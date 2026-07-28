import { Database, SQLiteError } from "bun:sqlite"
import {
  createHash,
  createPublicKey,
  timingSafeEqual,
  verify as verifySignature,
} from "node:crypto"

const ACCOUNT_CREDENTIAL_RE = /^[0-9a-fA-F]{64}$/
const ENDPOINT_ID_RE = /^[0-9a-f]{64}$/
const NONCE_RE = /^[0-9a-f]{64}$/
const SIGNATURE_RE = /^[0-9a-f]{128}$/
const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex")
const ENROLLMENT_DOMAIN = Buffer.from("fabi/network/relay-enrollment/v1\0", "utf8")

export const DEFAULT_LEASE_TTL_MS = 24 * 60 * 60 * 1_000
export const DEFAULT_REFRESH_AFTER_MS = 6 * 60 * 60 * 1_000
export const DEFAULT_MAX_CLOCK_SKEW_MS = 2 * 60 * 1_000
export const DEFAULT_NONCE_RETENTION_MS = 10 * 60 * 1_000
export const DEFAULT_MAX_ENDPOINTS_PER_ACCOUNT = 16

export interface RelayEnrollmentRequest {
  endpoint_id: string
  issued_at_ms: number
  nonce: string
  signature: string
}

export interface RelayEnrollmentLease {
  endpoint_id: string
  enrolled_at_ms: number
  expires_at_ms: number
  refresh_at_ms: number
}

export interface RelayAccessOptions {
  databasePath: string
  relayBearerToken: string
  leaseTtlMs?: number
  refreshAfterMs?: number
  maxClockSkewMs?: number
  nonceRetentionMs?: number
  maxEndpointsPerAccount?: number
  now?: () => number
  /** Stable scheduler/router identities managed by the infrastructure operator. */
  infrastructureEndpointIds?: string[]
}

export class RelayAccessError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = "RelayAccessError"
  }
}

/**
 * Persistent control-plane authority for Iroh relay access.
 *
 * A Fabi account credential authorizes enrollment, while an Ed25519 proof made
 * with the stable Iroh identity proves that the caller owns the EndpointId it
 * wants to enroll. Only account hashes, public endpoint IDs and bounded replay
 * nonces are persisted. Relay bearer secrets and account credentials never are.
 */
export class RelayAccessService {
  private readonly db: Database
  private readonly relayBearerToken: Buffer
  private readonly leaseTtlMs: number
  private readonly refreshAfterMs: number
  private readonly maxClockSkewMs: number
  private readonly nonceRetentionMs: number
  private readonly maxEndpointsPerAccount: number
  private readonly now: () => number
  private readonly infrastructureEndpointIds: ReadonlySet<string>

