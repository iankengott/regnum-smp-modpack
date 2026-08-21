#!/usr/bin/env bash
# Build the reproducible Regnum patch for Treasure Level Mobs 1.1.4.
#
# The input must be the unmodified jar with the pinned SHA-256. The output is
# separate so this command cannot overwrite a live or running Minecraft jar.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input="${1:-}"
output="${2:-}"

if [[ -z "$input" || -z "$output" ]]; then
    echo "usage: $0 INPUT_JAR OUTPUT_JAR" >&2
    exit 2
fi

expected_sha="c01d8f946367d4a925cc62f246199b052dd5a39d6609f70a5978cefeabcaf0f3"
actual_sha="$(sha256sum "$input" | cut -d' ' -f1)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "ERROR: refusing unexpected Treasure Level Mobs input SHA-256: $actual_sha" >&2
    exit 1
fi

asm_root="${PRISM_LIBRARIES:-$HOME/.local/share/PrismLauncher/libraries}/org/ow2/asm"
asm="$(find "$asm_root/asm" -maxdepth 2 -name 'asm-*.jar' -type f | sort -V | tail -n 1)"
asm_tree="$(find "$asm_root/asm-tree" -maxdepth 2 -name 'asm-tree-*.jar' -type f | sort -V | tail -n 1)"
[[ -n "$asm" && -n "$asm_tree" ]] || {
    echo "ERROR: ASM 9.x libraries were not found under $asm_root" >&2
    exit 1
}

source_dir="$repo_root/scripts/treasurelevelmobs"
build_dir="$(mktemp -d -t regnum-tlmobs-patch-XXXXXX)"
cleanup() {
    find "$build_dir" -type f -delete 2>/dev/null || true
    find "$build_dir" -type d -depth -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

javac -encoding UTF-8 -cp "$asm:$asm_tree" -d "$build_dir" \
    "$source_dir/RegnumLevelCap.java" \
    "$source_dir/PatchTreasureLevelMobs.java"

java -cp "$build_dir:$asm:$asm_tree" \
    treasurelevelmobs.patch.PatchTreasureLevelMobs \
    "$input" "$output" "$build_dir/treasurelevelmobs/patch/RegnumLevelCap.class"

patched_sha="$(sha256sum "$output" | cut -d' ' -f1)"
echo "Patched Treasure Level Mobs: $output"
echo "SHA-256: $patched_sha"
