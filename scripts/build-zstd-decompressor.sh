#!/usr/bin/env bash
# Build the tiny, standalone decompressor used by the fresh-install path.
#
# Fabi release archives use zstd because the CUDA runtime is several GiB.
# zstd is not part of a stock macOS install and is not guaranteed on Linux or
# Windows, so requiring a package manager would make the release non-autonomous.
#
# POSIX binaries are built from Meta's pinned upstream source and only include
# the official `zstd-decompress` target. Linux uses musl for a static binary.
# Windows uses the official upstream win64 release binary.

set -euo pipefail

PLATFORM_TAG="${1:-}"
if [ -z "$PLATFORM_TAG" ]; then
  echo "Usage: $0 <platform-tag>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
ZSTD_VERSION="1.5.7"
ZSTD_SOURCE_SHA256="eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3"
ZSTD_WINDOWS_ZIP_SHA256="acb4e8111511749dc7a3ebedca9b04190e37a17afeb73f55d4425dbf0b90fad9"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_sha256() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(sha256_file "$path")"
  if [ "$actual" != "$expected" ]; then
    echo "SHA256 mismatch for $path: expected $expected, got $actual" >&2
    exit 1
  fi
}

mkdir -p "$DIST"

case "$PLATFORM_TAG" in
  windows-x64-*)
    archive="$TMP_DIR/zstd-win64.zip"
    output="$DIST/fabi-unzstd-${PLATFORM_TAG}.exe"
    curl -fsSL \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-v${ZSTD_VERSION}-win64.zip" \
      -o "$archive"
    verify_sha256 "$archive" "$ZSTD_WINDOWS_ZIP_SHA256"
    tar -xf "$archive" -C "$TMP_DIR"
    cp "$TMP_DIR/zstd-v${ZSTD_VERSION}-win64/zstd.exe" "$output"
    ;;
  linux-*|darwin-*)
    archive="$TMP_DIR/zstd.tar.gz"
    source_root="$TMP_DIR/zstd-${ZSTD_VERSION}"
    output="$DIST/fabi-unzstd-${PLATFORM_TAG}"
    curl -fsSL \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" \
      -o "$archive"
    verify_sha256 "$archive" "$ZSTD_SOURCE_SHA256"
    tar -xzf "$archive" -C "$TMP_DIR"

    make_args=(
      -C "$source_root/programs"
      zstd-decompress
      HAVE_ZLIB=0
      HAVE_LZMA=0
      HAVE_LZ4=0
      HAVE_THREAD=0
      ZSTD_LEGACY_SUPPORT=0
    )
    if [[ "$PLATFORM_TAG" == linux-* ]]; then
      command -v musl-gcc >/dev/null 2>&1 || {
        echo "musl-gcc is required to build the portable Linux decompressor" >&2
        exit 1
      }
      make "${make_args[@]}" CC=musl-gcc LDFLAGS=-static -j2
    else
      make "${make_args[@]}" -j2
    fi
    cp "$source_root/programs/zstd-decompress" "$output"
    chmod +x "$output"
    ;;
  *)
    echo "Unsupported decompressor platform: $PLATFORM_TAG" >&2
    exit 1
    ;;
esac

"$output" --version
output_sha256="$(sha256_file "$output")"
printf '%s  %s\n' "$output_sha256" "$(basename "$output")" > "${output}.sha256"
echo "Standalone zstd decompressor: $output"
echo "SHA256: ${output}.sha256"
