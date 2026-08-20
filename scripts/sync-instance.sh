#!/usr/bin/env bash
# Pull the live pack into this instance. Run by the regnum-modpack-sync systemd
# user timer, and safe to run by hand.
#
# Deliberately conservative — it refuses rather than clobbers:
#   * skips entirely while Minecraft is running, so jars and configs are never
#     swapped out from under a live game
#   * --ff-only, so a diverged local branch stops the sync instead of merging
#   * skips when tracked files are dirty, so local config edits are never lost
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

# Only java processes are matched, and this script is not one, so pgrep cannot
# match itself here.
if pgrep -f "java.*$repo_root" >/dev/null 2>&1; then
    log "Minecraft is running for this instance — skipping sync."
    exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Tracked files are modified locally — skipping sync so nothing is lost."
    git status --short
    exit 0
fi

before="$(git rev-parse HEAD)"
log "Fetching origin..."
git fetch --quiet origin

if ! git merge --ff-only --quiet "@{u}" 2>/dev/null; then
    log "Cannot fast-forward — local branch has diverged from origin. Resolve by hand."
    exit 1
fi

after="$(git rev-parse HEAD)"
if [[ "$before" == "$after" ]]; then
    log "Already up to date."
    exit 0
fi

log "Updated $(git rev-parse --short "$before") -> $(git rev-parse --short "$after")"
git --no-pager log --oneline "$before..$after"

# A config-only update is ready to play; a manifest change means jars on disk
# no longer match the pack and need fetching before the next launch.
if git diff --name-only "$before" "$after" | grep -q '^manifest/'; then
    log "Mod manifest changed — checking jars on disk:"
    "$repo_root/scripts/check-mods.sh" || true
fi
