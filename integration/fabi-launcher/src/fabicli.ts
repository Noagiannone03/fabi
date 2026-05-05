// Détection et spawn du fabi-cli (= fork OpenCode dans packages/fabi-cli).
//
// Stratégie de résolution, dans l'ordre :
//   1. cfg.fabiCliBin (CLI flag --fabi-cli-bin) ou env FABI_CLI_BIN
//   2. binaire embarqué dans dist/runtime/ (package Fabi utilisateur)
//   3. <meta-root>/packages/fabi-cli/packages/opencode/bin/opencode
//      → ce script Node cherche un binaire prebuilt dans node_modules ;
//        ne marche que si l'utilisateur a fait un `bun install` qui a tiré
//        le bon paquet `opencode-<platform>-<arch>`.
//   4. fallback dev : `bun run --conditions=browser src/index.ts` depuis
//      packages/fabi-cli/packages/opencode/ — marche en clone fresh tant
//      que `bun` est dans le PATH et que les deps sont installées.
//   5. `opencode` dans le PATH
//   6. null → le launcher reste en mode keep-alive avec un warning.

import { spawn, type ChildProcess } from "node:child_process"
import { existsSync, mkdirSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import type { FabiConfig } from "./config.js"
import { dim } from "./colors.js"

const HERE = dirname(fileURLToPath(import.meta.url))

export interface CliHandle {
  process: ChildProcess
  /** Résout avec le code de sortie (ou null si tué par signal). */
  exited: Promise<{ code: number | null; signal: NodeJS.Signals | null }>
  /** Forward un signal au CLI. Idempotent. */
  signal: (sig: NodeJS.Signals) => void
}

export interface CliResolution {
  command: string
  args: string[]
  cwd?: string
  /** Étiquette debug montrée dans les logs en --verbose. */
  source: "env-override" | "packaged-runtime" | "meta-tree-bin" | "meta-tree-dev" | "path"
  /**
   * Chemin absolu du fichier opencode.fabi.jsonc (config pré-baker du provider
   * Fabi) si on a pu le localiser. Sera posé en OPENCODE_CONFIG au spawn.
   */
  fabiConfigPath: string | null
}

/** Cherche la racine du méta-projet en remontant jusqu'à trouver packages/fabi-cli. */
function findMetaRoot(): string | null {
  // En dev (tsx) : src/fabicli.ts → integration/fabi-launcher/src → meta = HERE/../../..
  // Compilé    : dist/fabicli.js → integration/fabi-launcher/dist → meta = HERE/../../..
  const candidates = [
    join(HERE, "..", "..", ".."),
    join(HERE, "..", "..", "..", ".."),
    process.cwd(),
  ]
  for (const c of candidates) {
    if (existsSync(join(c, "packages", "fabi-cli", "packages", "opencode", "package.json"))) {
      return c
    }
  }
  return null
}

/**
 * Renvoie le chemin absolu du fichier opencode.fabi.jsonc (config pré-baker
 * qui déclare le provider Fabi). null si non trouvé (utile en mode standalone).
 */
function findFabiCliConfig(metaRoot: string | null): string | null {
  const candidates = [
    // Dev / npm link depuis le méta-repo.
    metaRoot ? join(metaRoot, "integration", "fabi-cli-config", "opencode.fabi.jsonc") : null,
    // Package npm : l'asset est copié à côté du build dans dist/config/.
    join(HERE, "config", "opencode.fabi.jsonc"),
    // Exécution directe depuis src/ pendant le dev.
    join(HERE, "..", "config", "opencode.fabi.jsonc"),
  ]
  for (const p of candidates) {
    if (p && existsSync(p)) return p
  }
  return null
}

/** Test rapide qu'un binaire est présent dans le PATH. */
async function inPath(name: string): Promise<string | null> {
  return await new Promise<string | null>((resolve) => {
    const which = process.platform === "win32" ? "where" : "which"
    const child = spawn(which, [name], { stdio: ["ignore", "pipe", "ignore"] })
    let out = ""
    child.stdout.on("data", (d: Buffer) => { out += d.toString() })
    child.on("close", (code) => {
      if (code !== 0) return resolve(null)
      const first = out.split(/\r?\n/).map(s => s.trim()).find(Boolean)
      resolve(first ?? null)
    })
    child.on("error", () => resolve(null))
  })
}

/** Renvoie comment lancer fabi-cli, ou null si introuvable. */
export async function resolveCli(
  cfg: FabiConfig,
  extraArgs: string[],
): Promise<CliResolution | null> {
  const meta = findMetaRoot()
  const fabiConfigPath = findFabiCliConfig(meta)

  // 1. Override explicite
  if (cfg.fabiCliBin) {
    if (!existsSync(cfg.fabiCliBin)) return null
    return { command: cfg.fabiCliBin, args: extraArgs, source: "env-override", fabiConfigPath }
  }

  const packaged = findPackagedRuntime()
  if (packaged) {
    return { command: packaged, args: extraArgs, source: "packaged-runtime", fabiConfigPath }
  }

  if (meta) {
    const opencodeDir = join(meta, "packages", "fabi-cli", "packages", "opencode")
    const binScript   = join(opencodeDir, "bin", "opencode")

    // 2. Le script Node bin/opencode (suppose que bun install a installé
    // le binaire prebuilt opencode-<platform>-<arch> dans node_modules).
    // On ne peut pas vérifier sans dupliquer sa logique de résolution, donc
    // on s'appuie sur le fait qu'il exit 1 si pas trouvé. Mais avant ça, on
    // teste l'existence d'au moins un node_modules dans l'arborescence : si
    // y'en a aucun, c'est un clone fresh, on saute à l'étape 3.
    if (existsSync(binScript) && hasInstalledOpencode(meta)) {
      return {
        command: process.execPath, // node
        args: [binScript, ...extraArgs],
        cwd: opencodeDir,
        source: "meta-tree-bin",
        fabiConfigPath,
      }
    }

    // 3. Fallback dev : `bun run` direct depuis les sources.
    const indexTs = join(opencodeDir, "src", "index.ts")
    if (existsSync(indexTs)) {
      const bun = await inPath("bun")
      if (bun) {
        return {
          command: bun,
          args: ["run", "--conditions=browser", indexTs, ...extraArgs],
          cwd: opencodeDir,
          source: "meta-tree-dev",
          fabiConfigPath,
        }
      }
    }
  }

  // 4. Installation globale d'opencode dans le PATH.
  // (On NE cherche PAS "fabi" : ce binaire = nous-mêmes → boucle infinie.)
  const opencodeInPath = await inPath("opencode")
  if (opencodeInPath) {
    return { command: opencodeInPath, args: extraArgs, source: "path", fabiConfigPath }
  }

  return null
}

function findPackagedRuntime(): string | null {
  const binary = process.platform === "win32" ? "opencode.exe" : "opencode"
  const candidates = [
    join(HERE, "runtime", binary),
    join(HERE, "..", "runtime", binary),
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  return null
}

/**
 * Heuristique légère : un node_modules contenant un paquet opencode-* prebuilt
 * existe-t-il ? Sinon le bin/opencode officiel exitera 1, donc on préfère
 * tomber direct sur le fallback bun.
 */
function hasInstalledOpencode(metaRoot: string): boolean {
  const places = [
    join(metaRoot, "packages", "fabi-cli", "node_modules"),
    join(metaRoot, "packages", "fabi-cli", "packages", "opencode", "node_modules"),
  ]
  for (const dir of places) {
    if (!existsSync(dir)) continue
    // Liste raccourcie des paquets prebuilt selon plateforme
    const candidates = [
      `opencode-${platformFolder()}-${archFolder()}`,
      `opencode-${platformFolder()}-${archFolder()}-baseline`,
    ]
    for (const c of candidates) {
      if (existsSync(join(dir, c, "bin"))) return true
    }
  }
  return false
}

function platformFolder(): string {
  const map: Record<string, string> = { darwin: "darwin", linux: "linux", win32: "windows" }
  return map[process.platform] ?? process.platform
}
function archFolder(): string {
  const map: Record<string, string> = { x64: "x64", arm64: "arm64", arm: "arm" }
  return map[process.arch] ?? process.arch
}

/** Spawn fabi-cli en foreground (TTY hérité). */
export function spawnCli(
  res: CliResolution,
  cfg: FabiConfig,
  log: (line: string) => void,
): CliHandle {
  if (cfg.verbose) {
    log(dim(`[fabi-cli] ${res.source}: ${res.command} ${res.args.join(" ")}`))
    if (res.fabiConfigPath) log(dim(`[fabi-cli] OPENCODE_CONFIG=${res.fabiConfigPath}`))
  }

  const fabiDataDir = join(process.env.XDG_DATA_HOME ?? join(homedir(), ".local", "share"), "fabi")
  mkdirSync(fabiDataDir, { recursive: true })

  // Construction de l'env transmis au CLI.
  // - On NE remplace JAMAIS un OPENCODE_CONFIG déjà posé par l'utilisateur.
  //   La config user est mergée par-dessus la nôtre côté opencode.
  // - FABI_SCHEDULER / FABI_MODEL restent transmis comme "indice" (utilisé
  //   par les scripts de monitoring ou de rebrand futur).
  const childEnv: NodeJS.ProcessEnv = {
    ...process.env,
    FABI_SCHEDULER:  cfg.scheduler,
    FABI_MODEL:      cfg.model,
    OPENCODE_DISABLE_AUTOUPDATE: "1",
    OPENCODE_CLIENT: process.env.OPENCODE_CLIENT ?? "fabi",
    OPENCODE_DB:     process.env.OPENCODE_DB ?? join(fabiDataDir, "fabi.db"),
  }
  if (res.fabiConfigPath && !process.env.OPENCODE_CONFIG) {
    childEnv.OPENCODE_CONFIG = res.fabiConfigPath
  }

  // stdio inherit → le CLI prend le TTY (clavier + couleurs). Process group
  // dédié pour pouvoir kill toute la descendance proprement.
  const child = spawn(res.command, res.args, {
    stdio: "inherit",
    detached: process.platform !== "win32",
    cwd: res.cwd,
    env: childEnv,
  })

  const exited = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>(
    (resolve) => {
      child.once("close", (code, signal) => resolve({ code, signal }))
      child.once("error", () => resolve({ code: 1, signal: null }))
    },
  )

  let signaled = false
  const signalChild = (sig: NodeJS.Signals): void => {
    if (signaled) return
    signaled = true
    try {
      if (process.platform !== "win32" && typeof child.pid === "number") {
        process.kill(-child.pid, sig)
      } else {
        child.kill(sig)
      }
    } catch { /* déjà mort */ }
  }

  return { process: child, exited, signal: signalChild }
}
