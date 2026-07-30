#!/usr/bin/env bash
# Fabi installer — télécharge le bon tarball depuis GitHub Releases
# selon ton OS / arch / GPU et l'installe dans ~/.local/share/fabi/.
#
# Usage :
#   curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash
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
#   FABI_TARBALL_PATH archive locale qualifiée (tests/installations hors ligne)
#   FABI_ZSTD_PATH décompresseur local qualifié + sidecar .sha256 (hors ligne)

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
${C_DIM}  Agent terminal open source connecté au swarm Fabi${C_RESET}

EOF

# ---------------------------------------------------------------------------
# Pré-vérifs
# ---------------------------------------------------------------------------
for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { err "Outil requis manquant : $cmd"; exit 1; }
done

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
DL_BASE="https://github.com/${FABI_REPO}/releases/download/${FABI_VERSION}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_sha256_sidecar() {
  path="$1"
  sidecar="$2"
  label="$3"
  EXPECTED="$(awk '{print $1}' "$sidecar")"
  if ! printf '%s\n' "$EXPECTED" | grep -Eq '^[0-9a-fA-F]{64}$'; then
    err "SHA256 invalide pour $label"
    exit 1
  fi
  ACTUAL="$(sha256_file "$path")"
  if [ "$(printf '%s' "$EXPECTED" | tr '[:upper:]' '[:lower:]')" != "$ACTUAL" ]; then
    err "SHA256 mismatch pour $label"
    err "  Attendu : $EXPECTED"
    err "  Reçu    : $ACTUAL"
    exit 1
  fi
}

# Le zstd système est un chemin rapide facultatif. Sur une machine neuve,
# télécharger le petit décompresseur officiel construit avec la release rend
# l'installation autonome sans Homebrew, apt, winget ni privilèges admin.
if [ -n "${FABI_ZSTD_PATH:-}" ]; then
  if [ ! -f "$FABI_ZSTD_PATH" ] || [ ! -f "${FABI_ZSTD_PATH}.sha256" ]; then
    err "FABI_ZSTD_PATH doit pointer vers un fichier et son sidecar .sha256"
    exit 1
  fi
  ZSTD_BIN="$TMP_DIR/fabi-unzstd"
  cp "$FABI_ZSTD_PATH" "$ZSTD_BIN"
  cp "${FABI_ZSTD_PATH}.sha256" "$TMP_DIR/fabi-unzstd.sha256"
  verify_sha256_sidecar "$ZSTD_BIN" "$TMP_DIR/fabi-unzstd.sha256" "le décompresseur local"
  chmod +x "$ZSTD_BIN"
elif command -v zstd >/dev/null 2>&1; then
  ZSTD_BIN="$(command -v zstd)"
else
  ZSTD_HELPER_NAME="fabi-unzstd-${PLATFORM}"
  ZSTD_HELPER_URL="${DL_BASE}/${ZSTD_HELPER_NAME}"
  log "zstd absent → téléchargement du décompresseur autonome…"
  if ! curl -fL --progress-bar "$ZSTD_HELPER_URL" -o "$TMP_DIR/fabi-unzstd"; then
    err "Décompresseur autonome absent de la release : $ZSTD_HELPER_URL"
    exit 1
  fi
  if ! curl -fsSL "${ZSTD_HELPER_URL}.sha256" -o "$TMP_DIR/fabi-unzstd.sha256"; then
    err "Checksum du décompresseur autonome absent"
    exit 1
  fi
  verify_sha256_sidecar "$TMP_DIR/fabi-unzstd" "$TMP_DIR/fabi-unzstd.sha256" "le décompresseur autonome"
  chmod +x "$TMP_DIR/fabi-unzstd"
  ZSTD_BIN="$TMP_DIR/fabi-unzstd"
  ok "Décompresseur autonome vérifié"
fi

# Asset splitté ? release-build.sh publie un manifeste `.parts` quand le tarball
# dépasse 2 Gio (limite GitHub) → on télécharge les parties et on réassemble (cat).
# Sinon, téléchargement direct du tarball unique (cas des petites plateformes).
if [ -n "${FABI_TARBALL_PATH:-}" ]; then
  if [ ! -f "$FABI_TARBALL_PATH" ]; then
    err "Archive locale introuvable : $FABI_TARBALL_PATH"
    exit 1
  fi
  log "Archive locale : ${C_DIM}${FABI_TARBALL_PATH}${C_RESET}"
  cp "$FABI_TARBALL_PATH" "$TMP_DIR/fabi.tar.zst"
