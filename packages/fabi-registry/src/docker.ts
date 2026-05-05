// Client minimal pour l'API Docker Engine, parlée via le socket UNIX
// `/var/run/docker.sock`. Pas de dépendance externe : on parle HTTP/1.1
// directement à travers un Unix socket avec `fetch` Bun (qui supporte le
// scheme `unix:` natif).
//
// Pourquoi pas dockerode ? Une dépendance Node + types pour 3 endpoints,
// alors que l'API Docker est stable et minimaliste. On reste léger.
//
// Endpoints utilisés :
//   - GET /containers/json?filters=...   → liste les containers actifs
//   - GET /containers/<id>/logs?...      → logs (texte ou stream)

import type { SwarmEntry } from "./types"

/** Socket Unix par défaut du Docker daemon. Override via `FABI_DOCKER_SOCKET`. */
const DEFAULT_SOCKET = "/var/run/docker.sock"

/** Schéma minimal d'un container retourné par GET /containers/json. */
interface ContainerSummary {
  Id: string
  Names: string[]
  Labels?: Record<string, string>
  State: string
  Status: string
}

/** Ce qu'on a besoin de savoir sur un container scheduler après scan. */
export interface SchedulerContainer {
  id: string
  name: string
  state: string
  labels: Record<string, string>
}

/**
 * Client Docker. Stateless, instancie une fois au démarrage.
 */
export class DockerClient {
  private readonly socketPath: string

  constructor(socketPath: string = process.env.FABI_DOCKER_SOCKET ?? DEFAULT_SOCKET) {
    this.socketPath = socketPath
  }

  /**
   * Liste les containers (running uniquement par défaut) qui ont le label
   * `fabi.swarm=true`. Renvoie une liste vide si aucun, throw si Docker injoignable.
   */
  async listFabiSwarmContainers(): Promise<SchedulerContainer[]> {
    // Docker accepte un filtre `label=key=value` URL-encoded en JSON
    const filters = JSON.stringify({ label: ["fabi.swarm=true"] })
    const path = `/containers/json?filters=${encodeURIComponent(filters)}`
    const containers = await this.request<ContainerSummary[]>("GET", path)
    return containers.map((c) => ({
      id: c.Id,
      name: c.Names[0]?.replace(/^\//, "") ?? c.Id.slice(0, 12),
      state: c.State,
      labels: c.Labels ?? {},
    }))
  }

  /**
   * Récupère un buffer de logs récents pour le container donné.
   *
   * Note : l'API Docker stream les logs en multiplexant stdout/stderr via un
   * format binaire (header de 8 bytes par chunk). Pour parser proprement on
   * utiliserait ce framing, mais pour notre cas — grep d'une string connue
   * — un dé-mux best-effort suffit : on strip les headers visiblement binaires.
   *
   * @param tailLines limite de lignes (par stream) — Docker accepte "all" ou un nombre
   */
  async getLogs(containerId: string, tailLines: number | "all" = 500): Promise<string> {
    const params = new URLSearchParams({
      stdout: "true",
      stderr: "true",
      timestamps: "false",
      tail: String(tailLines),
    })
    const raw = await this.request<string>("GET", `/containers/${containerId}/logs?${params}`, {
      asText: true,
    })
    return demuxDockerLogs(raw)
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  private async request<T>(
    method: string,
    path: string,
    opts: { asText?: boolean } = {},
  ): Promise<T> {
    // Bun supporte le scheme `unix:` pour fetch. Le format est :
    //   http://localhost/path  +  unix: <socket-path>
    // via l'option `unix` (Bun-only).
    const url = `http://localhost${path}`
    const res = await fetch(url, {
      method,
      unix: this.socketPath,
    })
    if (!res.ok) {
      throw new DockerError(
        `Docker API ${method} ${path} → ${res.status} ${res.statusText}`,
        res.status,
      )
    }
    if (opts.asText) {
      return (await res.text()) as T
    }
    return (await res.json()) as T
  }
}

export class DockerError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
  ) {
    super(message)
    this.name = "DockerError"
  }
}

/**
 * Démultiplexe le flux de logs Docker (format binaire 8-byte header par frame)
 * en best-effort. On extrait juste le texte ASCII/UTF-8 utile pour grep.
 *
 * Format de chaque frame :
 *   byte 0     : stream type (0=stdin, 1=stdout, 2=stderr)
 *   bytes 1-3  : padding (0x00)
 *   bytes 4-7  : longueur big-endian du payload
 *   bytes 8..  : payload
 */
function demuxDockerLogs(raw: string): string {
  // Si le serveur a négocié un transport non multiplexé (TTY enabled), c'est
  // déjà du texte propre. Heuristique : on regarde si le 1er char est un
  // marker valide (0x00, 0x01, 0x02). Sinon on retourne tel quel.
  if (raw.length === 0) return raw
  const c0 = raw.charCodeAt(0)
  if (c0 !== 0 && c0 !== 1 && c0 !== 2) return raw

  // Strip les headers de 8 bytes — naïf mais suffisant pour grep.
  // Note: ASCII safe ; pour de l'unicode complexe on utiliserait Uint8Array.
  let out = ""
  let i = 0
  while (i < raw.length) {
    const stream = raw.charCodeAt(i)
    if (stream !== 0 && stream !== 1 && stream !== 2) {
      // Pas de header valide ici — on ajoute le reste tel quel
      out += raw.slice(i)
      break
    }
    if (i + 8 > raw.length) break
    const len =
      (raw.charCodeAt(i + 4) << 24) |
      (raw.charCodeAt(i + 5) << 16) |
      (raw.charCodeAt(i + 6) << 8) |
      raw.charCodeAt(i + 7)
    out += raw.slice(i + 8, i + 8 + len)
    i += 8 + len
  }
  return out
}

// ---------------------------------------------------------------------------
// Helpers haut niveau utilisés par le scanner
// ---------------------------------------------------------------------------

/** Regex stable matching la ligne loggée par Parallax au démarrage. */
const PEER_ID_LOG_RE = /Stored scheduler peer id:\s*([A-Za-z0-9]+)/

/**
 * Cherche dans les logs l'identifiant peer du scheduler.
 *
 * Si plusieurs occurrences (rare — ne devrait apparaître qu'une fois par boot),
 * on retourne la **dernière** : le scheduler a été redémarré et la valeur
 * la plus à jour est la bonne.
 */
export function extractPeerIdFromLogs(logs: string): string | null {
  let lastMatch: string | null = null
  // Itère sur toutes les matches pour récupérer la plus récente
  const lines = logs.split("\n")
  for (const line of lines) {
    const m = line.match(PEER_ID_LOG_RE)
    if (m && m[1]) lastMatch = m[1]
  }
  return lastMatch
}

/** Pour faciliter les tests unitaires depuis l'extérieur. */
export const _internals = { PEER_ID_LOG_RE, demuxDockerLogs }
