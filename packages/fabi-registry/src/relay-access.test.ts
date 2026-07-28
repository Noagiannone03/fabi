import { afterEach, describe, expect, test } from "bun:test"
import { generateKeyPairSync, randomBytes, sign } from "node:crypto"
import { rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  RelayAccessError,
  RelayAccessService,
  enrollmentSigningPreimage,
  hashAccountCredential,
} from "./relay-access"

const ACCOUNT_CREDENTIAL = "ab".repeat(32)
const RELAY_BEARER = "relay-to-registry-secret"
const NOW = 1_800_000_000_000
const paths: string[] = []

afterEach(() => {
  for (const path of paths.splice(0)) {
    for (const suffix of ["", "-wal", "-shm"]) rmSync(path + suffix, { force: true })
  }
})

function databasePath(): string {
  const path = join(tmpdir(), `fabi-relay-access-${randomBytes(8).toString("hex")}.sqlite3`)
  paths.push(path)
  return path
}

function signer() {
  const pair = generateKeyPairSync("ed25519")
  const der = pair.publicKey.export({ format: "der", type: "spki" })
  const endpointId = Buffer.from(der).subarray(-32).toString("hex")
  return {
    endpointId,
    proof(accountCredential = ACCOUNT_CREDENTIAL, issuedAtMs = NOW, nonce = randomBytes(32).toString("hex")) {
      const accountId = hashAccountCredential(accountCredential)
      if (!accountId) throw new Error("test account credential is invalid")
      const signature = sign(
        null,
        enrollmentSigningPreimage(endpointId, accountId, issuedAtMs, nonce),
        pair.privateKey,
      ).toString("hex")
      return { endpoint_id: endpointId, issued_at_ms: issuedAtMs, nonce, signature }
    },
  }
}

function service(options: { maxEndpointsPerAccount?: number } = {}) {
  return new RelayAccessService({
    databasePath: databasePath(),
    relayBearerToken: RELAY_BEARER,
    leaseTtlMs: 60_000,
    refreshAfterMs: 20_000,
    maxClockSkewMs: 1_000,
    nonceRetentionMs: 10_000,
    ...(options.maxEndpointsPerAccount === undefined
      ? {}
      : { maxEndpointsPerAccount: options.maxEndpointsPerAccount }),
    now: () => NOW,
  })
}

describe("RelayAccessService", () => {
  test("enrolls an owned EndpointId and authorizes only the relay callout", () => {
    const access = service()
    const identity = signer()
    const lease = access.enroll(ACCOUNT_CREDENTIAL, identity.proof())

    expect(lease).toEqual({
      endpoint_id: identity.endpointId,
      enrolled_at_ms: NOW,
      expires_at_ms: NOW + 60_000,
      refresh_at_ms: NOW + 20_000,
    })
    expect(access.isRelayAuthorized(identity.endpointId)).toBe(true)
    expect(access.authenticateRelay(RELAY_BEARER)).toBe(true)
    expect(access.authenticateRelay("wrong")).toBe(false)
    access.close()
  })

  test("rejects a proof signed by a different endpoint", () => {
    const access = service()
    const claimed = signer()
    const attacker = signer()
    const proof = attacker.proof()
    proof.endpoint_id = claimed.endpointId

    expect(() => access.enroll(ACCOUNT_CREDENTIAL, proof)).toThrow(RelayAccessError)
    expect(access.isRelayAuthorized(claimed.endpointId)).toBe(false)
    access.close()
  })

  test("rejects replayed nonces atomically", () => {
    const access = service()
    const identity = signer()
    const proof = identity.proof()
    access.enroll(ACCOUNT_CREDENTIAL, proof)

    try {
      access.enroll(ACCOUNT_CREDENTIAL, proof)
      throw new Error("expected replay rejection")
    } catch (error) {
      expect(error).toBeInstanceOf(RelayAccessError)
      expect((error as RelayAccessError).code).toBe("replayed_enrollment_proof")
    }
    access.close()
  })

  test("rejects stale proofs and malformed credentials", () => {
    const access = service()
    const identity = signer()
    expect(() => access.enroll(ACCOUNT_CREDENTIAL, identity.proof(ACCOUNT_CREDENTIAL, NOW - 1_001)))
      .toThrow(RelayAccessError)
    expect(() => access.enroll("not-a-credential", identity.proof())).toThrow(RelayAccessError)
    access.close()
  })

  test("enforces the active endpoint bound and supports revocation", () => {
    const access = service({ maxEndpointsPerAccount: 1 })
    const first = signer()
    const second = signer()
    access.enroll(ACCOUNT_CREDENTIAL, first.proof())
    expect(() => access.enroll(ACCOUNT_CREDENTIAL, second.proof())).toThrow(RelayAccessError)

    expect(access.revokeEndpoint(first.endpointId)).toBe(true)
    expect(access.isRelayAuthorized(first.endpointId)).toBe(false)
    expect(access.enroll(ACCOUNT_CREDENTIAL, second.proof()).endpoint_id).toBe(second.endpointId)
    access.close()
  })
})
