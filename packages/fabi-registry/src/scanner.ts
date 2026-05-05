// Scanner : boucle qui interroge Docker + le scheduler Parallax pour
// construire la liste des swarms en temps réel.
//
// Cycle (toutes les `intervalMs`) :
//   1. Lister les containers Docker avec label fabi.swarm=true
//   2. Pour chaque, extraire labels statiques (id, name, model, url)
//   3. Lire les logs récents pour trouver "Stored scheduler peer id: ..."
//   4. Healthcheck via GET <url>/cluster/status_json
//   5. Mettre à jour le cache en mémoire
//
// Le cache est lu de manière synchrone par le serveur HTTP. La boucle est
// non-bloquante — un scheduler down n'empêche pas les autres d'être listés.

import { DockerClient, extractPeerIdFromLogs, DockerError } from "./docker"
import type { SwarmEntry } from "./types"

export interface ScannerOptions {
  /** Intervalle entre deux scans complets (défaut 5s). */
  intervalMs?: number
  /** Timeout pour le healthcheck d'un scheduler individuel (défaut 3s). */
  healthcheckTimeoutMs?: number
  /** Combien de lignes de logs Docker on lit pour grep le peer ID. */
  logTailLines?: number
  /** Logger optionnel (sinon console.error). */
  logger?: { error: (msg: string, ...args: unknown[]) => void }
}

interface SchedulerStatus {
  online: boolean
  applicationStatus: string | null
  peers: number
  totalVramGb: number
}

export class SwarmScanner {
  private readonly docker: DockerClient
  private readonly intervalMs: number
  private readonly healthcheckTimeoutMs: number
  private readonly logTailLines: number
  private readonly logger: { error: (msg: string, ...args: unknown[]) => void }

  /** Cache des swarms — mis à jour après chaque scan. Lecture O(1). */
  private cache: Map<string, SwarmEntry> = new Map()

  /** Timer du loop — null si pas démarré. */
  private timer: ReturnType<typeof setInterval> | null = null

  /** Date du premier scan complété (utile pour le 1er affichage `--once`). */
  private firstScanComplete: Promise<void>
  private resolveFirstScan!: () => void

  constructor(docker: DockerClient, opts: ScannerOptions = {}) {
    this.docker = docker
    this.intervalMs = opts.intervalMs ?? 5_000
    this.healthcheckTimeoutMs = opts.healthcheckTimeoutMs ?? 3_000
    this.logTailLines = opts.logTailLines ?? 500
    this.logger = opts.logger ?? console
    this.firstScanComplete = new Promise((resolve) => {
      this.resolveFirstScan = resolve
    })
  }

  /** Snapshot synchrone du cache (à appeler depuis le serveur HTTP). */
  snapshot(): SwarmEntry[] {
    return Array.from(this.cache.values()).sort((a, b) => a.id.localeCompare(b.id))
  }

  /** Promesse qui résout après le tout premier scan. Utile au démarrage. */
  waitForFirstScan(): Promise<void> {
    return this.firstScanComplete
  }

  /**
   * Démarre le loop. Idempotent — appelable une seule fois.
   * Lance immédiatement un scan, puis répète à intervalMs.
   */
  async start(): Promise<void> {
    if (this.timer !== null) return
    // 1er scan immédiat (await pour qu'on ait des données dès le boot HTTP)
    await this.scanOnce()
    this.resolveFirstScan()
    this.timer = setInterval(() => {
      void this.scanOnce()
    }, this.intervalMs)
  }

  /** Stoppe le loop. Idempotent. */
  stop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  /**
   * Effectue un scan complet et met à jour le cache.
   * Ne throw jamais — toute erreur est logguée et le scan continue.
   */
  async scanOnce(): Promise<void> {
    let containers
    try {
      containers = await this.docker.listFabiSwarmContainers()
    } catch (err) {
      if (err instanceof DockerError) {
        this.logger.error(`[scanner] docker unreachable: ${err.message}`)
      } else {
        this.logger.error(`[scanner] unexpected error listing containers`, err)
      }
      return
    }

    // Containers vus dans ce scan, pour purger ceux disparus
    const seen = new Set<string>()

    // Scanne chaque container en parallèle (peer ID + healthcheck indépendants)
    await Promise.all(
      containers.map(async (c) => {
        const id = c.labels["fabi.swarm.id"] ?? c.name
        seen.add(id)
        const entry = await this.buildEntry(c)
        this.cache.set(entry.id, entry)
      }),
    )

    // Purge les entrées qui ne correspondent plus à un container actif
    for (const cachedId of this.cache.keys()) {
      if (!seen.has(cachedId)) {
        this.cache.delete(cachedId)
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Construction d'une entrée swarm
  // ---------------------------------------------------------------------------

  private async buildEntry(container: {
    id: string
    name: string
    state: string
    labels: Record<string, string>
  }): Promise<SwarmEntry> {
    const id = container.labels["fabi.swarm.id"] ?? container.name
    const name = container.labels["fabi.swarm.name"] ?? id
    const model = container.labels["fabi.swarm.model"] ?? ""
    const schedulerUrl = (container.labels["fabi.swarm.url"] ?? "").replace(/\/+$/, "")

    // Peer ID via parse des logs — résilient si Parallax restart (on relit)
    let schedulerPeer: string | null = null
    try {
      const logs = await this.docker.getLogs(container.id, this.logTailLines)
      schedulerPeer = extractPeerIdFromLogs(logs)
    } catch (err) {
      this.logger.error(`[scanner] log read failed for ${id}:`, (err as Error).message)
    }

    // Healthcheck du scheduler — données dynamiques
    let health: SchedulerStatus = {
      online: false,
      applicationStatus: null,
      peers: 0,
      totalVramGb: 0,
    }
    if (schedulerUrl) {
      health = await this.healthcheck(schedulerUrl)
    }

    const status: SwarmEntry["status"] = !schedulerUrl
      ? "unknown"
      : health.online
        ? "online"
        : "offline"

    return {
      id,
      name,
      schedulerUrl,
      schedulerPeer,
      model,
      status,
      schedulerStatus: health.applicationStatus,
      peers: health.peers,
      totalVramGb: health.totalVramGb,
      lastSeen: new Date().toISOString(),
      containerName: container.name,
    }
  }

  /**
   * Healthcheck d'un scheduler Parallax. Ne throw jamais — tout problème
   * → online: false. Timeout configurable.
   */
  private async healthcheck(schedulerUrl: string): Promise<SchedulerStatus> {
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), this.healthcheckTimeoutMs)
    try {
      const res = await fetch(`${schedulerUrl}/cluster/status_json`, {
        method: "GET",
        signal: ctrl.signal,
      })
      if (!res.ok) return { online: false, applicationStatus: null, peers: 0, totalVramGb: 0 }
      const json = (await res.json()) as {
        data?: {
          status?: string
          node_list?: Array<{ gpu_memory?: number }>
        }
      }
      const data = json.data ?? {}
      const nodeList = Array.isArray(data.node_list) ? data.node_list : []
      const totalVramGb = nodeList.reduce(
        (acc, n) => acc + (typeof n.gpu_memory === "number" ? n.gpu_memory : 0),
        0,
      )
      return {
        online: true,
        applicationStatus: data.status ?? null,
        peers: nodeList.length,
        totalVramGb: Math.round(totalVramGb * 10) / 10,
      }
    } catch {
      return { online: false, applicationStatus: null, peers: 0, totalVramGb: 0 }
    } finally {
      clearTimeout(timer)
    }
  }
}