  constructor(options: RelayAccessOptions) {
    if (!options.relayBearerToken) {
      throw new Error("relay HTTP bearer token must not be empty")
    }
    this.relayBearerToken = Buffer.from(options.relayBearerToken, "utf8")
    this.leaseTtlMs = positiveInteger(options.leaseTtlMs ?? DEFAULT_LEASE_TTL_MS, "leaseTtlMs")
    this.refreshAfterMs = positiveInteger(
      options.refreshAfterMs ?? DEFAULT_REFRESH_AFTER_MS,
      "refreshAfterMs",
    )
    if (this.refreshAfterMs >= this.leaseTtlMs) {
      throw new Error("refreshAfterMs must be lower than leaseTtlMs")
    }
    this.maxClockSkewMs = positiveInteger(
      options.maxClockSkewMs ?? DEFAULT_MAX_CLOCK_SKEW_MS,
      "maxClockSkewMs",
    )
    this.nonceRetentionMs = positiveInteger(
      options.nonceRetentionMs ?? DEFAULT_NONCE_RETENTION_MS,
      "nonceRetentionMs",
    )
    this.maxEndpointsPerAccount = positiveInteger(
      options.maxEndpointsPerAccount ?? DEFAULT_MAX_ENDPOINTS_PER_ACCOUNT,
      "maxEndpointsPerAccount",
    )
    this.now = options.now ?? Date.now
    const infrastructureEndpointIds = options.infrastructureEndpointIds ?? []
    if (infrastructureEndpointIds.some(endpointId => !ENDPOINT_ID_RE.test(endpointId))) {
      throw new Error("infrastructure endpoint IDs must be lowercase 32-byte hexadecimal values")
    }
    this.infrastructureEndpointIds = new Set(infrastructureEndpointIds)
    this.db = new Database(options.databasePath, { create: true, strict: true })
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000; PRAGMA foreign_keys = ON;")
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS relay_endpoints (
        endpoint_id TEXT PRIMARY KEY NOT NULL,
        account_id TEXT NOT NULL,
        enrolled_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS relay_endpoints_account
        ON relay_endpoints(account_id, expires_at_ms);
      CREATE TABLE IF NOT EXISTS relay_enrollment_nonces (
        nonce TEXT PRIMARY KEY NOT NULL,
        account_id TEXT NOT NULL,
        expires_at_ms INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS relay_nonces_expiry
        ON relay_enrollment_nonces(expires_at_ms);
    `)
  }

  enroll(accountCredential: string | null, request: unknown): RelayEnrollmentLease {
    const accountId = hashAccountCredential(accountCredential)
    if (!accountId) {
      throw new RelayAccessError(401, "invalid_account_credential", "account credential is invalid")
    }
    const proof = parseEnrollmentRequest(request)
    const now = Math.trunc(this.now())
    if (Math.abs(now - proof.issued_at_ms) > this.maxClockSkewMs) {
      throw new RelayAccessError(400, "stale_enrollment_proof", "enrollment proof is outside the clock window")
    }
    if (!verifyEnrollmentProof(accountId, proof)) {
      throw new RelayAccessError(403, "invalid_enrollment_proof", "endpoint ownership proof is invalid")
    }

    const expiresAt = now + this.leaseTtlMs
    const nonceExpiresAt = now + this.nonceRetentionMs
    const transaction = this.db.transaction(() => {
      this.db.query("DELETE FROM relay_enrollment_nonces WHERE expires_at_ms <= ?").run(now)
      this.db.query("DELETE FROM relay_endpoints WHERE expires_at_ms <= ?").run(now)

      try {
        this.db.query(
          "INSERT INTO relay_enrollment_nonces(nonce, account_id, expires_at_ms) VALUES (?, ?, ?)",
        ).run(proof.nonce, accountId, nonceExpiresAt)
      } catch (error) {
        if (error instanceof SQLiteError && error.code === "SQLITE_CONSTRAINT_PRIMARYKEY") {
          throw new RelayAccessError(409, "replayed_enrollment_proof", "enrollment nonce was already used")
        }
        throw error
      }

      const existing = this.db.query(
        "SELECT account_id FROM relay_endpoints WHERE endpoint_id = ?",
      ).get(proof.endpoint_id) as { account_id: string } | null
      if (!existing || existing.account_id !== accountId) {
        const row = this.db.query(
          "SELECT COUNT(*) AS count FROM relay_endpoints WHERE account_id = ? AND expires_at_ms > ?",
        ).get(accountId, now) as { count: number }
        if (row.count >= this.maxEndpointsPerAccount) {
          throw new RelayAccessError(409, "endpoint_limit_reached", "account endpoint limit reached")
        }
      }

      this.db.query(`
        INSERT INTO relay_endpoints(endpoint_id, account_id, enrolled_at_ms, expires_at_ms)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(endpoint_id) DO UPDATE SET
          account_id = excluded.account_id,
          enrolled_at_ms = excluded.enrolled_at_ms,
          expires_at_ms = excluded.expires_at_ms
      `).run(proof.endpoint_id, accountId, now, expiresAt)
    })

    transaction.immediate()
    return {
      endpoint_id: proof.endpoint_id,
      enrolled_at_ms: now,
      expires_at_ms: expiresAt,
      refresh_at_ms: now + this.refreshAfterMs,
    }
  }

  isRelayAuthorized(endpointId: string | null): boolean {
    if (!endpointId || !ENDPOINT_ID_RE.test(endpointId)) return false
    if (this.infrastructureEndpointIds.has(endpointId)) return true
    const row = this.db.query(
      "SELECT 1 AS allowed FROM relay_endpoints WHERE endpoint_id = ? AND expires_at_ms > ?",
    ).get(endpointId, Math.trunc(this.now())) as { allowed: number } | null
    return row?.allowed === 1
  }

  authenticateRelay(bearerToken: string | null): boolean {
    if (bearerToken === null) return false
    const candidate = Buffer.from(bearerToken, "utf8")
    return candidate.length === this.relayBearerToken.length
      && timingSafeEqual(candidate, this.relayBearerToken)
  }

  revokeEndpoint(endpointId: string): boolean {
    if (!ENDPOINT_ID_RE.test(endpointId)) return false
    return this.db.query("DELETE FROM relay_endpoints WHERE endpoint_id = ?").run(endpointId).changes > 0
  }

  close(): void {
    this.db.close()
  }
}

export function parseInfrastructureEndpointIds(raw: string | undefined): string[] {
  let decoded: unknown
  try {
    decoded = JSON.parse(raw ?? "")
  } catch (error) {
    throw new Error("FABI_RELAY_INFRA_ENDPOINTS must be a JSON array", { cause: error })
  }
  if (!Array.isArray(decoded) || decoded.length === 0
    || decoded.some(value => typeof value !== "string" || !ENDPOINT_ID_RE.test(value))) {
    throw new Error(
      "FABI_RELAY_INFRA_ENDPOINTS must contain lowercase 32-byte hexadecimal EndpointIds",
    )
  }
  return [...new Set(decoded)]
}

export function hashAccountCredential(credential: string | null): string | null {
  if (!credential || !ACCOUNT_CREDENTIAL_RE.test(credential.trim())) return null
  return createHash("sha256").update(credential.trim().toLowerCase(), "ascii").digest("hex")
}

export function enrollmentSigningPreimage(
  endpointId: string,
  accountId: string,
  issuedAtMs: number,
  nonce: string,
): Buffer {
  if (!ENDPOINT_ID_RE.test(endpointId)) throw new Error("invalid endpoint ID")
  if (!ENDPOINT_ID_RE.test(accountId)) throw new Error("invalid account ID")
  if (!Number.isSafeInteger(issuedAtMs) || issuedAtMs < 0) throw new Error("invalid issued_at_ms")
  if (!NONCE_RE.test(nonce)) throw new Error("invalid nonce")
  const timestamp = Buffer.alloc(8)
  timestamp.writeBigUInt64BE(BigInt(issuedAtMs))
  return Buffer.concat([
    ENROLLMENT_DOMAIN,
    Buffer.from(endpointId, "hex"),
    Buffer.from(accountId, "hex"),
    timestamp,
    Buffer.from(nonce, "hex"),
  ])
}

function verifyEnrollmentProof(accountId: string, request: RelayEnrollmentRequest): boolean {
  try {
    const publicKey = createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(request.endpoint_id, "hex")]),
      format: "der",
      type: "spki",
    })
    return verifySignature(
      null,
      enrollmentSigningPreimage(
        request.endpoint_id,
        accountId,
        request.issued_at_ms,
        request.nonce,
      ),
      publicKey,
      Buffer.from(request.signature, "hex"),
    )
  } catch {
    return false
  }
}

function parseEnrollmentRequest(value: unknown): RelayEnrollmentRequest {
  const object = value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
  if (
    !object
    || typeof object.endpoint_id !== "string"
    || !ENDPOINT_ID_RE.test(object.endpoint_id)
    || typeof object.issued_at_ms !== "number"
    || !Number.isSafeInteger(object.issued_at_ms)
    || object.issued_at_ms < 0
    || typeof object.nonce !== "string"
    || !NONCE_RE.test(object.nonce)
    || typeof object.signature !== "string"
    || !SIGNATURE_RE.test(object.signature)
  ) {
    throw new RelayAccessError(400, "invalid_enrollment_request", "enrollment request is malformed")
  }
  return {
    endpoint_id: object.endpoint_id,
    issued_at_ms: object.issued_at_ms,
    nonce: object.nonce,
    signature: object.signature,
  }
}

function positiveInteger(value: number, name: string): number {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error(`${name} must be a positive integer`)
  return value
}
