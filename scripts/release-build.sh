#!/usr/bin/env bash
# release-build.sh — produit UN tarball Fabi prêt à publier pour UNE plateforme.
#
# Pipeline :
#   1. Compile le binaire `fabi` via `bun build --compile` (= TS + deps + Bun runtime)
#   2. Télécharge un Python embarquable (python-build-standalone)
#   3. Crée un venv Python qui a Parallax installé
#   4. Pack le tout dans un tarball compressé zstd
#
# Le tarball final ressemble à :
#   fabi/
#   ├── bin/fabi                     ← binaire natif (50 MB)
#   ├── runtime/python/              ← Python 3.11 standalone
#   └── runtime/parallax-venv/       ← venv avec parallax + ses deps (PyTorch...)
#
# Usage :
#   ./release-build.sh <bun-target> <pbs-arch> <accel>
# Ex (Linux x64 CUDA) :
#   ./release-build.sh bun-linux-x64 x86_64-unknown-linux-gnu cuda
# Ex (macOS arm64 MLX) :
#   ./release-build.sh bun-darwin-arm64 aarch64-apple-darwin mlx
#
# Variables d'env optionnelles :
#   FABI_VERSION       version qui sera affichée et embarquée (défaut: lit VERSION ou v0.0.0-dev)
#   PYTHON_BUILD_TAG   release tag de python-build-standalone (défaut: 20241016)
#   PARALLAX_SOURCE    path local ou spec pip pour parallax (défaut: ../packages/swarm-engine)
#   PARALLAX_EXTRA     extra pip forcé pour parallax (défaut: auto selon accel)
#   FABI_SKIP_PARALLAX  si "1", skip le venv parallax (utile pour test build fabi seul)

set -euo pipefail

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

BUN_TARGET="${1:-}"
PBS_ARCH="${2:-}"
ACCEL="${3:-cpu}"

if [ -z "$BUN_TARGET" ] || [ -z "$PBS_ARCH" ]; then
  echo "Usage : $0 <bun-target> <python-build-standalone-arch> [accel]" >&2
  echo "Ex    : $0 bun-linux-x64 x86_64-unknown-linux-gnu cuda" >&2
  exit 1
fi

if [[ "$BUN_TARGET" != bun-* ]]; then
  echo "Erreur : bun-target doit commencer par 'bun-' (ex: bun-linux-x64)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FABI_CLI_DIR="$ROOT/packages/fabi-cli"
SWARM_ENGINE_DIR="$ROOT/packages/swarm-engine"
DIST="$ROOT/dist"
PLATFORM_TAG="${BUN_TARGET#bun-}"           # linux-x64, darwin-arm64, etc.
PKG_NAME="fabi-${PLATFORM_TAG}-${ACCEL}"
PKG_DIR="$DIST/$PKG_NAME"
TARBALL="$DIST/${PKG_NAME}.tar.zst"

