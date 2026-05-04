#!/usr/bin/env bash
#
# sync-upstream.sh — synchronise les deux sous-repos avec leur upstream.
#
# Mode interactif : pour chaque sous-repo, montre les commits upstream en avance
# et propose un merge. Aucun merge n'est fait sans validation explicite.

set -euo pipefail

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

log()    { printf "%s[sync]%s %s\n" "$C_BLUE" "$C_RESET" "$1"; }
warn()   { printf "%s[sync]%s %s\n" "$C_YELLOW" "$C_RESET" "$1" >&2; }
err()    { printf "%s[sync]%s %s\n" "$C_RED" "$C_RESET" "$1" >&2; }
ok()     { printf "%s[sync]%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_DIR="$PROJECT_ROOT/packages"

# Détermine la branche par défaut d'un repo (main ou master)
default_branch() {
  local repo="$1"
  git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "main"
}

sync_one() {
  local subdir="$1"
  local target="$PACKAGES_DIR/$subdir"

  if [[ ! -d "$target/.git" ]]; then
    warn "$subdir : pas cloné. Lance ./scripts/setup.sh d'abord."
    return 0
  fi

  if ! git -C "$target" remote | grep -qx "upstream"; then
    warn "$subdir : pas de remote 'upstream'. Lance ./scripts/setup.sh d'abord."
    return 0
  fi

  log "── $subdir ─────────────────────────────────────────"
  log "Fetch upstream…"
  git -C "$target" fetch upstream --quiet
  # Met à jour le symbolic-ref local vers la branche par défaut d'upstream
  git -C "$target" remote set-head upstream --auto >/dev/null 2>&1 || true

  local branch upstream_branch upstream_head
  branch="$(default_branch "$target")"
  # Détection robuste de la branche par défaut d'upstream :
  #  1. Symbolic ref local upstream/HEAD (fixé par set-head)
  #  2. Fallback : main, dev, master dans cet ordre
  upstream_head="$(git -C "$target" symbolic-ref --short refs/remotes/upstream/HEAD 2>/dev/null || true)"
  if [[ -n "$upstream_head" ]]; then
    upstream_branch="$upstream_head"
  elif git -C "$target" rev-parse upstream/main >/dev/null 2>&1; then
    upstream_branch="upstream/main"
  elif git -C "$target" rev-parse upstream/dev >/dev/null 2>&1; then
    upstream_branch="upstream/dev"
  elif git -C "$target" rev-parse upstream/master >/dev/null 2>&1; then
    upstream_branch="upstream/master"
  else
    warn "$subdir : branche upstream par défaut introuvable."
    return 0
  fi

  local ahead behind
  ahead="$(git -C "$target"  rev-list --count "$upstream_branch..$branch" 2>/dev/null || echo 0)"
  behind="$(git -C "$target" rev-list --count "$branch..$upstream_branch" 2>/dev/null || echo 0)"

  log "Branche locale : $branch"
  log "Branche upstream : $upstream_branch"
  log "Tu es à $ahead commit(s) en avance, $behind en retard."

  if [[ "$behind" -eq 0 ]]; then
    ok "$subdir : déjà à jour avec upstream."
    return 0
  fi

  echo
  log "Commits upstream en attente :"
  git -C "$target" log --oneline "$branch..$upstream_branch" | head -30 | sed 's/^/    /'
  if [[ "$behind" -gt 30 ]]; then
    log "    … ($((behind - 30)) commits supplémentaires non affichés)"
  fi
  echo

  printf "%s[sync]%s Action ? [m]erge / [c]herry-pick interactif / [s]kip : " "$C_BLUE" "$C_RESET"
  read -r choice
  case "$choice" in
    m|M)
      log "Merge en cours…"
      if git -C "$target" merge "$upstream_branch" --no-edit; then
        ok "$subdir : merge OK."
      else
        warn "$subdir : conflits à résoudre manuellement dans $target."
      fi
      ;;
    c|C)
      log "Mode cherry-pick : copie les SHA depuis la liste ci-dessus,"
      log "puis lance manuellement :"
      echo "    cd $target"
      echo "    git cherry-pick <sha1> <sha2> …"
      ;;
    *)
      log "Skip — pas de modification."
      ;;
  esac
}

log "Sync upstream pour tous les sous-repos."
log "Racine : $PROJECT_ROOT"
echo

sync_one "void-swarm-cli"
echo
sync_one "swarm-engine"
echo

ok "Sync terminé."
echo
echo "Pense à mettre à jour DIVERGENCE.md à la racine après un merge important :"
echo "  - Date de la sync"
echo "  - Commit upstream synced"
echo "  - Modifs / conflits notables"
