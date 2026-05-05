#!/usr/bin/env bash
#
# check-divergence.sh — état des lieux : combien on diverge d'upstream.
#
# Read-only, ne modifie rien.

set -euo pipefail

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_DIR="$PROJECT_ROOT/packages"

check_one() {
  local subdir="$1"
  local target="$PACKAGES_DIR/$subdir"

  printf "\n%s── %s ──────────────────────────────────────────%s\n" "$C_BLUE" "$subdir" "$C_RESET"

  if [[ ! -d "$target/.git" ]]; then
    printf "  %sPas cloné. Lance ./scripts/setup.sh%s\n" "$C_YELLOW" "$C_RESET"
    return 0
  fi

  pushd "$target" >/dev/null

  if ! git remote | grep -qx "upstream"; then
    printf "  %sPas de remote 'upstream'.%s\n" "$C_YELLOW" "$C_RESET"
    popd >/dev/null
    return 0
  fi

  git fetch upstream --quiet 2>/dev/null || {
    printf "  %sÉchec fetch upstream (réseau ?)%s\n" "$C_RED" "$C_RESET"
  }
  git remote set-head upstream --auto >/dev/null 2>&1 || true

  local branch upstream_ref upstream_head
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "(detached)")"
  upstream_head="$(git symbolic-ref --short refs/remotes/upstream/HEAD 2>/dev/null || true)"
  if [[ -n "$upstream_head" ]]; then
    upstream_ref="$upstream_head"
  elif git rev-parse upstream/main >/dev/null 2>&1; then
    upstream_ref="upstream/main"
  elif git rev-parse upstream/dev >/dev/null 2>&1; then
    upstream_ref="upstream/dev"
  elif git rev-parse upstream/master >/dev/null 2>&1; then
    upstream_ref="upstream/master"
  else
    printf "  %sBranche upstream par défaut introuvable.%s\n" "$C_YELLOW" "$C_RESET"
    popd >/dev/null
    return 0
  fi

  local ahead behind
  ahead="$(git  rev-list --count "$upstream_ref..$branch" 2>/dev/null || echo 0)"
  behind="$(git rev-list --count "$branch..$upstream_ref" 2>/dev/null || echo 0)"

  # Compte des fichiers modifiés (différence par contenu)
  local changed_files
  changed_files="$(git diff --name-only "$upstream_ref...$branch" 2>/dev/null | wc -l | tr -d ' ')"

  printf "  Branche locale       : %s\n" "$branch"
  printf "  Branche upstream     : %s\n" "$upstream_ref"
  printf "  Commits en avance    : %s%s%s\n" "$C_GREEN" "$ahead"  "$C_RESET"
  printf "  Commits en retard    : %s%s%s\n" "$C_YELLOW" "$behind" "$C_RESET"
  printf "  Fichiers modifiés    : %s\n" "$changed_files"

  # Travail en cours non committé
  local unstaged
  unstaged="$(git status --porcelain | wc -l | tr -d ' ')"
  if [[ "$unstaged" -gt 0 ]]; then
    printf "  %sFichiers non committés : %s%s\n" "$C_YELLOW" "$unstaged" "$C_RESET"
  fi

  popd >/dev/null
}

printf "%s[fabi divergence check]%s racine = %s\n" "$C_BLUE" "$C_RESET" "$PROJECT_ROOT"

check_one "fabi-cli"
check_one "swarm-engine"

echo
echo "Pour synchroniser : ./scripts/sync-upstream.sh"
