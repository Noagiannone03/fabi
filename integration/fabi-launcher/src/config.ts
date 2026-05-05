// Résolution de la config Fabi (scheduler, modèle, options).
// Priorité décroissante : CLI flags > env > fichier user > fichier projet > défauts.

import { readFile } from "node:fs/promises"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

export interface FabiConfig {
  /**
   * URL HTTPS du scheduler Aircarto (OpenAI-compatible API).
   * Utilisée pour le healthcheck et plus tard pour configurer fabi-cli.
   * Sans trailing slash.
   */
  scheduler: string
  /**
   * Adresse Lattica/libp2p du scheduler (PeerID multiaddr) à passer à
   * `parallax join -s`. Valeur "auto" = découverte locale (LAN).
   * Différent de `scheduler` (URL HTTPS) car parallax parle en libp2p.
   */
  schedulerPeer: string
  /** Modèle à utiliser par défaut sur le swarm. */
  model: string
  /** Si true, on n'essaie pas de spawn parallax (mode dev / debug). */
  noParallax: boolean
  /** Si true, on n'essaie pas de lancer fabi-cli (utile pour tester juste le worker). */
  noCli: boolean
  /** Niveau de verbosité — affecte les logs internes. */
  verbose: boolean
  /** Chemin custom vers le binaire parallax (sinon auto-détecté dans PATH). */
  parallaxBin?: string
  /** Chemin custom vers le binaire fabi-cli (sinon auto-détecté). */
  fabiCliBin?: string
}

// Scheduler Aircarto en prod (serveur5, 37.59.98.16:3001, container parallax-scheduler).
// PeerID Lattica fixe — à mettre à jour si le scheduler est redéployé avec
// une nouvelle identité. Plus tard : auto-discovery via GET /swarm.json.
// Modèle = celui que le scheduler annonce dans /cluster/status_json.
export const DEFAULTS: FabiConfig = {
  scheduler:     "http://37.59.98.16:3001",
  schedulerPeer: "12D3KooWKLCTHRAhMEafQfaGZTAEx8kJjeMqpXDDeyhBGVotuSfR",
  model:         "Qwen/Qwen3-Coder-30B-A3B-Instruct",
  noParallax:    false,
  noCli:         false,
  verbose:       false,
}

/** Chemins de fichiers de config testés, dans l'ordre. */
function configPaths(): string[] {
  return [
    join(process.cwd(), ".fabi", "config.json"),       // projet
    join(homedir(), ".config", "fabi", "config.json"), // user
  ]
}

async function readJsonIfExists(path: string): Promise<Partial<FabiConfig> | null> {
  if (!existsSync(path)) return null
  try {
    const raw = await readFile(path, "utf-8")
    return JSON.parse(raw)
  } catch {
    return null
  }
}

function fromEnv(): Partial<FabiConfig> {
  const out: Partial<FabiConfig> = {}
  if (process.env.FABI_SCHEDULER)       out.scheduler     = process.env.FABI_SCHEDULER
  if (process.env.FABI_SCHEDULER_PEER)  out.schedulerPeer = process.env.FABI_SCHEDULER_PEER
  if (process.env.FABI_MODEL)           out.model         = process.env.FABI_MODEL
  if (process.env.FABI_NO_PARALLAX === "1") out.noParallax = true
  if (process.env.FABI_NO_CLI === "1")       out.noCli      = true
  if (process.env.FABI_VERBOSE === "1")      out.verbose    = true
  if (process.env.FABI_PARALLAX_BIN)    out.parallaxBin = process.env.FABI_PARALLAX_BIN
  if (process.env.FABI_CLI_BIN)         out.fabiCliBin  = process.env.FABI_CLI_BIN
  return out
}

/**
 * Parse les flags Fabi en stoppant à `--`. Tout ce qui vient après `--`
 * (ou tout flag inconnu) est renvoyé séparément, pour être passé à fabi-cli
 * en foreground sans interférence.
 */
function fromArgv(argv: string[]): { cfg: Partial<FabiConfig>; passthrough: string[] } {
  const cfg: Partial<FabiConfig> = {}
  const passthrough: string[] = []
  let stopped = false
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i]
    const next = argv[i + 1]
    if (stopped) { passthrough.push(a); continue }
    if (a === "--") { stopped = true; continue }
    switch (a) {
      case "--scheduler":      if (next) { cfg.scheduler     = next; i++ } break
      case "--scheduler-peer": if (next) { cfg.schedulerPeer = next; i++ } break
      case "--model":          if (next) { cfg.model         = next; i++ } break
      case "--parallax-bin":   if (next) { cfg.parallaxBin   = next; i++ } break
      case "--fabi-cli-bin":   if (next) { cfg.fabiCliBin    = next; i++ } break
      case "--no-parallax":    cfg.noParallax = true; break
      case "--no-cli":         cfg.noCli      = true; break
      case "-v":
      case "--verbose":        cfg.verbose    = true; break
      default:
        // Flag inconnu → passe-plat à fabi-cli (ainsi `fabi run "fix bug"` fonctionne).
        passthrough.push(a)
    }
  }
  return { cfg, passthrough }
}

export interface ResolvedConfig {
  cfg: FabiConfig
  /** Args inconnus du launcher, à transmettre tels quels à fabi-cli. */
  passthrough: string[]
}

export async function resolveConfig(argv: string[] = process.argv): Promise<ResolvedConfig> {
  // Lecture des fichiers, du moins prioritaire au plus prioritaire,
  // donc on les empile dans l'ordre projet d'abord PUIS user (user écrase projet).
  const layers: Partial<FabiConfig>[] = [DEFAULTS]
  for (const p of configPaths().reverse()) {
    const layer = await readJsonIfExists(p)
    if (layer) layers.push(layer)
  }
  layers.push(fromEnv())
  const { cfg: argvCfg, passthrough } = fromArgv(argv)
  layers.push(argvCfg)

  const merged = layers.reduce<FabiConfig>(
    (acc, layer) => ({ ...acc, ...layer }) as FabiConfig,
    DEFAULTS,
  )

  // Normalisation
  merged.scheduler = merged.scheduler.replace(/\/$/, "")
  return { cfg: merged, passthrough }
}
