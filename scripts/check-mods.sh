#!/usr/bin/env bash
# Compare the jars actually present in minecraft/mods against manifest/mods.tsv
# and reject known packaged-component collisions that prevent NeoForge startup.
#
# The repo carries no jars, so after a pull the manifest can list files this
# machine does not have (or a different build of one). This reports the drift.
# Exits 0 when the instance matches the manifest, 1 when it does not.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/manifest/mods.tsv"
effective_mods="$repo_root/scripts/effective-mod-jars.py"

[[ -f "$manifest" ]] || { echo "no manifest at $manifest" >&2; exit 1; }

drift=0

actual_list="$(mktemp -t regnum-effective-mods-XXXXXX)"
trap 'rm -f "$actual_list"' EXIT
"$effective_mods" --instance "$repo_root" >"$actual_list"

declare -A actual
while IFS= read -r -d '' path; do
    actual["$(basename "$path")"]="$path"
done <"$actual_list"

# Expected: everything in the manifest, keyed by filename -> sha256.
declare -A expected
while IFS=$'\t' read -r file _bytes sha; do
    expected["$file"]="$sha"
done < <(tail -n +2 "$manifest")

for file in "${!expected[@]}"; do
    path="${actual[$file]-}"
    if [[ -z "$path" ]]; then
        echo "MISSING  $file"
        drift=1
    elif [[ "$(sha256sum "$path" | cut -d' ' -f1)" != "${expected[$file]}" ]]; then
        echo "CHANGED  $file"
        drift=1
    fi
done

# Anything on disk the manifest does not know about.
for file in "${!actual[@]}"; do
    if [[ -z "${expected[$file]+set}" ]]; then
        echo "EXTRA    $file"
        drift=1
    fi
done

# The primary LambDynamicLights release already embeds its API and runtime.
# Installing those internal component jars beside it creates duplicate Java
# modules and aborts NeoForge before Minecraft can start.
lamb_full=()
lamb_components=()
for file in "${!actual[@]}"; do
    case "$file" in
        lambdynamiclights-[0-9]*.jar) lamb_full+=("$file") ;;
        lambdynamiclights-api-*.jar|lambdynamiclights-runtime-*.jar)
            lamb_components+=("$file")
            ;;
    esac
done
if (( ${#lamb_full[@]} > 0 && ${#lamb_components[@]} > 0 )); then
    for file in "${lamb_components[@]}"; do
        echo "CONFLICT $file is already embedded in ${lamb_full[0]}"
    done
    drift=1
fi

if (( drift )); then
    echo
    echo "Instance does not match the manifest. Fetch or remove jars as listed above,"
    echo "or run scripts/generate-manifest.sh if this machine is the source of truth."
else
    echo "All ${#expected[@]} mods match the manifest."
fi
exit "$drift"
