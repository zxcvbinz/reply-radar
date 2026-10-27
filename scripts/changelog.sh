#!/bin/zsh
# Elenco delle modifiche in Markdown, raggruppato per tipo di commit (Conventional Commits).
# Uso: scripts/changelog.sh [da-ref] [a-ref]   (da-ref vuoto = dall'inizio della storia)
set -euo pipefail
FROM=${1:-}
TO=${2:-HEAD}
RANGE=$TO
[[ -n "$FROM" ]] && RANGE="$FROM..$TO"
REPO_URL=${REPO_URL:-}

typeset -A TITLES=(
    feat "New features"
    fix "Bug fixes"
    perf "Performance"
    refactor "Refactoring"
    docs "Documentation"
    other "Other changes"
)
typeset -A ITEMS

while IFS=$'\t' read -r HASH SUBJECT; do
    [[ -z "$HASH" ]] && continue
    TYPE=other
    TEXT=$SUBJECT
    if [[ "$SUBJECT" =~ '^([a-z]+)(\(([^)]*)\))?!?: (.*)$' ]]; then
        case ${match[1]} in
            feat|fix|perf|refactor|docs) TYPE=${match[1]} ;;
        esac
        TEXT=${match[4]}
        [[ -n "${match[3]}" ]] && TEXT="**${match[3]}:** $TEXT"
    fi
    LINK=$HASH
    [[ -n "$REPO_URL" ]] && LINK="[$HASH]($REPO_URL/commit/$HASH)"
    ITEMS[$TYPE]+="- $TEXT ($LINK)"$'\n'
done < <(git log --no-merges --format='%h%x09%s' "$RANGE")

for TYPE in feat fix perf refactor docs other; do
    [[ -z "${ITEMS[$TYPE]:-}" ]] && continue
    print -r -- "### ${TITLES[$TYPE]}"
    print
    print -rn -- "${ITEMS[$TYPE]}"
    print
done
