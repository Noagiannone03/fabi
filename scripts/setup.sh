#!/usr/bin/env bash
#
# setup.sh — clone les upstreams Fabi et configure les remotes.
#
# Idempotent : peut être relancé sans casser un setup existant.
#
# Variables d'environnement (optionnelles) :
#   OPENCODE_UPSTREAM      URL upstream OpenCode (défaut: github.com/sst/opencode)
#   PARALLAX_UPSTREAM      URL upstream Parallax (défaut: github.com/GradientHQ/parallax)
#   OPENCODE_FORK_REMOTE   URL de TON fork OpenCode (sera origin) — vide si pas encore créé
#   PARALLAX_FORK_REMOTE   URL de TON fork Parallax (sera origin) — vide si pas encore créé
#   OPENCODE_REF           branche/tag/commit à checkout après clone (optionnel)
#   PARALLAX_REF           branche/tag/commit à checkout après clone (optionnel)

set -euo pipefail

# Couleurs (gracieuse dégradation si pas de TTY)
if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

log()    { printf "%s[fabi setup]%s %s\n" "$C_BLUE" "$C_RESET" "$1"; }
warn()   { printf "%s[fabi setup]%s %s\n" "$C_YELLOW" "$C_RESET" "$1" >&2; }
err()    { printf "%s[fabi setup]%s %s\n" "$C_RED" "$C_RESET" "$1" >&2; }
ok()     { printf "%s[fabi setup]%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }

# Racine du projet (le script vit dans scripts/, on remonte d'un cran)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_DIR="$PROJECT_ROOT/packages"

OPENCODE_UPSTREAM="${OPENCODE_UPSTREAM:-https://github.com/sst/opencode.git}"
PARALLAX_UPSTREAM="${PARALLAX_UPSTREAM:-https://github.com/GradientHQ/parallax.git}"
OPENCODE_FORK_REMOTE="${OPENCODE_FORK_REMOTE:-}"
PARALLAX_FORK_REMOTE="${PARALLAX_FORK_REMOTE:-}"
OPENCODE_REF="${OPENCODE_REF:-}"
PARALLAX_REF="${PARALLAX_REF:-}"

# ----------------------------------------------------------------------------
# Pré-vérifs
# ----------------------------------------------------------------------------

if ! command -v git >/dev/null 2>&1; then
  err "git n'est pas installé. Installe-le avant de continuer."
  exit 1
fi

mkdir -p "$PACKAGES_DIR"

# ----------------------------------------------------------------------------
# Helper : clone un upstream et configure les remotes proprement
# ----------------------------------------------------------------------------
# Args:
#   $1 : nom du sous-dossier (ex: "fabi-cli")
#   $2 : URL upstream
#   $3 : URL de notre fork (peut être vide)
#   $4 : ref à checkout (peut être vide)
clone_or_setup() {
  local subdir="$1"
  local upstream_url="$2"
  local fork_url="$3"
  local checkout_ref="$4"
  local target="$PACKAGES_DIR/$subdir"

  # Source du clone : si le fork user est fourni → on clone depuis le fork
  # (= contient nos modifs Fabi). Sinon → clone d'upstream (cas du dev qui
  # n'a pas encore créé son fork GitHub).
  local clone_url="${fork_url:-$upstream_url}"

  if [[ -d "$target/.git" ]]; then
    log "$subdir : repo déjà présent, on configure juste les remotes."
  else
    log "$subdir : clonage depuis $clone_url …"
    git clone "$clone_url" "$target"
    ok  "$subdir : clone terminé."
  fi

  pushd "$target" >/dev/null

  # Configure le remote upstream (on l'écrase si déjà existant pour être sûr)
  if git remote | grep -qx "upstream"; then
    git remote set-url upstream "$upstream_url"
  else
    git remote add upstream "$upstream_url"
  fi

  # Configure le remote origin :
  #   - si fork_url fourni → on le pointe dessus
  #   - sinon → on le supprime pour éviter les push accidentels vers upstream
  if [[ -n "$fork_url" ]]; then
    if git remote | grep -qx "origin"; then
      git remote set-url origin "$fork_url"
    else
      git remote add origin "$fork_url"
    fi
    log "$subdir : origin = $fork_url"
  else
    if git remote | grep -qx "origin"; then
      # Si origin pointe encore sur upstream (cas du clone initial), on le retire
      local origin_url
      origin_url="$(git remote get-url origin 2>/dev/null || true)"
      if [[ "$origin_url" == "$upstream_url" ]]; then
        warn "$subdir : origin pointait sur upstream, je le retire (évite push accidentel)."
        git remote remove origin
      fi
    fi
    warn "$subdir : pas d'origin configuré. Crée ton fork GitHub puis :"
    warn "  git -C $target remote add origin <url-de-ton-fork>"
  fi

  log "$subdir : remotes finaux :"
  git remote -v | sed 's/^/    /'

  if [[ -n "$checkout_ref" ]]; then
    log "$subdir : checkout $checkout_ref"
    git fetch --all --tags --prune
    if git show-ref --verify --quiet "refs/remotes/origin/$checkout_ref"; then
      git checkout -B "$checkout_ref" "origin/$checkout_ref"
    elif git show-ref --verify --quiet "refs/remotes/upstream/$checkout_ref"; then
      git checkout -B "$checkout_ref" "upstream/$checkout_ref"
    else
      git checkout "$checkout_ref"
    fi
  fi

  popd >/dev/null
}

# ----------------------------------------------------------------------------
# Clones
# ----------------------------------------------------------------------------

log "Racine projet : $PROJECT_ROOT"
log "Cible packages : $PACKAGES_DIR"
echo

clone_or_setup "fabi-cli" "$OPENCODE_UPSTREAM" "$OPENCODE_FORK_REMOTE" "$OPENCODE_REF"
echo
clone_or_setup "swarm-engine"   "$PARALLAX_UPSTREAM" "$PARALLAX_FORK_REMOTE" "$PARALLAX_REF"
echo

# ----------------------------------------------------------------------------
# Récap
# ----------------------------------------------------------------------------
ok "Setup terminé."
echo
echo "Prochaines étapes suggérées :"
echo "  1. Crée tes forks sur GitHub (ex: github.com/Noagiannone03/fabi-cli)"
echo "  2. Ajoute origin :"
echo "       git -C packages/fabi-cli remote add origin <url-fork>"
echo "       git -C packages/swarm-engine   remote add origin <url-fork>"
echo "  3. Lis docs/development.md pour démarrer le dev."
