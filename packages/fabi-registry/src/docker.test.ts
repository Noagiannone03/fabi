// Tests unitaires sur les parties pures du module Docker.

import { describe, expect, test } from "bun:test"
import { extractPeerIdFromLogs, _internals } from "./docker"

describe("extractPeerIdFromLogs", () => {
  test("retourne null sur des logs sans peer ID", () => {
    expect(extractPeerIdFromLogs("juste un log random\nrien d'utile")).toBeNull()
  })

  test("extrait le peer ID quand présent une fois", () => {
    const logs = `
May 04 14:26:01.395 [backend] INFO scheduler_manage.py:240 Using initial peers: [...]
May 04 14:26:02.556 [backend] INFO scheduler_manage.py:267 Stored scheduler peer id: 12D3KooWKLCTHRAhMEafQfaGZTAEx8kJjeMqpXDDeyhBGVotuSfR
May 04 14:30:00.000 [scheduler] INFO whatever
    `
    expect(extractPeerIdFromLogs(logs)).toBe(
      "12D3KooWKLCTHRAhMEafQfaGZTAEx8kJjeMqpXDDeyhBGVotuSfR",
    )
  })

  test("retourne le dernier peer ID si plusieurs (= scheduler restart)", () => {
    const logs = `
Stored scheduler peer id: 12D3KooWAAA111111111111111111111111111111111111111111
... beaucoup de logs ...
Stored scheduler peer id: 12D3KooWBBB222222222222222222222222222222222222222222
    `
    expect(extractPeerIdFromLogs(logs)).toBe(
      "12D3KooWBBB222222222222222222222222222222222222222222",
    )
  })

  test("regex stable même avec espaces variés", () => {
    expect(_internals.PEER_ID_LOG_RE.test("Stored scheduler peer id:  12D3KooWXXX")).toBe(true)
    expect(_internals.PEER_ID_LOG_RE.test("Stored scheduler peer id:12D3KooWXXX")).toBe(true)
  })
})

describe("demuxDockerLogs", () => {
  test("retourne tel quel si pas de header binaire (TTY mode)", () => {
    const plain = "ligne 1\nligne 2\n"
    expect(_internals.demuxDockerLogs(plain)).toBe(plain)
  })

  test("dé-mux une frame stdout simple", () => {
    // Header: stream=1 (stdout), padding 0,0,0, len=5 (big endian)
    const header = String.fromCharCode(1, 0, 0, 0, 0, 0, 0, 5)
    const payload = "hello"
    expect(_internals.demuxDockerLogs(header + payload)).toBe("hello")
  })

  test("dé-mux deux frames consécutives", () => {
    const f1 = String.fromCharCode(1, 0, 0, 0, 0, 0, 0, 3) + "abc"
    const f2 = String.fromCharCode(2, 0, 0, 0, 0, 0, 0, 4) + "def!"
    expect(_internals.demuxDockerLogs(f1 + f2)).toBe("abcdef!")
  })
})