elif curl -fsSL "${TARBALL_URL}.parts" -o "$TMP_DIR/parts.txt" 2>/dev/null; then
  log "Asset volumineux → téléchargement en parties + réassemblage…"
  : > "$TMP_DIR/fabi.tar.zst"
  while IFS= read -r part; do
    part="$(printf '%s' "$part" | tr -d '\r' | tr -d ' ')"
    [ -z "$part" ] && continue
    log "  partie : ${C_DIM}${part}${C_RESET}"
    if ! curl -fL --progress-bar "${DL_BASE}/${part}" -o "$TMP_DIR/part"; then
      err "Échec du téléchargement de la partie : ${DL_BASE}/${part}"
      exit 1
    fi
    cat "$TMP_DIR/part" >> "$TMP_DIR/fabi.tar.zst"
    rm -f "$TMP_DIR/part"
  done < "$TMP_DIR/parts.txt"
else
  log "Téléchargement : ${C_DIM}${TARBALL_URL}${C_RESET}"
  if ! curl -fL --progress-bar "$TARBALL_URL" -o "$TMP_DIR/fabi.tar.zst"; then
    err "Échec du téléchargement. Vérifie l'URL et que la release publie bien ce tarball pour ta plateforme."
    err "  → $TARBALL_URL"
    exit 1
  fi
fi

# Vérification SHA256 (best effort — on warn si le .sha256 est absent)
log "Vérification SHA256…"
if [ -n "${FABI_TARBALL_PATH:-}" ] && [ -f "${FABI_TARBALL_PATH}.sha256" ]; then
  cp "${FABI_TARBALL_PATH}.sha256" "$TMP_DIR/fabi.tar.zst.sha256"
elif [ -z "${FABI_TARBALL_PATH:-}" ]; then
  curl -fsSL "$SHA_URL" -o "$TMP_DIR/fabi.tar.zst.sha256" 2>/dev/null || true
fi
if [ -f "$TMP_DIR/fabi.tar.zst.sha256" ]; then
  EXPECTED="$(awk '{print $1}' "$TMP_DIR/fabi.tar.zst.sha256")"
  ACTUAL="$(sha256_file "$TMP_DIR/fabi.tar.zst")"
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
# Extraction et activation transactionnelle
# ---------------------------------------------------------------------------
log "Installation dans ${C_DIM}${INSTALL_ROOT}${C_RESET}"

STAGING_ROOT="$TMP_DIR/install"
mkdir -p "$STAGING_ROOT"
"$ZSTD_BIN" -q -f -d "$TMP_DIR/fabi.tar.zst" -o "$TMP_DIR/fabi.tar"
tar -xf "$TMP_DIR/fabi.tar" -C "$STAGING_ROOT" --strip-components=1

if [ ! -x "$STAGING_ROOT/bin/fabi" ]; then
  err "Le binaire fabi est absent après extraction : $STAGING_ROOT/bin/fabi"
  exit 1
fi

