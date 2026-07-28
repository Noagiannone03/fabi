import { afterEach, describe, expect, test } from "bun:test"
import { generateKeyPairSync, randomBytes, sign } from "node:crypto"
import { rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  RelayAccessService,
  enrollmentSigningPreimage,
  hashAccountCredential,
} from "./relay-access"
import type { SwarmScanner } from "./scanner"
import { startHttpServer } from "./server"

const ACCOUNT = "cd".repeat(32)
const RELAY_BEARER = "private-relay-callout-token"
const files: string[] = []

afterEach(() => {
  for (const path of files.splice(0)) {
    for (const suffix of ["", "-wal", "-shm"]) rmSync(path + suffix, { force: true })
  }
})

describe("relay HTTP contract", () => {
  test("enrolls through HTTPS-facing API then returns exact Iroh allow body", async () => {
    const path = join(tmpdir(), `fabi-registry-http-${randomBytes(8).toString("hex")}.sqlite3`)
    files.push(path)
    const access = new RelayAccessService({
      databasePath: path,
      relayBearerToken: RELAY_BEARER,
    })
    const scanner = {
      snapshot: () => [],
      subscribe: () => () => {},
    } as unknown as SwarmScanner
    const server = startHttpServer({ port: 0, host: "127.0.0.1", scanner, relayAccess: access })
    try {
      const keys = generateKeyPairSync("ed25519")
      const endpointId = Buffer.from(
        keys.publicKey.export({ format: "der", type: "spki" }),
      ).subarray(-32).toString("hex")
      const issuedAt = Date.now()
      const nonce = randomBytes(32).toString("hex")
      const accountId = hashAccountCredential(ACCOUNT)!
      const signature = sign(
        null,
        enrollmentSigningPreimage(endpointId, accountId, issuedAt, nonce),
        keys.privateKey,
      ).toString("hex")
      const base = `http://127.0.0.1:${server.port}`

      const enrollment = await fetch(`${base}/v1/network/enroll`, {
        method: "POST",
        headers: { Authorization: `Bearer ${ACCOUNT}`, "Content-Type": "application/json" },
        body: JSON.stringify({ endpoint_id: endpointId, issued_at_ms: issuedAt, nonce, signature }),
      })
      expect(enrollment.status).toBe(200)
      expect((await enrollment.json() as { lease: { endpoint_id: string } }).lease.endpoint_id)
        .toBe(endpointId)

      const denied = await fetch(`${base}/v1/network/relay-access`, {
        method: "POST",
        headers: { "X-Iroh-Endpoint-Id": endpointId },
      })
      expect(denied.status).toBe(401)
      expect(await denied.text()).toBe("false")

      const allowed = await fetch(`${base}/v1/network/relay-access`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RELAY_BEARER}`,
          "X-Iroh-Endpoint-Id": endpointId,
        },
      })
      expect(allowed.status).toBe(200)
      expect(await allowed.text()).toBe("true")
    } finally {
      server.stop(true)
      access.close()
    }
  })
})