VERSION="${FABI_VERSION:-$(cat "$ROOT/VERSION" 2>/dev/null || echo "v0.0.0-dev")}"
PYTHON_BUILD_TAG="${PYTHON_BUILD_TAG:-20241016}"
PYTHON_VERSION="3.11.10"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf "\033[1;34m[release-build]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[release-build]\033[0m %s\n" "$1"; }
err()  { printf "\033[1;31m[release-build]\033[0m %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Pré-vérifs
# ---------------------------------------------------------------------------

for cmd in bun curl tar zstd; do
  command -v "$cmd" >/dev/null 2>&1 || { err "Outil requis manquant : $cmd"; exit 1; }
done

if [ ! -d "$FABI_CLI_DIR" ]; then
  err "$FABI_CLI_DIR introuvable. Lance d'abord scripts/setup.sh"
  exit 1
fi

if [ -z "${FABI_SKIP_PARALLAX:-}" ] && [ ! -d "$SWARM_ENGINE_DIR" ]; then
  err "$SWARM_ENGINE_DIR introuvable. Lance d'abord scripts/setup.sh ou utilise FABI_SKIP_PARALLAX=1"
  exit 1
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

log "Cible       : $BUN_TARGET / $PBS_ARCH / $ACCEL"
log "Version     : $VERSION"
log "Tarball     : $TARBALL"
log "Python PBS  : cpython-${PYTHON_VERSION}+${PYTHON_BUILD_TAG}-${PBS_ARCH}"
echo

rm -rf "$PKG_DIR" "$TARBALL"
mkdir -p "$PKG_DIR/bin" "$PKG_DIR/runtime"

# 1. Binaire fabi via le script de build officiel d'OpenCode (qui fait tout
# le boilerplate : génère models-snapshot, bundle le worker TUI, embed les
# migrations DB, etc. — bien plus complet qu'un simple `bun build --compile`).
log "(1/4) Compilation du binaire fabi (script/build.ts)…"
cd "$FABI_CLI_DIR"
bun install --frozen-lockfile --ignore-scripts

cd "$FABI_CLI_DIR/packages/opencode"

# Le script accepte :
#   --single             : build uniquement la plateforme courante (= du runner GitHub)
#   --skip-embed-web-ui  : on a supprimé packages/app, donc on skip
#   --skip-install       : skip le bun install cross-platform interne (déjà fait)
# Le résultat va dans packages/opencode/dist/<name>/bin/opencode.
rm -rf dist
bun run script/build.ts --single --skip-embed-web-ui --skip-install

# Localise le binaire produit (un seul dossier dans dist/ avec --single)
SRC_BIN_DIR=$(ls -d dist/*/ 2>/dev/null | head -1)
if [ -z "$SRC_BIN_DIR" ]; then
  err "Aucun dossier produit dans packages/opencode/dist/"
  exit 1
fi
SRC_BIN_NAME="opencode"
[[ "$BUN_TARGET" == bun-windows-* ]] && SRC_BIN_NAME="opencode.exe"
SRC_BIN="${SRC_BIN_DIR}bin/${SRC_BIN_NAME}"

if [ ! -x "$SRC_BIN" ]; then
  err "Binaire produit absent : $SRC_BIN"
  exit 1
fi

# Renomme opencode → fabi dans notre tarball
OUT_BIN_NAME="fabi"
[[ "$BUN_TARGET" == bun-windows-* ]] && OUT_BIN_NAME="fabi.exe"
cp "$SRC_BIN" "$PKG_DIR/bin/$OUT_BIN_NAME"
chmod +x "$PKG_DIR/bin/$OUT_BIN_NAME"
ok  "Binaire produit : $PKG_DIR/bin/$OUT_BIN_NAME ($(du -h "$PKG_DIR/bin/$OUT_BIN_NAME" | cut -f1))"

# 2. Python embeddable (python-build-standalone)
if [ -z "${FABI_SKIP_PARALLAX:-}" ]; then
  log "(2/4) Téléchargement de Python ${PYTHON_VERSION} standalone…"

  if [[ "$PBS_ARCH" == *windows* ]]; then
    PBS_FILENAME="cpython-${PYTHON_VERSION}+${PYTHON_BUILD_TAG}-${PBS_ARCH}-install_only.tar.gz"
  else
    PBS_FILENAME="cpython-${PYTHON_VERSION}+${PYTHON_BUILD_TAG}-${PBS_ARCH}-install_only_stripped.tar.gz"
  fi
  PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD_TAG}/${PBS_FILENAME}"

  TMP_PY="$(mktemp -d)"
  curl -fsSL "$PBS_URL" -o "$TMP_PY/python.tar.gz"
  tar -xzf "$TMP_PY/python.tar.gz" -C "$PKG_DIR/runtime/"
  # python-build-standalone extrait dans un dossier "python"
  mv "$PKG_DIR/runtime/python" "$PKG_DIR/runtime/python-base"
  rm -rf "$TMP_PY"
  ok  "Python standalone extrait dans runtime/python-base/"

  # 3. venv + parallax
  log "(3/4) Création du venv et installation de Parallax (peut prendre 5-15 min)…"
  PYTHON_BIN="$PKG_DIR/runtime/python-base/bin/python3"
  [[ "$PBS_ARCH" == *windows* ]] && PYTHON_BIN="$PKG_DIR/runtime/python-base/python.exe"

  "$PYTHON_BIN" -m venv "$PKG_DIR/runtime/parallax-venv"

  VENV_PIP="$PKG_DIR/runtime/parallax-venv/bin/pip"
  [[ "$PBS_ARCH" == *windows* ]] && VENV_PIP="$PKG_DIR/runtime/parallax-venv/Scripts/pip.exe"

  "$VENV_PIP" install --upgrade --quiet pip wheel setuptools

  # Choix de l'index PyTorch selon l'accélérateur
  EXTRA_PIP_ARGS=()
  case "$ACCEL" in
    cuda)
      EXTRA_PIP_ARGS=(--extra-index-url "https://download.pytorch.org/whl/cu121")
      ;;
    rocm)
      EXTRA_PIP_ARGS=(--extra-index-url "https://download.pytorch.org/whl/rocm6.0")
      ;;
    cpu|mlx)
      EXTRA_PIP_ARGS=(--extra-index-url "https://download.pytorch.org/whl/cpu")
      ;;
  esac

  PARALLAX_SPEC="${PARALLAX_SOURCE:-$SWARM_ENGINE_DIR}"
  PARALLAX_EXTRA="${PARALLAX_EXTRA:-}"
  if [ -z "$PARALLAX_EXTRA" ]; then
    case "$ACCEL" in
      mlx)
        PARALLAX_EXTRA="mac"
        ;;
      cuda)
        PARALLAX_EXTRA="gpu"
        ;;
      rocm)
        PARALLAX_EXTRA="vllm"
        ;;
      cpu)
        PARALLAX_EXTRA=""
        ;;
    esac
  fi

  PARALLAX_INSTALL_SPEC="$PARALLAX_SPEC"
  if [ -n "$PARALLAX_EXTRA" ]; then
    PARALLAX_INSTALL_SPEC="${PARALLAX_SPEC}[${PARALLAX_EXTRA}]"
  fi

  if [ -d "$PARALLAX_SPEC" ]; then
    "$VENV_PIP" install "${EXTRA_PIP_ARGS[@]}" -e "$PARALLAX_INSTALL_SPEC"
  else
    "$VENV_PIP" install "${EXTRA_PIP_ARGS[@]}" "$PARALLAX_INSTALL_SPEC"
  fi
  "$VENV_PIP" install --quiet requests
  ok  "Parallax installé"

  # Rendre les symlinks Python du venv relocatables.
  #
  # `python -m venv` crée sur macOS/Linux :
  #   runtime/parallax-venv/bin/python3 -> /abs/path/runtime/python-base/bin/python3
  # Les shebangs des entrypoints pointent ensuite vers parallax-venv/bin/python3.
  # Si on ne remplace pas ce symlink absolu, le tarball fonctionne sur la VM de
  # build mais casse chez l'utilisateur.
  if [[ "$PBS_ARCH" != *windows* ]]; then
    VENV_BIN="$PKG_DIR/runtime/parallax-venv/bin"
    ln -sf "../../python-base/bin/python3" "$VENV_BIN/python3"
    ln -sf "python3" "$VENV_BIN/python"
    ln -sf "python3" "$VENV_BIN/python3.11"
  fi

  # Vérification : le binaire parallax doit exister dans le venv
  PARALLAX_BIN="$PKG_DIR/runtime/parallax-venv/bin/parallax"
  [[ "$PBS_ARCH" == *windows* ]] && PARALLAX_BIN="$PKG_DIR/runtime/parallax-venv/Scripts/parallax.exe"

  if [ ! -x "$PARALLAX_BIN" ]; then
    err "Le binaire parallax est absent après pip install : $PARALLAX_BIN"
    exit 1
  fi

  # 3.5 Neutralisation des paths absolus dans le venv
  # ----------------------------------------------------------------------------
  # Un venv Python n'est PAS relocatable par défaut : les shebangs et pyvenv.cfg
  # contiennent le path absolu de la machine de build (ici la VM GitHub Actions,
  # /Users/runner/...). Sans ce traitement, le venv ne marche pas chez l'user.
  #
  # On remplace $PKG_DIR par un placeholder __FABI_INSTALL_ROOT__ qui sera
  # remplacé par le vrai install root par install.sh à l'extraction.
  PLACEHOLDER="__FABI_INSTALL_ROOT__"
  log "(3.5/4) Neutralisation des paths absolus du venv (relocatable)…"

  # On cible uniquement les fichiers texte du venv (pyvenv.cfg, scripts pip/parallax,
  # fichiers .py qui peuvent contenir des paths hardcodés, RECORD du dist-info)
  # On utilise grep -lI pour skipper les binaires (et éviter de corrompre les .so)
  PATCHED_COUNT=0
  while IFS= read -r f; do
    # macOS sed exige un suffix pour -i, Linux non — on utilise une syntaxe compatible
    sed -i.bak "s|$PKG_DIR|$PLACEHOLDER|g" "$f" && rm -f "$f.bak"
    PATCHED_COUNT=$((PATCHED_COUNT + 1))
  done < <(grep -rlI "$PKG_DIR" "$PKG_DIR/runtime" 2>/dev/null || true)
  ok  "Paths neutralisés dans $PATCHED_COUNT fichiers du venv"
else
  log "(2-3/4) FABI_SKIP_PARALLAX=1 — runtime Parallax non bundlé"
fi

# 4. Manifest version + tarball zstd
log "(4/4) Création du tarball compressé…"
cat > "$PKG_DIR/MANIFEST" <<EOF
fabi $VERSION
target=$BUN_TARGET
arch=$PBS_ARCH
accel=$ACCEL
python=$PYTHON_VERSION
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cd "$DIST"
tar --use-compress-program='zstd -19 -T0 --long=27' -cf "$TARBALL" "$(basename "$PKG_DIR")"

# Cleanup du dossier décompressé (on garde juste le tarball)
rm -rf "$PKG_DIR"

# Hash SHA256 pour vérification install.sh
sha256sum "$TARBALL" > "${TARBALL}.sha256" 2>/dev/null || shasum -a 256 "$TARBALL" > "${TARBALL}.sha256"

ok "Tarball : $TARBALL ($(du -h "$TARBALL" | cut -f1))"
ok "SHA256  : ${TARBALL}.sha256"
