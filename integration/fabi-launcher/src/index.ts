#!/usr/bin/env node
// fabi-launcher : point d'entrée du binaire `fabi`.
//
// Cycle de vie :
//   1. lit la config (CLI flags > env > ~/.config/fabi/config.json > défauts)
//   2. healthcheck du scheduler (info, non bloquant)
//   3. spawn parallax worker (mode dégradé si binaire absent)
//   4. exec fabi-cli en foreground avec TTY hérité (mode keep-alive si CLI absent)
//   5. à l'exit du CLI : kill propre de parallax, propagation de l'exit code

import { resolveConfig } from "./config.js"
import { spawnWorker, checkScheduler, type WorkerHandle, type WorkerStatus } from "./parallax.js"
import { resolveCli, spawnCli } from "./fabicli.js"
import { showBanner, showStatus, showSeparator } from "./banner.js"
import { ok, warn, error as err, info, dim, sunset } from "./colors.js"

async function main(): Promise<void> {
  const { cfg, passthrough } = await resolveConfig(process.argv)
  showBanner({ scheduler: cfg.scheduler, model: cfg.model })

  // 1. Healthcheck scheduler — non bloquant, juste informatif
  const sched = await checkScheduler(cfg.scheduler, 3000)
  if (sched.reachable) {
    showStatus(ok(`scheduler joignable : ${cfg.scheduler}`))
    if (sched.model || typeof sched.nodeCount === "number" || sched.status) {
      const parts: string[] = []
      if (sched.status)                         parts.push(`status=${sched.status}`)
      if (typeof sched.nodeCount === "number")  parts.push(`workers=${sched.nodeCount}`)
      if (sched.model)                          parts.push(`model=${sched.model}`)
      showStatus(dim(`         ${parts.join("  ·  ")}`))
    }
  } else {
    showStatus(warn(`scheduler injoignable : ${cfg.scheduler}`))
    showStatus(dim(`         (Fabi peut continuer en mode dégradé)`))
  }

  // 2. Spawn parallax worker (sauf si --no-parallax)
  let worker: WorkerHandle | null = null
  if (cfg.noParallax) {
    showStatus(info(`mode --no-parallax : worker swarm désactivé`))
  } else {
    const onWorkerStatus = (s: WorkerStatus) => {
      switch (s.kind) {
        case "starting":
          showStatus(dim(`démarrage du worker parallax (-s ${cfg.schedulerPeer})…`))
          break
        case "missing-binary":
          showStatus(warn(`parallax non installé — mode autonome (pas de contribution swarm)`))
          showStatus(dim(`         install : cd packages/swarm-engine && pip install -e .`))
          break
        case "running":
          showStatus(ok(`worker parallax démarré (pid ${s.pid}) — tu contribues au swarm 🦦`))
          break
        case "exited":
          showStatus(warn(`worker parallax arrêté (code=${s.code} signal=${s.signal})`))
          break
        case "error":
          showStatus(err(`worker parallax : ${s.message}`))
          break
      }
    }
    worker = await spawnWorker(cfg, onWorkerStatus)
  }

  showSeparator()

  // 3. Préparer la cleanup avant tout exec foreground.
  let cleaningUp = false
  let lastExitCode = 0
  const cleanup = async (origin: string): Promise<void> => {
    if (cleaningUp) return
    cleaningUp = true
    showStatus(dim(`${origin} — déconnexion du swarm…`))
    if (worker) {
      await worker.stop()
      showStatus(ok(`worker parallax arrêté proprement`))
    }
    showStatus(sunset(`à bientôt sur Fabi 🦦`) + "\n")
  }

  // 4. Résoudre fabi-cli. Si trouvé : exec foreground. Sinon : keep-alive.
  let cliFound = false
  if (!cfg.noCli) {
    const cliRes = await resolveCli(cfg, passthrough)
    if (cliRes) {
      cliFound = true
      showStatus(ok(`fabi-cli prêt (${cliRes.source})`))
      if (cliRes.fabiConfigPath) {
        showStatus(dim(`         config Fabi : ${cliRes.fabiConfigPath}`))
      } else {
        showStatus(warn(`         pas de opencode.fabi.jsonc trouvé — fabi-cli n'aura PAS le provider Fabi par défaut`))
        showStatus(dim(`         (lance fabi depuis la racine du méta-projet, ou pose OPENCODE_CONFIG manuellement)`))
      }
      if (process.env.OPENCODE_CONFIG && cliRes.fabiConfigPath) {
        showStatus(dim(`         (OPENCODE_CONFIG déjà posé par l'utilisateur — on respecte)`))
      }
      process.stdout.write("\n")

      const cli = spawnCli(cliRes, cfg, showStatus)

      // Forward signaux vers le CLI : laisse-le saver son état avant de mourir.
      // Quand le CLI exit, le finally ci-dessous tue parallax.
      const forward = (sig: NodeJS.Signals) => () => cli.signal(sig)
      const onSigInt  = forward("SIGINT")
      const onSigTerm = forward("SIGTERM")
      const onSigHup  = forward("SIGHUP")
      process.on("SIGINT",  onSigInt)
      process.on("SIGTERM", onSigTerm)
      process.on("SIGHUP",  onSigHup)

      // Si le worker meurt en arrière-plan, on note mais on n'interrompt pas
      // l'utilisateur dans son CLI — il décidera s'il veut quitter.
      worker?.process.on("close", () => {
        if (cleaningUp) return
        process.stderr.write(
          dim(`\n  [fabi] le worker parallax est sorti — tu n'es plus connecté au swarm\n`),
        )
      })

      const { code, signal } = await cli.exited
      lastExitCode = typeof code === "number" ? code : (signal ? 130 : 0)

      // Détache les listeners temporaires pour que cleanup() puisse écrire en paix
      process.off("SIGINT",  onSigInt)
      process.off("SIGTERM", onSigTerm)
      process.off("SIGHUP",  onSigHup)

      process.stdout.write("\n")
      await cleanup(`fabi-cli a quitté (code=${code} signal=${signal ?? "-"})`)
      process.exit(lastExitCode)
    }
  }

  // 5. Mode keep-alive : pas de CLI dispo (ou --no-cli). Utile en phase de
  // dev pour tester juste la mécanique parallax + signaux.
  if (!cliFound && !cfg.noCli) {
    showStatus(warn(`fabi-cli introuvable — lance \`bun install\` dans packages/fabi-cli/`))
    showStatus(dim(`         ou pose FABI_CLI_BIN=/chemin/vers/opencode`))
  }
  if (cfg.noCli) {
    showStatus(info(`mode --no-cli : pas de TUI lancée`))
  }
  showStatus(info(`prêt — Ctrl+C pour quitter et déconnecter le worker`))
  process.stdout.write("\n")

  const onSignal = (sig: string) => async () => {
    process.stdout.write("\n")
    await cleanup(`reçu ${sig}`)
    process.exit(0)
  }
  process.on("SIGINT",  onSignal("SIGINT"))
  process.on("SIGTERM", onSignal("SIGTERM"))
  process.on("SIGHUP",  onSignal("SIGHUP"))

  worker?.process.on("close", () => {
    showStatus(warn(`le worker parallax est sorti — on continue en mode autonome`))
  })

  // Keep-alive : pas d'exit naturel tant qu'aucun signal n'arrive.
  const keepAlive = setInterval(() => { /* idle */ }, 1 << 30)
  void keepAlive
}

main().catch((e: unknown) => {
  process.stderr.write(`\nErreur fatale: ${(e as Error).message}\n`)
  process.exit(1)
})
