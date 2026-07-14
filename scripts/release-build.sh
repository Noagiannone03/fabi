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
#   ├── runtime/python/              ← Python 3.12 standalone
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
# Parallax publie désormais ses kernels Metal avec l'ABI CPython 3.12 et le
# wheel vLLM-Windows est lui aussi cp312. Une seule version sur toutes les
# plateformes évite qu'un runtime Fabi accepte le code Python mais échoue au
# premier import natif (`_ext.cpython-311` absent).
PYTHON_VERSION="3.12.7"

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
# Le résultat va dans packages/opencode/dist/<name>/bin/fabi : depuis le rebrand
# de fabi-cli, build.ts (const PRODUCT = "fabi") compile directement le binaire
# sous le nom `fabi` (avant il sortait `opencode` et on le renommait ici).
rm -rf dist
bun run script/build.ts --single --skip-embed-web-ui --skip-install

# Localise le binaire produit (un seul dossier dans dist/ avec --single)
SRC_BIN_DIR=$(ls -d dist/*/ 2>/dev/null | head -1)
if [ -z "$SRC_BIN_DIR" ]; then
  err "Aucun dossier produit dans packages/opencode/dist/"
  exit 1
fi
SRC_BIN_NAME="fabi"
[[ "$BUN_TARGET" == bun-windows-* ]] && SRC_BIN_NAME="fabi.exe"
SRC_BIN="${SRC_BIN_DIR}bin/${SRC_BIN_NAME}"

if [ ! -x "$SRC_BIN" ]; then
  err "Binaire produit absent : $SRC_BIN"
  err "  (build.ts doit émettre dist/<target>/bin/fabi — vérifie PRODUCT dans fabi-cli)"
  exit 1
fi

# Copie le binaire dans le tarball (déjà nommé `fabi` par build.ts)
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

  # 2.5. Source Parallax embarquée
  # ----------------------------------------------------------------------------
  # Parallax doit être installé en editable (`pip install -e`) pour suivre son
  # README et contourner le packaging wheel upstream incomplet. Un editable
  # écrit un fichier .pth vers le dossier source : ce dossier doit donc vivre
  # dans le tarball, pas seulement sur la machine GitHub Actions.
  PARALLAX_BUNDLE_DIR="$PKG_DIR/runtime/parallax-src"
  log "(2.5/4) Copie du source Parallax dans le runtime…"
  mkdir -p "$PARALLAX_BUNDLE_DIR"
  # tar-pipe plutôt que rsync : rsync n'est PAS disponible sur les runners
  # Windows (Git Bash). tar est présent partout (macOS / Linux / Windows 10+)
  # et gère les exclusions de la même façon.
  ( cd "$SWARM_ENGINE_DIR" && tar \
      --exclude=".git" \
      --exclude=".venv" \
      --exclude="__pycache__" \
      --exclude="*.pyc" \
      -cf - . ) | ( cd "$PARALLAX_BUNDLE_DIR" && tar -xf - )
  ok  "Source Parallax embarquée dans runtime/parallax-src/"

  # 3. venv + parallax
  log "(3/4) Création du venv et installation de Parallax (peut prendre 5-15 min)…"
  PYTHON_BIN="$PKG_DIR/runtime/python-base/bin/python3"
  [[ "$PBS_ARCH" == *windows* ]] && PYTHON_BIN="$PKG_DIR/runtime/python-base/python.exe"

  "$PYTHON_BIN" -m venv "$PKG_DIR/runtime/parallax-venv"

  VENV_PIP="$PKG_DIR/runtime/parallax-venv/bin/pip"
  [[ "$PBS_ARCH" == *windows* ]] && VENV_PIP="$PKG_DIR/runtime/parallax-venv/Scripts/pip.exe"

  # Python du venv — on l'utilise via `python -m pip` pour mettre à jour pip :
  # sur Windows, pip.exe ne peut pas se remplacer lui-même (exe verrouillé pendant
  # qu'il tourne → "To modify pip, please run ..."). `python -m pip` contourne ça.
  VENV_PY="$PKG_DIR/runtime/parallax-venv/bin/python"
  [[ "$PBS_ARCH" == *windows* ]] && VENV_PY="$PKG_DIR/runtime/parallax-venv/Scripts/python.exe"

  "$VENV_PY" -m pip install --upgrade --quiet pip wheel setuptools

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

  PARALLAX_SPEC="${PARALLAX_SOURCE:-$PARALLAX_BUNDLE_DIR}"

  if [[ "$PBS_ARCH" == *windows* ]]; then
    # --- Windows natif (NVIDIA) : wheel vLLM-Windows + Parallax CORE (sans mlx) ---
    # mlx n'a AUCUN build Windows. Le chemin vLLM de Parallax est désormais mlx-free
    # (cf. swarm-engine, branche production, commit "decouple ... from mlx") : on
    # installe donc Parallax SANS les extras mac/gpu/vllm (qui tirent tous mlx), et on
    # ajoute à part le wheel vLLM compilé nativement pour Windows par SystemPanic.
    # CUDA 12.4 (cu124) = compatibilité driver maximale (la grande majorité des PC).
    FABI_VLLM_WIN_WHEEL="${FABI_VLLM_WIN_WHEEL:-https://github.com/SystemPanic/vllm-windows/releases/download/v0.16.0/vllm-0.16.0+cu124-cp312-cp312-win_amd64.whl}"
    # Les wheels SystemPanic épinglent un torch NIGHTLY DATÉ (ex.
    # torch==2.11.0.dev20260216+cu126) qui finit PURGÉ de l'index pytorch → install
    # non reproductible dans le temps. On RELÂCHE donc ce pin : on repacke le wheel
    # pour remplacer "torch==<nightly figé>" par "torch" (non contraint), puis on
    # installe un torch STABLE de la même série (2.11.x, compatible ABI). `wheel
    # unpack`/`pack` régénère le RECORD proprement (pas d'édition manuelle bancale).
    # torch + torchaudio en lockstep (2.11.0) ; torchvision résolu par pip pour
    # matcher torch 2.11.0 (il déclare lui-même sa dépendance torch).
    FABI_TORCH_SPEC="${FABI_TORCH_SPEC:-torch==2.11.0 torchvision torchaudio==2.11.0}"
    FABI_TORCH_INDEX="${FABI_TORCH_INDEX:-https://download.pytorch.org/whl/cu126}"
    WHL_TMP="$(mktemp -d)"
    mkdir -p "$WHL_TMP/unpacked" "$WHL_TMP/repacked"
    # garder le NOM de wheel d'origine : `wheel unpack` le parse (sinon "Bad wheel filename").
    WHEEL_FILE="$WHL_TMP/$(basename "$FABI_VLLM_WIN_WHEEL")"
    log "Wheel vLLM-Windows : $FABI_VLLM_WIN_WHEEL"
    curl -fsSL "$FABI_VLLM_WIN_WHEEL" -o "$WHEEL_FILE"
    "$VENV_PY" -m pip install --quiet --upgrade wheel
    "$VENV_PY" -m wheel unpack "$WHEEL_FILE" -d "$WHL_TMP/unpacked"
    META="$(ls "$WHL_TMP"/unpacked/*/*.dist-info/METADATA)"
    # relâche les pins figés de torch ET torchvision/torchaudio (même problème de
    # nightly datée purgée) → on les rend non contraints, puis on installe le trio
    # stable assorti juste avant.
    sed -i.bak -E 's/^Requires-Dist: (torch|torchvision|torchaudio)==.*/Requires-Dist: \1/' "$META" && rm -f "$META.bak"
    UNPACKED_DIR="$(ls -d "$WHL_TMP"/unpacked/*/)"
    "$VENV_PY" -m wheel pack "$UNPACKED_DIR" -d "$WHL_TMP/repacked"
    log "Torch stable       : $FABI_TORCH_SPEC ($FABI_TORCH_INDEX)"
    # shellcheck disable=SC2086 -- on veut le word-split (plusieurs paquets)
    "$VENV_PIP" install $FABI_TORCH_SPEC --extra-index-url "$FABI_TORCH_INDEX"
    "$VENV_PIP" install "$WHL_TMP"/repacked/*.whl --extra-index-url "$FABI_TORCH_INDEX"
    rm -rf "$WHL_TMP"
    if [ -d "$PARALLAX_SPEC" ]; then
      "$VENV_PIP" install -e "$PARALLAX_SPEC"
    else
      "$VENV_PIP" install "$PARALLAX_SPEC"
    fi
    "$VENV_PIP" install --quiet requests
    ok  "Parallax (core, mlx-free) + vLLM natif Windows installés"
  else
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
  fi

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
    ln -sf "python3" "$VENV_BIN/python3.12"
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

  # 3.6 Allègement du venv — on retire ce qui est INUTILE à l'exécution. Réduit
  # fortement la taille (le runtime CUDA frôle la limite d'asset GitHub de 2 Gio)
  # et accélère le download. Rien de tout ça n'est requis pour importer/exécuter :
  #   - __pycache__ / *.pyc : régénérés au 1er import
  #   - *.pyi : stubs de typage (dev only)
  #   - *.lib / *.a : libs statiques de LINK (compilation d'extensions), pas le runtime
  #   - test / tests : suites de tests des paquets
  log "(3.6/4) Allègement du venv (caches, stubs, libs statiques, tests)…"
  VENV_ROOT="$PKG_DIR/runtime/parallax-venv"
  BEFORE_SZ="$(du -sh "$VENV_ROOT" 2>/dev/null | cut -f1)"
  find "$VENV_ROOT" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  find "$VENV_ROOT" -type f \( -name "*.pyc" -o -name "*.pyi" -o -name "*.lib" -o -name "*.a" \) -delete 2>/dev/null || true
  find "$VENV_ROOT" -type d \( -name "test" -o -name "tests" \) -prune -exec rm -rf {} + 2>/dev/null || true
  ok  "Venv allégé : $BEFORE_SZ -> $(du -sh "$VENV_ROOT" 2>/dev/null | cut -f1)"
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
opencode_revision=$(git -C "$FABI_CLI_DIR" rev-parse HEAD)
parallax_revision=$(git -C "$SWARM_ENGINE_DIR" rev-parse HEAD)
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cd "$DIST"
tar --use-compress-program='zstd -19 -T0 --long=27' -cf "$TARBALL" "$(basename "$PKG_DIR")"

# Cleanup du dossier décompressé (on garde juste le tarball)
rm -rf "$PKG_DIR"

# Hash SHA256 du tarball ENTIER (vérifié par l'installeur après réassemblage).
sha256sum "$TARBALL" > "${TARBALL}.sha256" 2>/dev/null || shasum -a 256 "$TARBALL" > "${TARBALL}.sha256"

ok "Tarball : $TARBALL ($(du -h "$TARBALL" | cut -f1))"
ok "SHA256  : ${TARBALL}.sha256"

# 4.5 Découpage si le tarball dépasse la limite d'asset GitHub (2 Gio).
# ----------------------------------------------------------------------------
# Un runtime CUDA peut dépasser 2 Gio compressé. GitHub refuse alors l'asset.
# Pratique standard : découper en parties < 2 Gio, que l'installeur réassemble
# (cat) avant extraction. On publie alors les `.part??` + un manifeste `.parts`
# (sa présence signale à l'installeur que l'asset est splitté) + le `.sha256`
# du tout (vérifié après réassemblage). Les petits tarballs restent en 1 fichier.
SPLIT_THRESHOLD_BYTES=$(( 1900 * 1024 * 1024 ))   # 1900 Mio (marge sous 2 Gio)
TARBALL_BYTES=$(wc -c < "$TARBALL" | tr -d ' ')
if [ "$TARBALL_BYTES" -gt "$SPLIT_THRESHOLD_BYTES" ]; then
  log "Tarball > 1900 Mio → découpage en parties (limite asset GitHub = 2 Gio)…"
  split -b 1800m "$TARBALL" "${TARBALL}.part"
  ( cd "$DIST" && ls "$(basename "$TARBALL")".part?? | LC_ALL=C sort > "$(basename "$TARBALL").parts" )
  rm -f "$TARBALL"   # le tout dépasse 2 Gio : on ne publie que les parties
  ok "Découpé en : $(tr '\n' ' ' < "${TARBALL}.parts")"
fi
