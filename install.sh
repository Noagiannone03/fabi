#!/usr/bin/env bash
# Fabi installer — télécharge le bon tarball depuis GitHub Releases
# selon ton OS / arch / GPU et l'installe dans ~/.local/share/fabi/.
#
# Usage :
#   curl -fsSL https://fabi.aircarto.fr/install.sh | bash
# ou (sans le sous-domaine, direct depuis le repo) :
#   curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash
#
# Variables d'environnement reconnues :
#   FABI_VERSION   version à installer (défaut : latest)
#   FABI_ACCEL     forcer l'accélérateur (cpu / cuda / mlx / rocm)
#   FABI_INSTALL   dossier d'install (défaut : ~/.local/share/fabi)
#   FABI_BIN_DIR   où poser le symlink fabi (défaut : ~/.local/bin)
#   FABI_NO_PATH   si "1", ne touche pas au PATH (pas de modif .bashrc)
#   FABI_REPO      override repo source (défaut : Noagiannone03/fabi)

set -euo pipefail

# ---------------------------------------------------------------------------
# Couleurs (gracieux si pas de TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m';  C_DIM=$'\033[2m';     C_RESET=$'\033[0m'
  C_SUNSET=$'\033[38;2;255;140;66m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_RESET=""; C_SUNSET=""
fi

log()  { printf "%s[fabi-install]%s %s\n" "$C_BLUE"  "$C_RESET" "$1"; }
ok()   { printf "%s[fabi-install]%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf "%s[fabi-install]%s %s\n" "$C_YELLOW" "$C_RESET" "$1" >&2; }
err()  { printf "%s[fabi-install]%s %s\n" "$C_RED"   "$C_RESET" "$1" >&2; }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
cat <<EOF
${C_SUNSET}
  ███████╗ █████╗ ██████╗ ██╗
  ██╔════╝██╔══██╗██╔══██╗██║
  █████╗  ███████║██████╔╝██║
  ██╔══╝  ██╔══██║██╔══██╗██║
  ██║     ██║  ██║██████╔╝██║
  ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝${C_RESET}
${C_DIM}  CLI agentique open source qui rejoint le swarm Aircarto${C_RESET}

EOF

# ---------------------------------------------------------------------------
# Pré-vérifs
# ---------------------------------------------------------------------------
for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { err "Outil requis manquant : $cmd"; exit 1; }
done

# zstd : pas standard sur tous les Linux, on suggère l'install
if ! command -v zstd >/dev/null 2>&1; then
  warn "zstd n'est pas installé."
  warn "  Ubuntu/Debian : sudo apt install zstd"
  warn "  macOS         : brew install zstd"
  warn "  Fedora/RHEL   : sudo dnf install zstd"
  exit 1
fi

# ---------------------------------------------------------------------------
# Détection plateforme
# ---------------------------------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) err "Architecture non supportée : $ARCH"; exit 1 ;;
esac

case "$OS" in
  linux|darwin) ;;
  *) err "OS non supporté : $OS (Windows : utilise install.ps1 dans PowerShell)"; exit 1 ;;
esac

# Détection accélérateur
ACCEL="${FABI_ACCEL:-}"
if [ -z "$ACCEL" ]; then
  if [ "$OS" = "darwin" ] && [ "$ARCH" = "arm64" ]; then
    ACCEL="mlx"
  elif command -v nvidia-smi >/dev/null 2>&1; then
    ACCEL="cuda"
  elif [ -d /opt/rocm ]; then
    ACCEL="rocm"
  else
    ACCEL="cpu"
  fi
fi

PLATFORM="${OS}-${ARCH}-${ACCEL}"
log "Plateforme détectée : ${C_GREEN}${PLATFORM}${C_RESET}"

# ---------------------------------------------------------------------------
# Résolution version + URLs
# ---------------------------------------------------------------------------
FABI_REPO="${FABI_REPO:-Noagiannone03/fabi}"
FABI_VERSION="${FABI_VERSION:-latest}"

if [ "$FABI_VERSION" = "latest" ]; then
  log "Résolution de la dernière version…"
  FABI_VERSION="$(
    curl -fsSL "https://api.github.com/repos/${FABI_REPO}/releases/latest" \
      | grep '"tag_name"' \
      | head -1 \
      | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
  )"
  if [ -z "$FABI_VERSION" ]; then
    err "Impossible de résoudre la dernière version. Vérifie que ${FABI_REPO} a au moins une release."
    exit 1
  fi