# ---------------------------------------------------------------------------
# Relocalisation du venv Python bundlé
# ---------------------------------------------------------------------------
# Le tarball contient un venv Python pré-installé avec Parallax. Le venv
# n'est pas relocatable par défaut (paths absolus de la machine de build),
# release-build.sh a remplacé ces paths par le placeholder
# __FABI_INSTALL_ROOT__ et enregistré les fichiers texte concernés dans un
# manifeste. On ne scanne plus aveuglément les binaires du runtime.
PLACEHOLDER="__FABI_INSTALL_ROOT__"
RELOCATION_MANIFEST="$STAGING_ROOT/runtime/relocation-manifest.txt"
if [ -f "$RELOCATION_MANIFEST" ]; then
  log "Relocalisation du runtime Python…"
  RELOC_COUNT=0
  while IFS= read -r relative; do
    relative="$(printf '%s' "$relative" | tr -d '\r')"
    [ -z "$relative" ] && continue
    case "$relative" in
      /*|../*|*/../*) err "Chemin de relocalisation invalide : $relative"; exit 1 ;;
      runtime/*) ;;
      *) err "Chemin de relocalisation hors runtime : $relative"; exit 1 ;;
    esac
    file="$STAGING_ROOT/$relative"
    if [ ! -f "$file" ] || ! grep -q "$PLACEHOLDER" "$file"; then
      err "Fichier de relocalisation invalide : $relative"
      exit 1
    fi
    sed -i.bak "s|$PLACEHOLDER|$INSTALL_ROOT|g" "$file" && rm -f "$file.bak"
    RELOC_COUNT=$((RELOC_COUNT + 1))
  done < "$RELOCATION_MANIFEST"
  if [ "$RELOC_COUNT" -eq 0 ]; then
    err "Manifeste de relocalisation vide"
    exit 1
  fi
  ok "Runtime relocalisé dans $RELOC_COUNT fichiers"
elif [ -d "$STAGING_ROOT/runtime" ] && grep -rqI "$PLACEHOLDER" "$STAGING_ROOT/runtime" 2>/dev/null; then
  # Compatibilité avec les anciennes RC sans manifeste.
  warn "Runtime ancien sans manifeste de relocalisation ; fallback par scan texte"
  while IFS= read -r file; do
    sed -i.bak "s|$PLACEHOLDER|$INSTALL_ROOT|g" "$file" && rm -f "$file.bak"
  done < <(grep -rlI "$PLACEHOLDER" "$STAGING_ROOT/runtime" 2>/dev/null || true)
fi

# Une mise à jour ne doit jamais déplacer les identités Iroh, la racine TUF,
# les journaux SSE ou l'état de fencing avec les binaires. Le paquet déclare
# donc explicitement les entrées qu'il possède. Les autres chemins présents
# sous INSTALL_ROOT appartiennent à l'utilisateur et restent en place.
MANAGED_PATHS_FILE="$STAGING_ROOT/.fabi-managed-paths"
if [ ! -f "$MANAGED_PATHS_FILE" ]; then
  err "Manifeste des chemins gérés absent : .fabi-managed-paths"
  exit 1
fi
MANAGED_PATHS=""
while IFS= read -r managed; do
  managed="$(printf '%s' "$managed" | tr -d '\r')"
  [ -z "$managed" ] && continue
  case "$managed" in
    .|..|/*|*/*|*\\*) err "Chemin géré invalide : $managed"; exit 1 ;;
  esac
  if [ ! -e "$STAGING_ROOT/$managed" ] && [ ! -L "$STAGING_ROOT/$managed" ]; then
    err "Chemin géré absent du paquet : $managed"
    exit 1
  fi
  MANAGED_PATHS="${MANAGED_PATHS}${managed}
"
done < "$MANAGED_PATHS_FILE"
if [ -z "$MANAGED_PATHS" ]; then
  err "Manifeste des chemins gérés vide"
  exit 1
fi

mkdir -p "$INSTALL_ROOT"
BACKUP="${INSTALL_ROOT}.backup-$(date +%s)-$$"
mkdir -p "$BACKUP"
BACKUP_USED=0
while IFS= read -r managed; do
  [ -z "$managed" ] && continue
  if [ -e "$INSTALL_ROOT/$managed" ] || [ -L "$INSTALL_ROOT/$managed" ]; then
    mv "$INSTALL_ROOT/$managed" "$BACKUP/$managed"
    BACKUP_USED=1
  fi
done <<EOF
$MANAGED_PATHS
EOF

ACTIVATION_FAILED=0
while IFS= read -r managed; do
  [ -z "$managed" ] && continue
  if ! mv "$STAGING_ROOT/$managed" "$INSTALL_ROOT/$managed"; then
    ACTIVATION_FAILED=1
    break
  fi
done <<EOF
$MANAGED_PATHS
EOF

if [ "$ACTIVATION_FAILED" -ne 0 ]; then
  err "Activation du nouveau runtime échouée ; restauration de la version précédente"
  while IFS= read -r managed; do
    [ -z "$managed" ] && continue
    rm -rf "$INSTALL_ROOT/$managed"
    if [ -e "$BACKUP/$managed" ] || [ -L "$BACKUP/$managed" ]; then
      mv "$BACKUP/$managed" "$INSTALL_ROOT/$managed"
    fi
  done <<EOF
$MANAGED_PATHS
EOF
  exit 1
fi

RUNTIME_PYTHON="$INSTALL_ROOT/runtime/parallax-venv/bin/python"
if [ ! -x "$RUNTIME_PYTHON" ] || ! "$RUNTIME_PYTHON" -c \
  'from parallax.cli import main as parallax_main; from backend.server.request_agent_frontend import main as request_agent_main'; then
  err "Les entrypoints Parallax et Request Agent activés ne peuvent pas être importés ; restauration de la version précédente"
  while IFS= read -r managed; do
    [ -z "$managed" ] && continue
    rm -rf "$INSTALL_ROOT/$managed"
    if [ -e "$BACKUP/$managed" ] || [ -L "$BACKUP/$managed" ]; then
      mv "$BACKUP/$managed" "$INSTALL_ROOT/$managed"
    fi
  done <<EOF
$MANAGED_PATHS
EOF
  exit 1
fi

if [ "$BACKUP_USED" -eq 1 ]; then
  warn "Ancien runtime sauvegardé dans $BACKUP"
else
  rmdir "$BACKUP"
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
