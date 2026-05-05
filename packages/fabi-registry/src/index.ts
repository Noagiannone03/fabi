// fabi-registry — point d'entrée.
//
// Orchestre le scanner Docker et le serveur HTTP. Configurable via env :
//   FABI_REGISTRY_PORT        (défaut: 3002)
//   FABI_REGISTRY_HOST        (défaut: "0.0.0.0")
//   FABI_REGISTRY_INTERVAL_MS (défaut: 5000)
//   FABI_DOCKER_SOCKET        (défaut: /var/run/docker.sock)
//
// Logs : stdout pour info, stderr pour erreurs. Format simple, pas de JSON
// — ce n'est pas un service de production critique au sens strict, et
// `journalctl -u fabi-registry` reste lisible.

import { DockerClient } from "./docker"
import { SwarmScanner } from "./scanner"
import { startHttpServer } from "./server"

const PORT = Number(process.env.FABI_REGISTRY_PORT ?? "3002")
const HOST = process.env.FABI_REGISTRY_HOST ?? "0.0.0.0"
const INTERVAL_MS = Number(process.env.FABI_REGISTRY_INTERVAL_MS ?? "5000")

async function main(): Promise<void> {
  if (Number.isNaN(PORT) || PORT <= 0 || PORT > 65535) {
    throw new Error(`Invalid FABI_REGISTRY_PORT: ${process.env.FABI_REGISTRY_PORT}`)
  }
  if (Number.isNaN(INTERVAL_MS) || INTERVAL_MS < 500) {
    throw new Error(`Invalid FABI_REGISTRY_INTERVAL_MS: must be >= 500ms`)
  }

  const docker = new DockerClient()
  const scanner = new SwarmScanner(docker, { intervalMs: INTERVAL_MS })

  console.log(`[fabi-registry] scanning Docker every ${INTERVAL_MS}ms`)
  await scanner.start()
  const initial = scanner.snapshot()
  console.log(`[fabi-registry] initial scan found ${initial.length} swarm(s)`)
  for (const s of initial) {
    console.log(
      `  - ${s.id} (${s.status}) peer=${s.schedulerPeer ?? "?"} peers=${s.peers} vram=${s.totalVramGb}GB`,
    )
  }

  const server = startHttpServer({ port: PORT, host: HOST, scanner })
  console.log(`[fabi-registry] listening on http://${HOST}:${PORT}`)

  // Graceful shutdown — important pour systemd qui envoie SIGTERM au stop
  const shutdown = (sig: NodeJS.Signals) => {
    console.log(`[fabi-registry] received ${sig}, shutting down`)
    scanner.stop()
    server.stop()
    process.exit(0)
  }
  process.on("SIGINT", () => shutdown("SIGINT"))
  process.on("SIGTERM", () => shutdown("SIGTERM"))
}

main().catch((err) => {
  console.error("[fabi-registry] fatal:", err)
  process.exit(1)
})
