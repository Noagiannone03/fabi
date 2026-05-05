// Gestion du sous-process parallax : détection, spawn, surveillance, arrêt propre.

import { spawn, type ChildProcess } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import type { FabiConfig } from "./config.js"
import { dim } from "./colors.js"

const HERE = dirname(fileURLToPath(import.meta.url))

export type WorkerStatus =
  | { kind: "starting" }
  | { kind: "running"; pid: number }
  | { kind: "missing-binary" }
  | { kind: "exited"; code: number | null; signal: NodeJS.Signals | null }
  | { kind: "error"; message: string }

export interface WorkerHandle {
  process: ChildProcess
  pid: number
  /** Stoppe proprement (SIGTERM puis SIGKILL après 5s). Idempotent. */
  stop: () => Promise<void>
}

/** Cherche le binaire parallax dans le PATH (sync, peu coûteux au boot). */
async function findParallaxBin(override?: string): Promise<string | null> {
  if (override) return existsSync(override) ? override : null

  const managed = findManagedParallaxBin()
  if (managed) return managed

  return await new Promise<string | null>((resolve) => {
    const which = process.platform === "win32" ? "where" : "which"
    const child = spawn(which, ["parallax"], {
      stdio: ["ignore", "pipe", "ignore"],
    })
    let out = ""
    child.stdout.on("data", (d: Buffer) => { out += d.toString() })
    child.on("close", (code) => {
      if (code === 0) {
        const first = out.split(/\r?\n/).map(s => s.trim()).find(Boolean)
        resolve(first ?? null)
      } else {
        resolve(null)
      }
    })
    child.on("error", () => resolve(null))
  })
}

function findManagedParallaxBin(): string | null {
  const binary = process.platform === "win32" ? "parallax.exe" : "parallax"
  const dataRoot = process.env.XDG_DATA_HOME ?? join(homedir(), ".local", "share")
  const candidates = [
    join(HERE, "runtime", binary),
    join(HERE, "..", "runtime", binary),
    join(dataRoot, "fabi", "runtime", binary),
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  return null
}

/**
 * Spawn le worker parallax. Renvoie null si parallax n'est pas trouvé
 * (le launcher continuera alors en mode autonome).
 */
export async function spawnWorker(
  cfg: FabiConfig,
  onStatus: (s: WorkerStatus) => void,
): Promise<WorkerHandle | null> {
  onStatus({ kind: "starting" })

  const bin = await findParallaxBin(cfg.parallaxBin)
  if (!bin) {
    onStatus({ kind: "missing-binary" })
    return null
  }

  // `parallax join -s` veut une PeerID Lattica (ou "auto" pour LAN),
  // PAS l'URL HTTPS du scheduler — c'est un réseau libp2p.
  const args = ["join", "-s", cfg.schedulerPeer]
  // Process group dédié → on peut tuer toute la descendance d'un coup
  // (utile si parallax fork des sous-process GPU).
  const child = spawn(bin, args, {
    stdio: ["ignore", "pipe", "pipe"],
    detached: process.platform !== "win32",
    env: process.env,
  })

  // En détaché, on doit unref pour que le process parent n'attende pas
  // l'enfant lors d'un exit normal — mais on le track quand même via stop().
  if (child.unref) child.unref()

  const pid = child.pid
  if (typeof pid !== "number") {
    onStatus({ kind: "error", message: "spawn parallax sans PID — échec immédiat" })
    return null
  }

  onStatus({ kind: "running", pid })

  // Capture des sorties pour debug si --verbose
  if (cfg.verbose) {
    child.stdout?.on("data", (d: Buffer) => {
      const text = d.toString().trimEnd()
      if (text) process.stderr.write(dim(`[parallax] ${text}\n`))
    })
    child.stderr?.on("data", (d: Buffer) => {
      const text = d.toString().trimEnd()
      if (text) process.stderr.write(dim(`[parallax!] ${text}\n`))
    })
  } else {
    child.stdout?.on("data", () => {})
    child.stderr?.on("data", () => {})
  }

  child.on("close", (code, signal) => {
    onStatus({ kind: "exited", code, signal })
  })
  child.on("error", (err) => {
    onStatus({ kind: "error", message: err.message })
  })

  let stopped = false
  const stop = async (): Promise<void> => {
    if (stopped) return
    stopped = true

    return new Promise<void>((resolve) => {
      let done = false
      const finish = () => {
        if (done) return
        done = true
        resolve()
      }
      child.once("close", finish)

      try {
        // Tue tout le process group (négatif = group)
        if (process.platform !== "win32" && pid) {
          process.kill(-pid, "SIGTERM")
        } else {
          child.kill("SIGTERM")
        }
      } catch {
        // déjà mort
        finish()
        return
      }

      // Force-kill après 5s si toujours vivant
      setTimeout(() => {
        if (done) return
        try {
          if (process.platform !== "win32" && pid) {
            process.kill(-pid, "SIGKILL")
          } else {
            child.kill("SIGKILL")
          }
        } catch { /* déjà mort */ }
        finish()
      }, 5000).unref()
    })
  }

  return { process: child, pid, stop }
}

export interface SchedulerInfo {
  reachable: boolean
  /** Statut du cluster ("waiting", "ready", etc.) si dispo. */
  status?: string
  /** Modèle servi par le scheduler. */
  model?: string
  /** Nb de workers connectés au swarm. */
  nodeCount?: number
}

/**
 * Healthcheck du scheduler via /cluster/status_json (route exposée par le
 * scheduler Parallax). Renvoie aussi des infos cluster utiles à afficher.
 */
export async function checkScheduler(scheduler: string, timeoutMs = 3000): Promise<SchedulerInfo> {
  try {
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), timeoutMs)
    const res = await fetch(`${scheduler}/cluster/status_json`, {
      method: "GET",
      signal: ctrl.signal,
    })
    clearTimeout(timer)
    if (!res.ok) return { reachable: false }
    const json = await res.json() as {
      data?: { status?: string; model_name?: string; node_list?: unknown[] }
    }
    const data = json.data ?? {}
    return {
      reachable: true,
      status:    data.status,
      model:     data.model_name,
      nodeCount: Array.isArray(data.node_list) ? data.node_list.length : undefined,
    }
  } catch {
    return { reachable: false }
  }
}
