#!/usr/bin/env bash
# Regression test for the POSIX installer managed-path transaction.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

install_root="$test_root/install"
bin_root="$test_root/bin"

build_fixture() {
  local version="$1"
  local package_root="$test_root/package-$version"
  local archive="$test_root/fabi-$version.tar.zst"

  mkdir -p \
    "$package_root/bin" \
    "$package_root/runtime/parallax-venv/bin"
  printf '#!/usr/bin/env sh\nprintf "fabi %s\\n"\n' "$version" > "$package_root/bin/fabi"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$package_root/runtime/parallax-venv/bin/python"
  chmod +x "$package_root/bin/fabi" "$package_root/runtime/parallax-venv/bin/python"
  printf '__FABI_INSTALL_ROOT__/runtime\n' > "$package_root/runtime/runtime-path.txt"
  printf 'runtime/runtime-path.txt\n' > "$package_root/runtime/relocation-manifest.txt"
  printf 'fabi %s\n' "$version" > "$package_root/MANIFEST"
  printf 'bin\nruntime\nMANIFEST\n.fabi-managed-paths\n' > "$package_root/.fabi-managed-paths"

  tar --use-compress-program='zstd -q -1' -cf "$archive" -C "$test_root" "package-$version"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive" > "$archive.sha256"
  else
    shasum -a 256 "$archive" > "$archive.sha256"
  fi
  printf '%s\n' "$archive"
}

run_installer() {
  FABI_VERSION=test \
  FABI_TARBALL_PATH="$1" \
  FABI_INSTALL="$install_root" \
  FABI_BIN_DIR="$bin_root" \
  FABI_NO_PATH=1 \
    "$repo_root/install.sh" >/dev/null
}

first_archive="$(build_fixture first)"
run_installer "$first_archive"
mkdir -p "$install_root/network" "$install_root/swarm-v3" "$install_root/trust"
printf 'stable-identity\n' > "$install_root/network/worker.key"
printf 'fencing-state\n' > "$install_root/swarm-v3/fencing.sqlite3"
printf 'pinned-root\n' > "$install_root/trust/root.json"

second_archive="$(build_fixture second)"
run_installer "$second_archive"

test "$("$install_root/bin/fabi")" = "fabi second"
test "$(cat "$install_root/network/worker.key")" = "stable-identity"
test "$(cat "$install_root/swarm-v3/fencing.sqlite3")" = "fencing-state"
test "$(cat "$install_root/trust/root.json")" = "pinned-root"
test "$(cat "$install_root/runtime/runtime-path.txt")" = "$install_root/runtime"
test "$(readlink "$bin_root/fabi")" = "$install_root/bin/fabi"
find "$test_root" -maxdepth 1 -type d -name 'install.backup-*' | grep -q .

# A malformed package must fail before touching either managed or persistent
# state from the working installation.
bad_root="$test_root/package-bad"
mkdir -p "$bad_root/bin" "$bad_root/runtime/parallax-venv/bin"
cp "$install_root/bin/fabi" "$bad_root/bin/fabi"
cp "$install_root/runtime/parallax-venv/bin/python" "$bad_root/runtime/parallax-venv/bin/python"
printf '__FABI_INSTALL_ROOT__/runtime\n' > "$bad_root/runtime/runtime-path.txt"
printf 'runtime/runtime-path.txt\n' > "$bad_root/runtime/relocation-manifest.txt"
printf 'fabi bad\n' > "$bad_root/MANIFEST"
bad_archive="$test_root/fabi-bad.tar.zst"
tar --use-compress-program='zstd -q -1' -cf "$bad_archive" -C "$test_root" package-bad
if run_installer "$bad_archive" 2>/dev/null; then
  printf 'malformed package unexpectedly installed\n' >&2
  exit 1
fi
test "$("$install_root/bin/fabi")" = "fabi second"
test "$(cat "$install_root/network/worker.key")" = "stable-identity"

printf 'installer upgrade transaction: ok\n'
