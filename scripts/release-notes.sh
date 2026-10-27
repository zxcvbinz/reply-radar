#!/bin/zsh
# Note di una release: installazione, elenco delle modifiche dai commit, checksum.
# Legge VERSION, PREVIOUS (tag precedente, può essere vuoto), ZIP, REPO_URL, HAS_CERT e HAS_NOTARY dall'ambiente.
set -euo pipefail
cd "${0:A:h}/.."

print -r -- "## Install"
print
print -r -- "Download \`$ZIP\`, unzip it and move **Reply Radar** to Applications. Requires macOS 26 or later. Works on Apple Silicon and Intel."
print
if [[ "${HAS_CERT:-}" == true && "${HAS_NOTARY:-}" == true ]]; then
    print -r -- "Signed with Developer ID and notarized by Apple."
else
    print -r -- "This build is **not notarized**. After moving it to Applications, run once:"
    print
    print -r -- '```bash'
    print -r -- 'xattr -dr com.apple.quarantine "/Applications/Reply Radar.app"'
    print -r -- '```'
    print
    print -r -- "or open it and confirm in *System Settings › Privacy & Security › Open Anyway*. You will need to grant Full Disk Access again after each update."
fi
print
print -r -- "## What's changed"
print
REPO_URL=${REPO_URL:-} ./scripts/changelog.sh "${PREVIOUS:-}" HEAD
if [[ -n "${PREVIOUS:-}" && -n "${REPO_URL:-}" ]]; then
    print -r -- "**Full changelog:** $REPO_URL/compare/$PREVIOUS...v$VERSION"
    print
fi
print -r -- "SHA-256: \`$(cut -d' ' -f1 "$ZIP.sha256")\`"
