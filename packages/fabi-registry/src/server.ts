// Serveur HTTP du fabi-registry. Utilise Bun.serve, sans framework.
//
// Endpoints :
//   GET /healthz         → 200 si le scanner a complété au moins un cycle
//   GET /v1/swarms       → SwarmsResponse (toujours 200, liste vide possible)
//   GET /v1/swarms/:id   → SwarmEntry ou 404
//   GET /v1/swarms/stream→ SSE (text/event-stream) : push de la liste à chaque
//                          changement (join/leave/peer count/status). Le client
//                          (IDE/CLI) s'abonne une fois via EventSource au lieu de
//                          poller — 1 poll interne (scanner) → N clients.
//
// CORS : autorisé pour tout origin (Cli fabi distant + futur dashboard web).
// Pas d'auth pour l'instant — l'endpoint est public en lecture seule.

import type { SwarmScanner } from "./scanner"
import type { SwarmsResponse } from "./types"

export interface ServerOptions {
  port: number
  host: string
  scanner: SwarmScanner
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
} as const

export function startHttpServer(opts: ServerOptions) {
  const { scanner, port, host } = opts

  const server = Bun.serve({
    port,
    hostname: host,
    async fetch(req) {
      const url = new URL(req.url, `http://${host}:${port}`)

      if (req.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS_HEADERS })
      }

      if (req.method !== "GET") {
        return jsonResponse(405, { error: "method_not_allowed" })
      }

      switch (url.pathname) {
        case "/":
        case "/healthz":
          return handleHealth(scanner)

        case "/v1/swarms":
          return handleListSwarms(scanner, host)

        case "/v1/swarms/stream":
          return handleStream(scanner, host)

        default: {
          // /v1/swarms/:id
          const m = url.pathname.match(/^\/v1\/swarms\/([^/]+)$/)
          if (m && m[1]) return handleGetSwarm(scanner, m[1])
          return jsonResponse(404, { error: "not_found", path: url.pathname })
        }
      }
    },
    error(err) {
      console.error("[server] unhandled error:", err)
      return jsonResponse(500, { error: "internal_server_error" })
    },
  })

  return server
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

function handleHealth(scanner: SwarmScanner): Response {
  // On considère le registry healthy dès qu'il a complété 1 scan
  // (même si le scan a trouvé 0 swarms — c'est l'état "pas de scheduler running",
  // qui est légitime).
  const swarms = scanner.snapshot()
  return jsonResponse(200, {
    status: "ok",
    swarmCount: swarms.length,
    timestamp: new Date().toISOString(),
  })
}

function handleListSwarms(scanner: SwarmScanner, host: string): Response {
  const swarms = scanner.snapshot()
  const generatedAt =
    swarms.length > 0
      ? swarms.reduce((latest, s) => (s.lastSeen > latest ? s.lastSeen : latest), swarms[0]!.lastSeen)
      : new Date().toISOString()
  const body: SwarmsResponse = {
    apiVersion: "v1",
    generatedAt,
    host,
    swarms,
  }
  return jsonResponse(200, body)
}

function handleStream(scanner: SwarmScanner, host: string): Response {
  // SSE : le client ouvre UNE connexion et reçoit la liste à chaque changement
  // (push), au lieu de poller en boucle. Le scanner (poll interne 10s) fan-out
  // à tous les abonnés → léger même avec beaucoup de clients.
  const encoder = new TextEncoder()
  let unsubscribe: () => void = () => {}
  let keepalive: ReturnType<typeof setInterval> | undefined

  const stream = new ReadableStream({
    start(controller) {
      const send = (swarms: ReturnType<SwarmScanner["snapshot"]>) => {
        const body: SwarmsResponse = {
          apiVersion: "v1",
          generatedAt: new Date().toISOString(),
          host,
          swarms,
        }
        try {
          controller.enqueue(encoder.encode(`event: swarms\ndata: ${JSON.stringify(body)}\n\n`))
        } catch {
          /* client parti entre deux : le cancel() nettoiera */
        }
      }
      // subscribe() émet immédiatement le snapshot courant, puis sur changement.
      unsubscribe = scanner.subscribe(send)
      // Commentaire SSE périodique pour garder la connexion ouverte à travers
      // les proxies (Caddy) sans dépendre d'un changement de données.
      keepalive = setInterval(() => {
        try {
          controller.enqueue(encoder.encode(`: keepalive\n\n`))
        } catch {
          /* idem */
        }
      }, 25_000)
    },
    cancel() {
      unsubscribe()
      if (keepalive) clearInterval(keepalive)
    },
  })

  return new Response(stream, {
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      // Demande aux proxies (Caddy/nginx) de ne pas bufferiser le flux.
      "X-Accel-Buffering": "no",
    },
  })
}

function handleGetSwarm(scanner: SwarmScanner, id: string): Response {
  const swarm = scanner.snapshot().find((s) => s.id === id)
  if (!swarm) {
    return jsonResponse(404, { error: "swarm_not_found", id })
  }
  return jsonResponse(200, swarm)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
      // Pas de cache — le contenu peut changer toutes les 5s
      "Cache-Control": "no-store",
    },
  })
}
