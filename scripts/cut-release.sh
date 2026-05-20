#!/usr/bin/env bash
# Usage: scripts/cut-release.sh
# Commit all changes first: mise exec -- jj commit -m "..."
set -euo pipefail

DATE=$(date +%Y.%m.%d)
HASH=$(mise exec -- jj log -r @- --no-graph -T 'commit_id.shortest(7)')
TAG="v${DATE}-${HASH}"

echo "→ ${TAG}"
mise exec -- jj tag create "${TAG}" @-
mise exec -- jj git push --tag "${TAG}"
