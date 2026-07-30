// Test du scanner avec un client Docker simulé.

import { describe, expect, test } from "bun:test"
import { SwarmScanner, parseSchedulerStatus } from "./scanner"
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
  test("normalise le contrat réel du scheduler c54", () => {
    const status = parseSchedulerStatus({
      type: "cluster_status",
      data: {
        status: "available",
        prefill_contract_ready: true,
        max_supported_context_tokens: 32768,
        node_list: [
          { status: "available", gpu_memory: 16, max_sequence_length: 32768 },
          { status: "available", gpu_memory: 16, max_sequence_length: 32768 },
        ],
      },
    })
    expect(status).toMatchObject({
      online: true,
      applicationStatus: "available",
      peers: 2,
      totalVramGb: 32,
      maxContextTokens: 32768,
      nodesActive: 2,
      nodesInitializing: 0,
      pipelineReady: true,
      routingReady: true,
    })
  })

  test("reste compatible avec les champs de télémétrie historiques", () => {
    const status = parseSchedulerStatus({
      data: {
        status: "waiting",
        max_context_tokens: 16384,
        pipeline_ready: false,
        routing_ready: false,
        node_list: [{ node_state: "active", loading_phase: "initializing", gpu_memory: 8 }],
      },
    })
    expect(status.maxContextTokens).toBe(16384)
    expect(status.nodesActive).toBe(1)
    expect(status.nodesInitializing).toBe(1)
    expect(status.pipelineReady).toBe(false)
  })

  test("utilise le verdict de route v3 et l'identité Iroh explicite", () => {
    const endpointId = "e888178432676f45ab58c92df4d0528ed6e867bb0da5fa8b1d717789ca37b625"
    const modelSwarmId = "46e338001cbca3a457b8e513950d62cc10fc7866226529e7b27825a737797b57"
    const status = parseSchedulerStatus({
      data: {
        status: "available",
        // Ces champs appartiennent au chemin de placement v2 et ne doivent
        // pas rendre indisponible une route v3 active.
        prefill_contract_ready: false,
        pipeline_ready: false,
        routing_ready: false,
        scheduler_endpoint_id: endpointId,
        network_transport: "iroh",
        swarm_v3_shadow: {
          mode: "active",
          state: "route_ready",
          catalog: {
            state: "snapshot_ready",
            model_swarm_id: modelSwarmId,
            workers: 2,
          },
          v3_route: ["mac", "rtx"],
        },
        node_list: [
          { status: "available", gpu_memory: 5.2 },
          { status: "available", gpu_memory: 13.4 },
        ],
      },
    })

    expect(status).toMatchObject({
      schedulerPeer: endpointId,
      modelSwarmId,
      networkTransport: "iroh",
      pipelineReady: true,
      routingReady: true,
    })
  })

  test("ne publie jamais une identité de modèle v3 mal formée", () => {
    for (const invalid of [
      "46e338",
      "46E338001CBCA3A457B8E513950D62CC10FC7866226529E7B27825A737797B57",
      "z6e338001cbca3a457b8e513950d62cc10fc7866226529e7b27825a737797b57",
    ]) {
      const status = parseSchedulerStatus({
        data: {
          status: "available",
          swarm_v3_shadow: {
            mode: "active",
            state: "route_ready",
            catalog: {
              state: "snapshot_ready",
              model_swarm_id: invalid,
            },
          },
        },
      })
      expect(status.modelSwarmId).toBeUndefined()
    }
  })

  test("refuse de déclarer prête une route v3 qui ne l'est pas", () => {
    const status = parseSchedulerStatus({
      data: {
        status: "available",
        swarm_v3_shadow: { mode: "active", state: "no_feasible_route" },
      },
    })

    expect(status.pipelineReady).toBe(false)
    expect(status.routingReady).toBe(false)
  })

  test("distingue un pipeline v3 chargé d'une route momentanément saturée", () => {
    const status = parseSchedulerStatus({
      data: {
        status: "waiting",
        structural_pipeline_ready: true,
        admission_ready: false,
        max_supported_context_tokens: 16384,
        swarm_v3_shadow: {
          mode: "active",
          state: "no_feasible_route",
        },
        swarm_v3_execution: {
          active_routes: [{ request_id: "busy-request" }],
        },
        node_list: [
          { status: "available", gpu_memory: 16 },
          { status: "available", gpu_memory: 16 },
        ],
      },
    })

    expect(status).toMatchObject({
      applicationStatus: "waiting",
      maxContextTokens: 16384,
      pipelineReady: true,
      routingReady: false,
      nodesActive: 2,
    })
  })

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
