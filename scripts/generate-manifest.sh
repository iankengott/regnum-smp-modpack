#!/usr/bin/env bash
# Regenerate manifest/ from the live instance.
#
# The repo does not carry mod jars, resource packs, shader packs, or datapack
# zips — they are third-party artifacts under their own licenses. Instead each
# one is recorded here by filename, byte size, and SHA-256, so a pack can be
# verified or rebuilt from the same files without redistributing them.
#
# Run this after adding, removing, or updating anything in the instance, then
# commit the result.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mc="$repo_root/minecraft"
out="$repo_root/manifest"
effective_mods="$repo_root/scripts/effective-mod-jars.py"
mkdir -p "$out"

# Write one TSV per artifact directory: name, bytes, sha256.
write_manifest() {
    local dir="$1" name="$2" pattern="$3"
    # Separate statement: bash expands all of `local`'s arguments before
    # assigning any of them, so $name is not yet set on the line above.
    local target="$out/$name.tsv"
    printf 'file\tbytes\tsha256\n' >"$target"
    if [[ "$name" != "mods" && ! -d "$mc/$dir" ]]; then
        echo "  $name: no $dir/ directory, wrote header only"
        return
    fi
    # -print0/-d '' so filenames with spaces survive; sort for a stable diff.
    # Pin collation so regeneration is identical when an agent shell uses C
    # while the desktop session uses en_US.UTF-8.
    {
        if [[ "$name" == "mods" ]]; then
            # The resolver already sorts by filename; sorting its absolute paths
            # would group the AutoModpack overlay separately from mods/.
            "$effective_mods" --instance "$repo_root"
        else
            find "$mc/$dir" -maxdepth 1 -type f -name "$pattern" -print0 |
                LC_ALL=en_US.UTF-8 sort -z
        fi
    } |
        while IFS= read -r -d '' f; do
            printf '%s\t%s\t%s\n' \
                "$(basename "$f")" \
                "$(stat -c %s "$f")" \
                "$(sha256sum "$f" | cut -d' ' -f1)"
        done >>"$target"
    echo "  $name: $(($(wc -l <"$target") - 1)) entries"
}

echo "Regenerating manifests from $mc"
write_manifest mods          mods          '*.jar'
write_manifest resourcepacks resourcepacks '*.zip'
write_manifest shaderpacks   shaderpacks   '*.zip'
write_manifest datapacks     datapacks     '*.zip'

# Loader and Minecraft versions, lifted straight out of the Prism pack file.
python3 - "$repo_root/mmc-pack.json" "$out/loader.tsv" <<'PY'
import json, sys

src, dst = sys.argv[1], sys.argv[2]
with open(src) as fh:
    components = json.load(fh)["components"]
with open(dst, "w") as fh:
    fh.write("uid\tname\tversion\n")
    for c in components:
        fh.write("{}\t{}\t{}\n".format(
            c["uid"], c.get("cachedName", ""), c["version"]))
PY
echo "  loader: $(($(wc -l <"$out/loader.tsv") - 1)) components"
echo "Done."
