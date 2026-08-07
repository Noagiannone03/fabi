#!/usr/bin/env bash
#
# Refuse une release dont les sources clonées et le fallback compilé dans le
# CLI ne décrivent pas le même runtime. Sans cette vérification, le tarball
# peut embarquer un moteur récent tout en réinstallant silencieusement un
# ancien commit lors d'une réparation déclenchée par le CLI.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
# shellcheck source=../runtime-lock.env
source "$ROOT/runtime-lock.env"
set +a

OPENCODE_DIR="$ROOT/packages/fabi-cli"
PARALLAX_DIR="$ROOT/packages/swarm-engine"
RUNTIME_SOURCE="$OPENCODE_DIR/packages/opencode/src/swarm/runtime-source.ts"
SKIPPY_LOCK="$ROOT/scripts/skippy-native-runtime-lock.json"
SKIPPY_BRIDGE_CARGO="$PARALLAX_DIR/native/fabi-skippy-runtime/Cargo.toml"
SKIPPY_BRIDGE_SOURCE="$PARALLAX_DIR/native/fabi-skippy-runtime/src/lib.rs"

for required in \
  "$OPENCODE_DIR/.git" \
  "$PARALLAX_DIR/.git" \
  "$RUNTIME_SOURCE" \
  "$SKIPPY_LOCK" \
  "$SKIPPY_BRIDGE_CARGO" \
  "$SKIPPY_BRIDGE_SOURCE"; do
  if [ ! -e "$required" ]; then
    printf 'runtime lock preflight: missing %s\n' "$required" >&2
    exit 1
  fi
done

ACTUAL_OPENCODE_REF="$(git -C "$OPENCODE_DIR" rev-parse HEAD)"
ACTUAL_PARALLAX_REF="$(git -C "$PARALLAX_DIR" rev-parse HEAD)"
CLI_PARALLAX_REF="$(
  sed -nE \
    's/^export const QUALIFIED_PARALLAX_COMMIT = "([0-9a-fA-F]{40})"$/\1/p' \
    "$RUNTIME_SOURCE"
)"
LOCKED_MESH_REF="$(node -p 'require(process.argv[1]).mesh_revision' "$SKIPPY_LOCK")"
LOCKED_MESH_VERSION="$(node -p 'require(process.argv[1]).mesh_release' "$SKIPPY_LOCK")"
LOCKED_SKIPPY_ABI="$(node -p 'require(process.argv[1]).skippy_abi' "$SKIPPY_LOCK")"
BRIDGE_MESH_REF="$(sed -nE 's/.*rev = "([0-9a-fA-F]{40})".*/\1/p' "$SKIPPY_BRIDGE_CARGO" | sort -u)"
BRIDGE_MESH_VERSION="$(sed -nE 's/^pub const SKIPPY_MESH_RELEASE: &str = "([^"]+)";.*/\1/p' "$SKIPPY_BRIDGE_SOURCE")"
BRIDGE_SKIPPY_ABI="$(sed -nE 's/^pub const SKIPPY_RUNTIME_ABI: &str = "([^"]+)";.*/\1/p' "$SKIPPY_BRIDGE_SOURCE")"

if [ "$ACTUAL_OPENCODE_REF" != "$OPENCODE_REF" ]; then
  printf 'runtime lock preflight: fabi-cli HEAD=%s, lock=%s\n' \
    "$ACTUAL_OPENCODE_REF" "$OPENCODE_REF" >&2
  exit 1
fi
if [ "$ACTUAL_PARALLAX_REF" != "$PARALLAX_REF" ]; then
  printf 'runtime lock preflight: swarm-engine HEAD=%s, lock=%s\n' \
    "$ACTUAL_PARALLAX_REF" "$PARALLAX_REF" >&2
  exit 1
fi
if [ "$CLI_PARALLAX_REF" != "$PARALLAX_REF" ]; then
  printf 'runtime lock preflight: CLI fallback=%s, lock=%s\n' \
    "${CLI_PARALLAX_REF:-<absent>}" "$PARALLAX_REF" >&2
  exit 1
fi
if [ "$LOCKED_MESH_REF" != "$MESH_LLM_REF" ] || [ "$BRIDGE_MESH_REF" != "$MESH_LLM_REF" ]; then
  printf 'runtime lock preflight: Mesh revision mismatch env=%s package=%s bridge=%s\n' \
    "$MESH_LLM_REF" "$LOCKED_MESH_REF" "$BRIDGE_MESH_REF" >&2
  exit 1
fi
if [ "$LOCKED_MESH_VERSION" != "$MESH_LLM_VERSION" ] || [ "$BRIDGE_MESH_VERSION" != "$MESH_LLM_VERSION" ]; then
  printf 'runtime lock preflight: Mesh version mismatch env=%s package=%s bridge=%s\n' \
    "$MESH_LLM_VERSION" "$LOCKED_MESH_VERSION" "$BRIDGE_MESH_VERSION" >&2
  exit 1
fi
if [ "$LOCKED_SKIPPY_ABI" != "$SKIPPY_RUNTIME_ABI" ] || [ "$BRIDGE_SKIPPY_ABI" != "$SKIPPY_RUNTIME_ABI" ]; then
  printf 'runtime lock preflight: Skippy ABI mismatch env=%s package=%s bridge=%s\n' \
    "$SKIPPY_RUNTIME_ABI" "$LOCKED_SKIPPY_ABI" "$BRIDGE_SKIPPY_ABI" >&2
  exit 1
fi

printf 'runtime lock preflight: coherent opencode=%s parallax=%s mesh=%s skippy_abi=%s\n' \
  "$OPENCODE_REF" "$PARALLAX_REF" "$MESH_LLM_REF" "$SKIPPY_RUNTIME_ABI"
