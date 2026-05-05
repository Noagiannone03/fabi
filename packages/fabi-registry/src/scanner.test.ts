// Test du scanner avec un client Docker simulé.

import { describe, expect, test } from "bun:test"
import { SwarmScanner } from "./scanner"
import type { DockerClient } from "./docker"

/** Mock minimal du DockerClient — on remplace seulement les 2 méthodes utilisées. */
function makeMockDocker(opts: {
  containers: Array<{ id: string; name: string; state: string; labels: Record<string, string> }>
  logsByContainer?: Record<string, string>
}): DockerClient {
  return {
    listFabiSwarmContainers: async () => opts.containers,
    getLogs: async (id: string) => opts.logsByContainer?.[id] ?? "",
  } as unknown as DockerClient
}

describe("SwarmScanner", () => {
  test("snapshot vide avant scan", () => {
    const scanner = new SwarmScanner(
      makeMockDocker({ containers: [] }),
      { logger: { error: () => {} } },
    )
    expect(scanner.snapshot()).toEqual([])
  })

  test("scanOnce sans containers → cache vide", async () => {
    const scanner = new SwarmScanner(
      makeMockDocker({ containers: [] }),
      { logger: { error: () => {} } },
    )
    await scanner.scanOnce()
    expect(scanner.snapshot()).toEqual([])
  })

  test("scanOnce avec un container et peer ID dans logs", async () => {
    const docker = makeMockDocker({
      containers: [
        {
          id: "abc123",
          name: "parallax-scheduler",
          state: "running",
          labels: {
            "fabi.swarm": "true",
            "fabi.swarm.id": "test-prod",
            "fabi.swarm.name": "Test Prod",
            "fabi.swarm.model": "Qwen/Test",
            // URL bidon : le healthcheck va échouer, on s'en fout pour ce test
            "fabi.swarm.url": "http://10.255.255.1:9999",
          },
        },
      ],
      logsByContainer: {
        abc123: "Stored scheduler peer id: 12D3KooWPEERTEST",
      },
    })
    const scanner = new SwarmScanner(docker, {
      healthcheckTimeoutMs: 100,
      logger: { error: () => {} },
    })
    await scanner.scanOnce()
    const snap = scanner.snapshot()
    expect(snap).toHaveLength(1)
    expect(snap[0]?.id).toBe("test-prod")
    expect(snap[0]?.schedulerPeer).toBe("12D3KooWPEERTEST")
    expect(snap[0]?.model).toBe("Qwen/Test")
    expect(snap[0]?.status).toBe("offline") // healthcheck a fail (URL bidon)
    expect(snap[0]?.peers).toBe(0)
  })

  test("purge un container disparu entre 2 scans", async () => {
    let containers = [
      {
        id: "abc",
        name: "c1",
        state: "running",
        labels: { "fabi.swarm": "true", "fabi.swarm.id": "swarm-1", "fabi.swarm.url": "" },
      },
    ]
    const docker = {
      listFabiSwarmContainers: async () => containers,
      getLogs: async () => "",
    } as unknown as DockerClient
    const scanner = new SwarmScanner(docker, { logger: { error: () => {} } })

    await scanner.scanOnce()
    expect(scanner.snapshot()).toHaveLength(1)

    containers = []
    await scanner.scanOnce()
    expect(scanner.snapshot()).toHaveLength(0)
  })

  test("erreur Docker → cache préservé, ne throw pas", async () => {
    const docker = {
      listFabiSwarmContainers: async () => {
        throw new Error("docker down")
      },
      getLogs: async () => "",
    } as unknown as DockerClient
    const scanner = new SwarmScanner(docker, { logger: { error: () => {} } })
    // Ne doit pas throw
    await scanner.scanOnce()
    expect(scanner.snapshot()).toEqual([])
  })
})
