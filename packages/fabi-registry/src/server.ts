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
import { RelayAccessError, type RelayAccessService } from "./relay-access"
import type { SwarmsResponse } from "./types"

export interface ServerOptions {
  port: number
  host: string
  scanner: SwarmScanner
  relayAccess: RelayAccessService
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
} as const

const MAX_ENROLLMENT_BODY_BYTES = 4 * 1024

export function startHttpServer(opts: ServerOptions) {
  const { scanner, relayAccess, port, host } = opts

  const server = Bun.serve({
    port,
    hostname: host,
    async fetch(req) {
      const url = new URL(req.url, `http://${host}:${port}`)

      if (req.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS_HEADERS })
      }

      if (url.pathname === "/v1/network/enroll") {
        if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" })
        return handleRelayEnrollment(req, relayAccess)
      }

      if (url.pathname === "/v1/network/relay-access") {
        if (req.method !== "POST") return new Response("false", { status: 405 })
        return handleRelayAccess(req, relayAccess)
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

async function handleRelayEnrollment(
  request: Request,
  relayAccess: RelayAccessService,
): Promise<Response> {
  const declaredLength = Number(request.headers.get("content-length") ?? "0")
  if (Number.isFinite(declaredLength) && declaredLength > MAX_ENROLLMENT_BODY_BYTES) {
    return jsonResponse(413, { error: "request_too_large" })
  }
  const body = await request.text()
  if (Buffer.byteLength(body, "utf8") > MAX_ENROLLMENT_BODY_BYTES) {
    return jsonResponse(413, { error: "request_too_large" })
  }
  let parsed: unknown
  try {
    parsed = JSON.parse(body)
  } catch {
    return jsonResponse(400, { error: "invalid_json" })
  }
  try {
    const lease = relayAccess.enroll(bearerToken(request), parsed)
    return jsonResponse(200, { apiVersion: "v1", lease })
  } catch (error) {
    if (error instanceof RelayAccessError) {
      return jsonResponse(error.status, { error: error.code })
    }
    throw error
  }
}

function handleRelayAccess(request: Request, relayAccess: RelayAccessService): Response {
  // This route is called only by iroh-relay. It deliberately returns the exact
  // lower-case body expected by iroh-relay 1.0.x and reveals no enrollment state
  // to callers that do not possess the private M2M bearer.
  if (!relayAccess.authenticateRelay(bearerToken(request))) {
    return new Response("false", { status: 401 })
  }
  // iroh-relay 1.0.3 documents `X-Iroh-Endpoint-Id`, but the released
  // binary's `X_IROH_ENDPOINT_ID` constant still emits `X-Iroh-NodeId`.
  // Accept both spellings so the registry works with the pinned release and
  // remains compatible when upstream aligns the wire header with its docs.
  const endpointId = request.headers.get("x-iroh-endpoint-id")
    ?? request.headers.get("x-iroh-nodeid")
  return new Response(relayAccess.isRelayAuthorized(endpointId) ? "true" : "false", {
    status: 200,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  })
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

function bearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization")
  const match = authorization?.match(/^Bearer[ \t]+([^\s]+)$/i)
  return match?.[1] ?? null
}