fi

ok "Version cible : ${FABI_VERSION}"

TARBALL_NAME="fabi-${PLATFORM}.tar.zst"
TARBALL_URL="https://github.com/${FABI_REPO}/releases/download/${FABI_VERSION}/${TARBALL_NAME}"
SHA_URL="${TARBALL_URL}.sha256"

# ---------------------------------------------------------------------------
# Téléchargement
# ---------------------------------------------------------------------------
INSTALL_ROOT="${FABI_INSTALL:-$HOME/.local/share/fabi}"
BIN_DIR="${FABI_BIN_DIR:-$HOME/.local/bin}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "Téléchargement : ${C_DIM}${TARBALL_URL}${C_RESET}"
if ! curl -fL --progress-bar "$TARBALL_URL" -o "$TMP_DIR/fabi.tar.zst"; then
  err "Échec du téléchargement. Vérifie l'URL et que la release publie bien ce tarball pour ta plateforme."
  err "  → $TARBALL_URL"
  exit 1
fi

# Vérification SHA256 (best effort — on warn si le .sha256 est absent)
log "Vérification SHA256…"
if curl -fsSL "$SHA_URL" -o "$TMP_DIR/fabi.tar.zst.sha256" 2>/dev/null; then
  EXPECTED="$(awk '{print $1}' "$TMP_DIR/fabi.tar.zst.sha256")"
  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "$TMP_DIR/fabi.tar.zst" | awk '{print $1}')"
  else
    ACTUAL="$(shasum -a 256 "$TMP_DIR/fabi.tar.zst" | awk '{print $1}')"
  fi
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    err "SHA256 mismatch ! Le fichier est peut-être corrompu ou altéré."
    err "  Attendu : $EXPECTED"
    err "  Reçu    : $ACTUAL"
    exit 1
  fi
  ok "Intégrité vérifiée"
else
  warn "Pas de fichier .sha256 dispo — vérification skipée"
fi

# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------
log "Installation dans ${C_DIM}${INSTALL_ROOT}${C_RESET}"

# Si déjà installé, on backup avant écrasement
if [ -d "$INSTALL_ROOT" ]; then
  BACKUP="${INSTALL_ROOT}.backup-$(date +%s)"
  warn "Install existante détectée, backup → $BACKUP"
  mv "$INSTALL_ROOT" "$BACKUP"
fi

mkdir -p "$INSTALL_ROOT"
tar --use-compress-program=unzstd -xf "$TMP_DIR/fabi.tar.zst" -C "$INSTALL_ROOT" --strip-components=1

if [ ! -x "$INSTALL_ROOT/bin/fabi" ]; then
  err "Le binaire fabi est absent après extraction : $INSTALL_ROOT/bin/fabi"
  exit 1
fi

# ---------------------------------------------------------------------------
# Symlink dans BIN_DIR
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_ROOT/bin/fabi" "$BIN_DIR/fabi"
ok "Symlink créé : ${BIN_DIR}/fabi → ${INSTALL_ROOT}/bin/fabi"

# ---------------------------------------------------------------------------
# Vérification PATH
# ---------------------------------------------------------------------------
PATH_OK=0
case ":$PATH:" in
  *":$BIN_DIR:"*) PATH_OK=1 ;;
esac

if [ "$PATH_OK" = "0" ] && [ "${FABI_NO_PATH:-0}" != "1" ]; then
  warn "$BIN_DIR n'est pas dans ton PATH."
  warn "Ajoute cette ligne à ton ~/.bashrc ou ~/.zshrc :"
  echo
  echo "    export PATH=\"$BIN_DIR:\$PATH\""
  echo
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
ok "${C_GREEN}Fabi ${FABI_VERSION} installé avec succès${C_RESET}"
echo
echo "  Lance avec : ${C_GREEN}fabi${C_RESET}"
echo "  Aide       : ${C_DIM}fabi --help${C_RESET}"
echo "  Mise à jour: ${C_DIM}curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash${C_RESET}"
echo
