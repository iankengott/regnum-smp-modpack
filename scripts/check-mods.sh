#!/usr/bin/env bash
# Compare the jars actually present in minecraft/mods against manifest/mods.tsv.
#
# The repo carries no jars, so after a pull the manifest can list files this
# machine does not have (or a different build of one). This reports the drift.
# Exits 0 when the instance matches the manifest, 1 when it does not.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/manifest/mods.tsv"
mods_dir="$repo_root/minecraft/mods"

[[ -f "$manifest" ]] || { echo "no manifest at $manifest" >&2; exit 1; }

drift=0

# Expected: everything in the manifest, keyed by filename -> sha256.
declare -A expected
while IFS=$'\t' read -r file _bytes sha; do
    expected["$file"]="$sha"
done < <(tail -n +2 "$manifest")

for file in "${!expected[@]}"; do
    path="$mods_dir/$file"
    if [[ ! -f "$path" ]]; then
        echo "MISSING  $file"
        drift=1
    elif [[ "$(sha256sum "$path" | cut -d' ' -f1)" != "${expected[$file]}" ]]; then
        echo "CHANGED  $file"
        drift=1
    fi
done

# Anything on disk the manifest does not know about.
while IFS= read -r -d '' path; do
    file="$(basename "$path")"
    if [[ -z "${expected[$file]+set}" ]]; then
        echo "EXTRA    $file"
        drift=1
    fi
done < <(find "$mods_dir" -maxdepth 1 -type f -name '*.jar' -print0)

if (( drift )); then
    echo
    echo "Instance does not match the manifest. Fetch or remove jars as listed above,"
    echo "or run scripts/generate-manifest.sh if this machine is the source of truth."
else
    echo "All ${#expected[@]} mods match the manifest."
fi
exit "$drift"
