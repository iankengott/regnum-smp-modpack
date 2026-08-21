#!/usr/bin/env bash
# Check the Distant Horizons and Chunky settings for one safe workflow phase.
set -euo pipefail

usage() {
    echo "usage: $0 {idle|chunky|dh-pregen} INSTANCE_OR_SERVER_ROOT" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
mode="$1"
root="$(cd "$2" && pwd)"

case "$mode" in
    idle|chunky|dh-pregen) ;;
    *) usage ;;
esac

if [[ -d "$root/minecraft/config" ]]; then
    game="$root/minecraft"
    effective_mods="$root/scripts/effective-mod-jars.py"
    [[ -x "$effective_mods" ]] || {
        echo "FAIL: missing executable $effective_mods" >&2
        exit 1
    }
    mapfile -d '' jars < <("$effective_mods" --instance "$root")
elif [[ -d "$root/config" && -d "$root/mods" ]]; then
    game="$root"
    shopt -s nullglob
    jars=("$root"/mods/*.jar)
    shopt -u nullglob
else
    echo "FAIL: $root is not a Prism instance or dedicated-server root" >&2
    exit 1
fi

dh_config="$game/config/DistantHorizons.toml"
chunky_config="$game/config/chunky/config.json"
[[ -f "$dh_config" ]] || { echo "FAIL: missing $dh_config" >&2; exit 1; }
[[ -f "$chunky_config" ]] || { echo "FAIL: missing $chunky_config" >&2; exit 1; }

has_jar() {
    local expression="$1" path
    for path in "${jars[@]}"; do
        if [[ "${path##*/}" =~ $expression ]]; then
            return 0
        fi
    done
    return 1
}

toml_value() {
    local key="$1"
    awk -F= -v key="$key" '
        {
            name = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (name == key) {
                value = $2
                sub(/[[:space:]]+#.*/, "", value)
                gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", value)
                print value
                exit
            }
        }
    ' "$dh_config"
}

failures=0
require_equal() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $label = $actual"
    else
        echo "FAIL: $label = ${actual:-<missing>}; expected $expected"
        failures=1
    fi
}

case "$mode" in
    chunky)
        if has_jar '^DistantHorizons-.*\.jar$'; then
            echo "FAIL: Distant Horizons jar must be absent during Chunky"
            failures=1
        else
            echo "PASS: Distant Horizons jar is absent during Chunky"
        fi
        ;;
    idle|dh-pregen)
        if has_jar '^DistantHorizons-.*\.jar$'; then
            echo "PASS: Distant Horizons jar is present"
        else
            echo "FAIL: Distant Horizons jar is absent"
            failures=1
        fi
        ;;
esac
if has_jar '^Chunky-.*\.jar$'; then
    echo "PASS: Chunky jar is present"
else
    echo "FAIL: Chunky jar is absent"
    failures=1
fi

require_equal "distantGeneratorMode" "$(toml_value distantGeneratorMode)" "PRE_EXISTING_ONLY"

case "$mode" in
    idle|dh-pregen)
        require_equal "enableDistantGeneration" "$(toml_value enableDistantGeneration)" "true"
        ;;
    chunky)
        require_equal "enableDistantGeneration" "$(toml_value enableDistantGeneration)" "false"
        ;;
esac

if grep -Eq '"continueOnRestart"[[:space:]]*:[[:space:]]*true' "$chunky_config"; then
    echo "PASS: Chunky continueOnRestart = true"
else
    echo "FAIL: Chunky continueOnRestart must be true"
    failures=1
fi

echo "INFO: DH render radius = $(toml_value lodChunkRenderDistanceRadius) chunks"
echo "INFO: DH client-request generation = $(toml_value enableServerGeneration)"
echo "INFO: pre-generation radius is chosen by the chunky or dh pregen command"

if (( failures )); then
    exit 1
fi
echo "PASS: $mode phase is configured safely"
