#!/usr/bin/env bash
#
# Package ARDM for distribution.
#
# Reads the version from the addon's TOC and produces ARDM-v<version>.zip
# containing a single top-level `ARDM/` folder so it extracts straight into
# Interface/AddOns/.
#
# Usage: bash release.sh
set -euo pipefail

ADDON="ARDM"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/$ADDON"
cd "$ROOT"

if [ ! -d "$SRC" ]; then
    echo "error: expected addon directory at $SRC" >&2
    exit 1
fi

VERSION="$(grep -E '^## Version:' "$SRC/$ADDON.toc" | head -1 | sed -E 's/^## Version:[[:space:]]*//')"
if [ -z "$VERSION" ]; then
    echo "error: could not read '## Version' from $SRC/$ADDON.toc" >&2
    exit 1
fi

ZIP="$ADDON-v$VERSION.zip"
STAGE="$(mktemp -d)"
DEST="$STAGE/$ADDON"
mkdir -p "$DEST"

rsync -a \
    --exclude '.git' \
    --exclude '.github' \
    --exclude '.gitignore' \
    --exclude '.claude' \
    --exclude 'CLAUDE.md' \
    --exclude 'release.sh' \
    --exclude '*.zip' \
    --exclude '.DS_Store' \
    "$SRC/" "$DEST/"

rm -f "$ROOT/$ZIP"
( cd "$STAGE" && zip -r -q "$ROOT/$ZIP" "$ADDON" )
rm -rf "$STAGE"

echo "Created $ZIP (version $VERSION)"
