#!/usr/bin/env bash
# Install one exact Modrinth version into this live Prism instance.
#
# The version ID is intentionally required instead of a project slug: releases
# must stay pinned even when Modrinth publishes a newer compatible build.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mods_dir="$repo_root/minecraft/mods"
version_id="${1:-}"

if [[ -z "$version_id" || "$version_id" == "-h" || "$version_id" == "--help" ]]; then
    echo "usage: $0 MODRINTH_VERSION_ID" >&2
    exit "$([[ -n "$version_id" ]] && echo 0 || echo 2)"
fi

for command in curl jq sha512sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "missing required command: $command" >&2
        exit 1
    }
done

metadata="$(curl -fsSL "https://api.modrinth.com/v2/version/$version_id")"

jq -e '(.game_versions | index("1.21.1")) != null' <<<"$metadata" >/dev/null || {
    echo "Modrinth version $version_id does not support Minecraft 1.21.1" >&2
    exit 1
}
jq -e '(.loaders | index("neoforge")) != null' <<<"$metadata" >/dev/null || {
    echo "Modrinth version $version_id is not a NeoForge build" >&2
    exit 1
}

filename="$(jq -er '.files[] | select(.primary == true) | .filename' <<<"$metadata")"
url="$(jq -er '.files[] | select(.primary == true) | .url' <<<"$metadata")"
sha512="$(jq -er '.files[] | select(.primary == true) | .hashes.sha512' <<<"$metadata")"
target="$mods_dir/$filename"

if [[ -f "$target" ]] && printf '%s  %s\n' "$sha512" "$target" | sha512sum -c --status; then
    echo "$filename is already installed with the expected hash."
else
    tmp="$(mktemp -t regnum-mod-XXXXXX.jar)"
    trap 'rm -f "$tmp"' EXIT
    curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url"
    printf '%s  %s\n' "$sha512" "$tmp" | sha512sum -c --status || {
        echo "SHA-512 verification failed for $filename" >&2
        exit 1
    }
    mkdir -p "$mods_dir"
    install -m 0644 "$tmp" "$target"
    echo "Installed $filename into the Prism instance."
fi

"$repo_root/scripts/generate-manifest.sh"
