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

for required in "$OPENCODE_DIR/.git" "$PARALLAX_DIR/.git" "$RUNTIME_SOURCE"; do
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

printf 'runtime lock preflight: coherent opencode=%s parallax=%s\n' \
  "$OPENCODE_REF" "$PARALLAX_REF"
