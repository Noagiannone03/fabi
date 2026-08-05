import type { WorkerConnectionProfile } from "./types"

export interface ConnectionProfileEnvironment {
  [name: string]: string | undefined
  FABI_WORKER_RELAY_URL?: string | undefined
  FABI_WORKER_ENROLLMENT_URL?: string | undefined
  FABI_WORKER_CATALOG_DHT_BOOTSTRAPS?: string | undefined
  FABI_WORKER_MODEL_REGISTRY_ROOT_URL?: string | undefined
  FABI_WORKER_MODEL_REGISTRY_ROOT_SHA256?: string | undefined
  FABI_WORKER_MODEL_REGISTRY_METADATA_URL?: string | undefined
  FABI_WORKER_MODEL_REGISTRY_TARGETS_URL?: string | undefined
}

/** Build the public, secret-free worker bootstrap contract advertised by V3. */
export function connectionProfileFromEnvironment(
  env: ConnectionProfileEnvironment,
): WorkerConnectionProfile {
  const relayUrl = httpsUrl(env.FABI_WORKER_RELAY_URL, "FABI_WORKER_RELAY_URL")
  const enrollmentUrl = httpsUrl(
    env.FABI_WORKER_ENROLLMENT_URL,
    "FABI_WORKER_ENROLLMENT_URL",
  )
  const rootUrl = httpsUrl(
    env.FABI_WORKER_MODEL_REGISTRY_ROOT_URL,
    "FABI_WORKER_MODEL_REGISTRY_ROOT_URL",
  )
  const metadataUrl = httpsUrl(
    env.FABI_WORKER_MODEL_REGISTRY_METADATA_URL,
    "FABI_WORKER_MODEL_REGISTRY_METADATA_URL",
  )
  const targetsUrl = httpsUrl(
    env.FABI_WORKER_MODEL_REGISTRY_TARGETS_URL,
    "FABI_WORKER_MODEL_REGISTRY_TARGETS_URL",
  )
  const rootSha256 = env.FABI_WORKER_MODEL_REGISTRY_ROOT_SHA256?.trim().toLowerCase() ?? ""
  if (!/^[0-9a-f]{64}$/.test(rootSha256)) {
    throw new Error("FABI_WORKER_MODEL_REGISTRY_ROOT_SHA256 must be a SHA-256 hex digest")
  }
  let decoded: unknown
  try {
    decoded = JSON.parse(env.FABI_WORKER_CATALOG_DHT_BOOTSTRAPS ?? "")
  } catch (error) {
    throw new Error("FABI_WORKER_CATALOG_DHT_BOOTSTRAPS must be a JSON array", { cause: error })
  }
  if (
    !Array.isArray(decoded)
    || decoded.length === 0
    || decoded.some(address => typeof address !== "string"
      || !address.startsWith("/")
      || !address.includes("/p2p/"))
  ) {
    throw new Error(
      "FABI_WORKER_CATALOG_DHT_BOOTSTRAPS must contain at least one libp2p /p2p/ multiaddress",
    )
  }
  return {
    protocolVersion: 3,
    // Schema 2 introduced max_context_tokens on leases. Schema 3 requires the
    // TUF-signed model context ceiling and service classes. Keep this epoch
    // independent from the product's V3 protocol name so an older desktop
    // fails before starting a worker against an incompatible signed bundle.
    catalogSchemaVersion: 3,
    transport: "iroh",
    relayUrl,
    enrollmentUrl,
    catalogDhtBootstraps: decoded,
    modelRegistry: { rootUrl, rootSha256, metadataUrl, targetsUrl },
  }
}

function httpsUrl(value: string | undefined, name: string): string {
  const normalized = value?.trim() ?? ""
  let parsed: URL
  try {
    parsed = new URL(normalized)
  } catch (error) {
    throw new Error(`${name} must be an absolute HTTPS URL`, { cause: error })
  }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.hash) {
    throw new Error(`${name} must be an absolute HTTPS URL without credentials or fragment`)
  }
  return normalized
}
