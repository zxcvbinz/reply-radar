#!/bin/zsh
# Stampa la prossima versione (senza "v") in base ai commit dall'ultimo tag, secondo Conventional Commits:
#   tipo!: o "BREAKING CHANGE" → maggiore (minore finché si è a 0.x), feat → minore, fix/perf → patch.
# Uso: scripts/next-version.sh [auto|patch|minor|major]
# In modalità auto non stampa niente se non c'è nulla da rilasciare (solo docs, ci, chore...).
set -euo pipefail
MODE=${1:-auto}

LAST=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
if [[ -z "$LAST" ]]; then
    # Primo rilascio.
    echo "0.1.0"
    exit 0
fi
RANGE="$LAST..HEAD"
[[ -z "$(git rev-list "$RANGE")" ]] && exit 0

# Uno spazio fra un commit e l'altro: "%B" include il corpo, dove può stare "BREAKING CHANGE".
LOG=$(git log --no-merges --format='%s%n%b%n' "$RANGE")
BUMP=$MODE
if [[ "$MODE" == auto ]]; then
    if print -r -- "$LOG" | grep -qE '^[a-z]+(\([^)]*\))?!:|BREAKING CHANGE'; then BUMP=major
    elif print -r -- "$LOG" | grep -qE '^feat(\([^)]*\))?:'; then BUMP=minor
    elif print -r -- "$LOG" | grep -qE '^(fix|perf)(\([^)]*\))?:'; then BUMP=patch
    else exit 0
    fi
fi

IFS=. read -r MAJOR MINOR PATCH <<< "${LAST#v}"
case $BUMP in
    major) if (( MAJOR == 0 )); then MINOR=$((MINOR + 1)); PATCH=0; else MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0; fi ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "Modalità sconosciuta: $BUMP" >&2; exit 1 ;;
esac
echo "$MAJOR.$MINOR.$PATCH"
