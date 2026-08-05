import { describe, expect, test } from "bun:test"
import { connectionProfileFromEnvironment } from "./connection-profile"

const VALID = {
  FABI_WORKER_RELAY_URL: "https://relay.example:4443",
  FABI_WORKER_ENROLLMENT_URL: "https://registry.example/v1/network/enroll",
  FABI_WORKER_CATALOG_DHT_BOOTSTRAPS:
    '["/dns4/bootstrap.example/tcp/19191/p2p/12D3KooWExample"]',
  FABI_WORKER_MODEL_REGISTRY_ROOT_URL: "https://registry.example/tuf/1.root.json",
  FABI_WORKER_MODEL_REGISTRY_ROOT_SHA256: "ab".repeat(32),
  FABI_WORKER_MODEL_REGISTRY_METADATA_URL: "https://registry.example/tuf/metadata/",
  FABI_WORKER_MODEL_REGISTRY_TARGETS_URL: "https://registry.example/tuf/targets/",
}

describe("connectionProfileFromEnvironment", () => {
  test("publishes a complete secret-free V3 contract", () => {
    expect(connectionProfileFromEnvironment(VALID)).toEqual({
      protocolVersion: 3,
      catalogSchemaVersion: 3,
      transport: "iroh",
      relayUrl: "https://relay.example:4443",
      enrollmentUrl: "https://registry.example/v1/network/enroll",
      catalogDhtBootstraps: [
        "/dns4/bootstrap.example/tcp/19191/p2p/12D3KooWExample",
      ],
      modelRegistry: {
        rootUrl: "https://registry.example/tuf/1.root.json",
        rootSha256: "ab".repeat(32),
        metadataUrl: "https://registry.example/tuf/metadata/",
        targetsUrl: "https://registry.example/tuf/targets/",
      },
    })
  })

  test("fails closed for insecure URLs, missing DHT peers, or invalid root trust", () => {
    expect(() => connectionProfileFromEnvironment({
      ...VALID,
      FABI_WORKER_RELAY_URL: "http://relay.example:4443",
    })).toThrow("HTTPS")
    expect(() => connectionProfileFromEnvironment({
      ...VALID,
      FABI_WORKER_CATALOG_DHT_BOOTSTRAPS: "[]",
    })).toThrow("libp2p")
    expect(() => connectionProfileFromEnvironment({
      ...VALID,
      FABI_WORKER_MODEL_REGISTRY_ROOT_SHA256: "not-a-digest",
    })).toThrow("SHA-256")
  })
})
