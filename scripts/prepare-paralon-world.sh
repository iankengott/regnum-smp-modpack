#!/usr/bin/env bash
# Safely replace the Hermes Regnum world with Paralon, then run Chunky and
# Distant Horizons in separate, resumable phases.
set -Eeuo pipefail

PRODUCTION_HOST="ian-kengott-GF63-Thin-11SC"
PRODUCTION_USER="ian-kengott"
SESSION="${REGNUM_TMUX_SESSION:-regnum}"
PORT="${REGNUM_PORT:-25566}"
MC_ROOT="${REGNUM_MC_ROOT:-$HOME/regnum/new-server/mc}"
PREP_ROOT="${REGNUM_PREP_ROOT:-$HOME/regnum/paralon-prep}"
INCOMING_ROOT="${REGNUM_INCOMING_ROOT:-$HOME/regnum/incoming}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_CHECK="$SCRIPT_DIR/check-dh-chunky.sh"
STATE_DIR="$PREP_ROOT/state"
LOCK_FILE="$PREP_ROOT/controller.lock"
TESTING="${REGNUM_PARALON_TESTING:-0}"

usage() {
    cat >&2 <<'EOF'
usage:
  prepare-paralon-world.sh status
  prepare-paralon-world.sh inspect WORLD_DIR
  prepare-paralon-world.sh install WORLD_DIR EDITION PLAYER_MODE CENTER_X CENTER_Z RADIUS_CHUNKS
  prepare-paralon-world.sh chunky-start
  prepare-paralon-world.sh chunky-wait
  prepare-paralon-world.sh dh-start
  prepare-paralon-world.sh dh-wait
  prepare-paralon-world.sh finalize
  prepare-paralon-world.sh rollback
  prepare-paralon-world.sh self-test

PLAYER_MODE is reset or preserve. Production WORLD_DIR must be beneath
~/regnum/incoming. The install and rollback actions require typed confirmation.
EOF
    exit 2
}

say() { printf '\n=== %s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; return 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

validate_identity() {
    if [[ "$TESTING" == 1 ]]; then
        return
    fi
    [[ "$(hostname)" == "$PRODUCTION_HOST" ]] ||
        die "run this on Hermes ($PRODUCTION_HOST), not $(hostname)"
    [[ "$(whoami)" == "$PRODUCTION_USER" ]] ||
        die "run this as $PRODUCTION_USER, not $(whoami)"
    [[ "$MC_ROOT" == "$HOME/regnum/new-server/mc" ]] ||
        die "production server root must be $HOME/regnum/new-server/mc"
}

init_mutation_state() {
    mkdir -p "$STATE_DIR"
    require_command flock
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "another Paralon controller process holds $LOCK_FILE"
}

state_get() {
    local key="$1" default_value="${2:-}"
    if [[ -f "$STATE_DIR/$key" ]]; then
        cat "$STATE_DIR/$key"
    else
        printf '%s' "$default_value"
    fi
}

state_set() {
    local key="$1" value="$2" tmp
    [[ "$key" =~ ^[a-z0-9_]+$ ]] || die "unsafe state key: $key"
    [[ "$value" != *$'\n'* ]] || die "state value for $key contains a newline"
    tmp=$(mktemp "$STATE_DIR/.${key}.XXXXXX")
    printf '%s\n' "$value" > "$tmp"
    mv -f "$tmp" "$STATE_DIR/$key"
}

phase() { state_get phase uninitialized; }

port_line() {
    ss -ltnp 2>/dev/null | awk -v port=":$PORT" '$4 ~ port "$" { print; exit }'
}

port_pid() {
    port_line | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1
}

server_session_exists() {
    tmux has-session -t "=$SESSION" 2>/dev/null
}

server_is_live() {
    local pid cwd
    server_session_exists || return 1
    pid=$(port_pid)
    [[ -n "$pid" ]] || return 1
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
    [[ "$cwd" == "$MC_ROOT" ]]
}

require_server_live() {
    server_is_live || die "the exact $SESSION server is not healthy on port $PORT from $MC_ROOT"
}

wait_for_log() {
    local start_line="$1" expression="$2" timeout="${3:-20}" elapsed=0 output
    while (( elapsed < timeout )); do
        output=$(tail -n "+$((start_line + 1))" "$MC_ROOT/logs/latest.log" 2>/dev/null || true)
        if grep -Eq "$expression" <<<"$output"; then
            printf '%s\n' "$output"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    printf '%s\n' "$output"
    return 1
}

send_and_wait() {
    local command="$1" expression="$2" timeout="${3:-20}" start_line
    require_server_live
    start_line=$(wc -l < "$MC_ROOT/logs/latest.log")
    tmux send-keys -t "=$SESSION:" "$command" Enter
    wait_for_log "$start_line" "$expression" "$timeout"
}

query_tasks() {
    local start_line output elapsed=0
    require_server_live
    start_line=$(wc -l < "$MC_ROOT/logs/latest.log")
    tmux send-keys -t "=$SESSION:" "chunky progress" Enter
    tmux send-keys -t "=$SESSION:" "dh pregen status" Enter
    while (( elapsed < 20 )); do
        output=$(tail -n "+$((start_line + 1))" "$MC_ROOT/logs/latest.log" 2>/dev/null || true)
        if grep -Eq '\[Chunky\].*(No tasks running|Task running)' <<<"$output" &&
           grep -Eq '(Pregen is not running|Generated radius:)' <<<"$output"; then
            TASK_OUTPUT="$output"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    TASK_OUTPUT="$output"
    return 1
}

require_tasks_idle() {
    query_tasks || { printf '%s\n' "$TASK_OUTPUT"; die "could not query both pregeneration tasks"; }
    printf '%s\n' "$TASK_OUTPUT"
    grep -q '\[Chunky\].*No tasks running' <<<"$TASK_OUTPUT" || die "Chunky is not idle"
    grep -q 'Pregen is not running' <<<"$TASK_OUTPUT" || die "Distant Horizons is not idle"
}

stop_server() {
    local elapsed=0
    if ! server_is_live; then
        if [[ -n "$(port_line)" ]]; then
            die "port $PORT is held by a foreign process: $(port_line)"
            return 1
        fi
        return 0
    fi
    say "Stopping Regnum cleanly"
    tmux send-keys -t "=$SESSION:" "save-all flush" Enter
    sleep 5
    tmux send-keys -t "=$SESSION:" "stop" Enter
    while [[ -n "$(port_line)" && $elapsed -lt 120 ]]; do
        sleep 2
        elapsed=$((elapsed + 2))
    done
    if [[ -n "$(port_line)" ]]; then
        die "Regnum did not release port $PORT within 120 seconds"
        return 1
    fi
    tmux kill-session -t "=$SESSION" 2>/dev/null || true
}

start_server() {
    local elapsed=0 started_at
    if server_is_live; then
        return
    fi
    if [[ -n "$(port_line)" ]]; then
        die "port $PORT is held by a foreign process: $(port_line)"
        return 1
    fi
    if [[ ! -x "$MC_ROOT/start.sh" ]]; then
        die "missing executable $MC_ROOT/start.sh"
        return 1
    fi
    if server_session_exists; then
        die "tmux session $SESSION exists without the expected server listener"
        return 1
    fi
    started_at=$(date +%s)
    say "Starting Regnum"
    if ! tmux new-session -d -s "$SESSION" "cd '$MC_ROOT' && exec ./start.sh"; then
        die "could not create tmux session $SESSION"
        return 1
    fi
    while (( elapsed < 600 )); do
        if [[ -f "$MC_ROOT/logs/latest.log" ]] &&
           [[ "$(stat -c %Y "$MC_ROOT/logs/latest.log")" -ge "$started_at" ]] &&
           grep -q 'Done (' "$MC_ROOT/logs/latest.log" && server_is_live; then
            grep 'Done (' "$MC_ROOT/logs/latest.log" | tail -n 1
            return
        fi
        if ! server_session_exists; then
            die "Regnum tmux session exited during startup"
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    die "Regnum did not report Done and listen on $PORT within 600 seconds"
    return 1
}

set_toml_value() {
    local file="$1" key="$2" value="$3"
    python3 - "$file" "$key" "$value" <<'PY'
import os, re, sys, tempfile
path, key, value = sys.argv[1:]
text = open(path, encoding="utf-8").read()
pattern = re.compile(rf"^(\s*){re.escape(key)}\s*=.*$", re.MULTILINE)
matches = list(pattern.finditer(text))
if len(matches) != 1:
    raise SystemExit(f"expected one {key} assignment in {path}, found {len(matches)}")
text = pattern.sub(lambda m: f"{m.group(1)}{key} = {value}", text, count=1)
fd, tmp = tempfile.mkstemp(prefix=".paralon-", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    stream.write(text)
os.replace(tmp, path)
PY
}

set_json_bool() {
    local file="$1" key="$2" value="$3"
    python3 - "$file" "$key" "$value" <<'PY'
import json, os, sys, tempfile
path, key, raw = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    data = json.load(stream)
if key not in data:
    raise SystemExit(f"missing {key} in {path}")
data[key] = raw.lower() == "true"
fd, tmp = tempfile.mkstemp(prefix=".paralon-", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2)
    stream.write("\n")
os.replace(tmp, path)
PY
}

backup_pregen_configs() {
    local backup="$STATE_DIR/config-before-pregen"
    if [[ -d "$backup" ]]; then
        return
    fi
    mkdir -p "$backup/chunky"
    cp -a "$MC_ROOT/config/DistantHorizons.toml" "$backup/DistantHorizons.toml"
    cp -a "$MC_ROOT/config/chunky/config.json" "$backup/chunky/config.json"
}

configure_phase() {
    local target="$1"
    case "$target" in
        chunky)
            set_toml_value "$MC_ROOT/config/DistantHorizons.toml" distantGeneratorMode '"PRE_EXISTING_ONLY"'
            set_toml_value "$MC_ROOT/config/DistantHorizons.toml" enableDistantGeneration false
            set_json_bool "$MC_ROOT/config/chunky/config.json" forceLoadExistingChunks true
            ;;
        dh-pregen|idle)
            set_toml_value "$MC_ROOT/config/DistantHorizons.toml" distantGeneratorMode '"PRE_EXISTING_ONLY"'
            set_toml_value "$MC_ROOT/config/DistantHorizons.toml" enableDistantGeneration true
            set_json_bool "$MC_ROOT/config/chunky/config.json" forceLoadExistingChunks false
            ;;
        *) die "unknown config phase: $target" ;;
    esac
}

source_metrics() {
    local requested="$1" source
    source=$(realpath "$requested" 2>/dev/null) || die "cannot resolve source world: $requested"
    [[ -d "$source" ]] || die "source world is not a directory: $source"
    [[ -f "$source/level.dat" ]] || die "source world has no level.dat: $source"
    [[ -d "$source/region" ]] || die "source world has no overworld region directory: $source"
    [[ "$source" != "$MC_ROOT/world" && "$source" != "$MC_ROOT/world/"* ]] ||
        die "source world cannot be the live Regnum world"
    if [[ "$TESTING" != 1 ]]; then
        [[ "$source" == "$INCOMING_ROOT/"* ]] ||
            die "source world must be beneath $INCOMING_ROOT"
    fi

    local metrics
    metrics=$(python3 - "$source" <<'PY'
import hashlib, math, pathlib, re, sys
root = pathlib.Path(sys.argv[1]).resolve()
pattern = re.compile(r"r\.(-?\d+)\.(-?\d+)\.mca")
region_files = []
chunks = []
for path in root.joinpath("region").glob("r.*.*.mca"):
    match = pattern.fullmatch(path.name)
    if match:
        region_files.append((path, int(match.group(1)), int(match.group(2))))
if not region_files:
    raise SystemExit("no valid overworld region files found")
for path, region_x, region_z in region_files:
    header = path.read_bytes()[:4096]
    if len(header) != 4096:
        raise SystemExit(f"truncated region header: {path}")
    for index in range(1024):
        entry = header[index * 4:(index + 1) * 4]
        if int.from_bytes(entry[:3], "big") and entry[3]:
            chunks.append((region_x * 32 + index % 32, region_z * 32 + index // 32))
if not chunks:
    raise SystemExit("overworld region files contain no allocated chunks")
min_chunk_x = min(x for x, _ in chunks)
max_chunk_x = max(x for x, _ in chunks)
min_chunk_z = min(z for _, z in chunks)
max_chunk_z = max(z for _, z in chunks)
center_x = ((min_chunk_x + max_chunk_x + 1) * 16) // 2
center_z = ((min_chunk_z + max_chunk_z + 1) * 16) // 2
radius = 0.0
for chunk_x, chunk_z in chunks:
    block_x = chunk_x * 16 + 8
    block_z = chunk_z * 16 + 8
    radius = max(radius, math.hypot(block_x - center_x, block_z - center_z) / 16)
radius_chunks = math.ceil(radius) + 1
level_hash = hashlib.sha256(root.joinpath("level.dat").read_bytes()).hexdigest()
source_kib = sum(p.stat().st_size for p in root.rglob("*") if p.is_file()) // 1024
values = {
    "SOURCE": root,
    "LEVEL_SHA256": level_hash,
    "REGION_COUNT": len(region_files),
    "ALLOCATED_CHUNKS": len(chunks),
    "MIN_BLOCK_X": min_chunk_x * 16,
    "MAX_BLOCK_X": (max_chunk_x + 1) * 16 - 1,
    "MIN_BLOCK_Z": min_chunk_z * 16,
    "MAX_BLOCK_Z": (max_chunk_z + 1) * 16 - 1,
    "RECOMMENDED_CENTER_X": center_x,
    "RECOMMENDED_CENTER_Z": center_z,
    "MIN_RADIUS_CHUNKS": radius_chunks,
    "MIN_RADIUS_BLOCKS": radius_chunks * 16,
    "APPROX_CIRCLE_CHUNKS": math.ceil(math.pi * radius_chunks * radius_chunks),
    "SOURCE_KIB": source_kib,
}
for key, value in values.items():
    print(f"{key}={value}")
PY
) || die "could not inspect source world: $source"

    while IFS='=' read -r key value; do
        case "$key" in
            SOURCE) METRIC_SOURCE="$value" ;;
            LEVEL_SHA256) METRIC_LEVEL_SHA256="$value" ;;
            REGION_COUNT) METRIC_REGION_COUNT="$value" ;;
            ALLOCATED_CHUNKS) METRIC_ALLOCATED_CHUNKS="$value" ;;
            MIN_BLOCK_X) METRIC_MIN_BLOCK_X="$value" ;;
            MAX_BLOCK_X) METRIC_MAX_BLOCK_X="$value" ;;
            MIN_BLOCK_Z) METRIC_MIN_BLOCK_Z="$value" ;;
            MAX_BLOCK_Z) METRIC_MAX_BLOCK_Z="$value" ;;
            RECOMMENDED_CENTER_X) METRIC_CENTER_X="$value" ;;
            RECOMMENDED_CENTER_Z) METRIC_CENTER_Z="$value" ;;
            MIN_RADIUS_CHUNKS) METRIC_RADIUS_CHUNKS="$value" ;;
            MIN_RADIUS_BLOCKS) METRIC_RADIUS_BLOCKS="$value" ;;
            APPROX_CIRCLE_CHUNKS) METRIC_APPROX_CHUNKS="$value" ;;
            SOURCE_KIB) METRIC_SOURCE_KIB="$value" ;;
        esac
    done <<<"$metrics"
    [[ -n "${METRIC_SOURCE:-}" && -n "${METRIC_RADIUS_CHUNKS:-}" ]] ||
        die "source inspection returned incomplete metrics"
}

print_metrics() {
    cat <<EOF
SOURCE=$METRIC_SOURCE
LEVEL_SHA256=$METRIC_LEVEL_SHA256
REGION_COUNT=$METRIC_REGION_COUNT
ALLOCATED_CHUNKS=$METRIC_ALLOCATED_CHUNKS
MIN_BLOCK_X=$METRIC_MIN_BLOCK_X
MAX_BLOCK_X=$METRIC_MAX_BLOCK_X
MIN_BLOCK_Z=$METRIC_MIN_BLOCK_Z
MAX_BLOCK_Z=$METRIC_MAX_BLOCK_Z
RECOMMENDED_CENTER_X=$METRIC_CENTER_X
RECOMMENDED_CENTER_Z=$METRIC_CENTER_Z
MIN_RADIUS_CHUNKS=$METRIC_RADIUS_CHUNKS
MIN_RADIUS_BLOCKS=$METRIC_RADIUS_BLOCKS
APPROX_CIRCLE_CHUNKS=$METRIC_APPROX_CHUNKS
SOURCE_KIB=$METRIC_SOURCE_KIB
EOF
}

source_is_in_use() {
    local source="$1" link
    for link in /proc/[0-9]*/cwd; do
        [[ -e "$link" ]] || continue
        link=$(readlink -f "$link" 2>/dev/null || true)
        [[ "$link" == "$source" || "$link" == "$source/"* ]] && return 0
    done
    return 1
}

create_world_backup() {
    local stamp="$1" backup_dir="$HOME/backups-worlds" output
    mkdir -p "$backup_dir"
    if command -v zstd >/dev/null 2>&1; then
        output="$backup_dir/regnum_before_paralon_${stamp}.tar.zst"
        tar -C "$MC_ROOT" -I 'zstd -3 -T0' -cf "$output" world
    else
        output="$backup_dir/regnum_before_paralon_${stamp}.tar.gz"
        tar -C "$MC_ROOT" -czf "$output" world
    fi
    verify_world_backup "$output"
    state_set backup_archive "$output"
    printf '%s\n' "$output"
}

verify_world_backup() {
    local archive="$1"
    if [[ "$archive" == *.tar.zst ]]; then
        tar -I zstd -tf "$archive"
    elif [[ "$archive" == *.tar.gz ]]; then
        tar -tzf "$archive"
    else
        die "unsupported world backup format: $archive"
        return 1
    fi | awk '$0 == "world/level.dat" { found=1 } END { exit(found ? 0 : 1) }' || {
        die "world backup is unreadable or missing world/level.dat: $archive"
        return 1
    }
}

preserve_world_owned_data() {
    local old_world="$1" staged_world="$2" player_mode="$3" quarantine="$4" item
    mkdir -p "$quarantine"
    if [[ -d "$staged_world/serverconfig" ]]; then
        mv "$staged_world/serverconfig" "$quarantine/imported-serverconfig"
    fi
    [[ ! -d "$old_world/serverconfig" ]] || cp -a "$old_world/serverconfig" "$staged_world/serverconfig"

    for item in playerdata advancements stats; do
        if [[ -e "$staged_world/$item" ]]; then
            mv "$staged_world/$item" "$quarantine/imported-$item"
        fi
        if [[ "$player_mode" == preserve && -e "$old_world/$item" ]]; then
            cp -a "$old_world/$item" "$staged_world/$item"
        fi
    done
    if [[ -e "$staged_world/session.lock" ]]; then
        mv "$staged_world/session.lock" "$quarantine/imported-session.lock"
    fi
}

recover_install_failure() {
    local line="$1" rollback failed
    trap - ERR
    set +e
    printf '\nFAIL: Paralon installation failed at line %s; restoring the prior world.\n' "$line" >&2
    rollback=$(state_get rollback_world)
    if [[ -n "$rollback" && -d "$rollback" ]]; then
        if ! stop_server; then
            printf 'FAIL: could not stop Regnum during installation recovery.\n' >&2
            exit 1
        fi
        if [[ -d "$MC_ROOT/world" ]]; then
            failed="$PREP_ROOT/failed-paralon-$(date +%Y%m%d-%H%M%S)"
            if ! mv "$MC_ROOT/world" "$failed" || ! state_set failed_world "$failed"; then
                printf 'FAIL: could not retain the failed Paralon world at %s.\n' "$failed" >&2
                exit 1
            fi
        fi
        if ! mv "$rollback" "$MC_ROOT/world"; then
            printf 'FAIL: could not restore rollback world %s.\n' "$rollback" >&2
            exit 1
        fi
        state_set world_swapped false || exit 1
        state_set phase install-rolled-back || exit 1
    fi
    if ! server_is_live; then
        if ! start_server; then
            printf 'FAIL: prior world is in place but Regnum did not restart.\n' >&2
            exit 1
        fi
    fi
    exit 1
}

apply_world_border() {
    local center_x="$1" center_z="$2" radius_chunks="$3"
    send_and_wait "worldborder center $center_x $center_z" 'world border.*(center| to )' 20 >/dev/null
    send_and_wait "worldborder set $((radius_chunks * 32))" 'world border.*blocks wide|world border.*size' 20 >/dev/null
    send_and_wait "worldborder get" 'world border is currently' 20
}

install_world() {
    local source="$1" edition="$2" player_mode="$3" center_x="$4" center_z="$5" radius_chunks="$6"
    local current_phase stamp staging rollback quarantine current_kib free_kib required_kib staged_hash
    local live_hash swapped_marker imported_quarantine backup_archive
    [[ "$edition" != *$'\n'* && -n "$edition" ]] || die "edition must be a non-empty single line"
    [[ "$player_mode" == reset || "$player_mode" == preserve ]] || die "PLAYER_MODE must be reset or preserve"
    [[ "$center_x" =~ ^-?[0-9]+$ && "$center_z" =~ ^-?[0-9]+$ && "$radius_chunks" =~ ^[0-9]+$ ]] ||
        die "center and radius must be integers"

    current_phase=$(phase)
    case "$current_phase" in
        world-installed|chunky-running|chunky-complete|dh-running|dh-complete|complete)
            say "Paralon is already installed; phase is $current_phase"
            return
            ;;
        uninitialized|installing|install-rolled-back|rolled-back) ;;
        *) die "cannot install from phase $current_phase" ;;
    esac

    source_metrics "$source"
    (( radius_chunks >= METRIC_RADIUS_CHUNKS )) ||
        die "radius $radius_chunks does not cover all source regions; minimum is $METRIC_RADIUS_CHUNKS"

    if [[ "$current_phase" == installing && -f "$MC_ROOT/world/level.dat" ]]; then
        live_hash=$(sha256sum "$MC_ROOT/world/level.dat" | awk '{print $1}')
        swapped_marker=$(state_get world_swapped false)
        imported_quarantine=$(state_get imported_data_quarantine)
        rollback=$(state_get rollback_world)
        backup_archive=$(state_get backup_archive)
        if [[ "$swapped_marker" == true ||
              ( -n "$imported_quarantine" && "$live_hash" == "$METRIC_LEVEL_SHA256" ) ]]; then
            [[ -n "$rollback" && -d "$rollback" ]] ||
                die "cannot resume installed Paralon: rollback world is missing"
            [[ -n "$backup_archive" && -f "$backup_archive" ]] ||
                die "cannot resume installed Paralon: verified backup is missing"
            verify_world_backup "$backup_archive"
            state_set world_swapped true
            trap 'recover_install_failure $LINENO' ERR
            say "Resuming the installed Paralon world after an interrupted restart"
            start_server
            apply_world_border "$center_x" "$center_z" "$radius_chunks"
            state_set phase world-installed
            trap - ERR
            say "Paralon installed. Chunky has not started."
            return
        fi
    fi

    source_is_in_use "$METRIC_SOURCE" && die "a process is using the source world; stop it before copying"
    require_server_live
    require_tasks_idle
    "$PHASE_CHECK" idle "$MC_ROOT"

    current_kib=$(du -sk "$MC_ROOT/world" | awk '{print $1}')
    free_kib=$(df -Pk "$PREP_ROOT" | awk 'NR==2 {print $4}')
    required_kib=$((METRIC_SOURCE_KIB + current_kib + 10 * 1024 * 1024))
    (( free_kib >= required_kib )) ||
        die "insufficient disk: need source copy + current-world backup + 10 GiB headroom"

    if [[ "${PARALON_CONFIRM:-}" != "REPLACE CURRENT REGNUM WORLD" ]]; then
        printf 'Type REPLACE CURRENT REGNUM WORLD to continue: '
        read -r PARALON_CONFIRM
    fi
    [[ "$PARALON_CONFIRM" == "REPLACE CURRENT REGNUM WORLD" ]] || die "world replacement not confirmed"

    stamp=$(date +%Y%m%d-%H%M%S)
    staging="$PREP_ROOT/staging-world"
    rollback="$PREP_ROOT/rollback-world-$stamp"
    quarantine="$PREP_ROOT/imported-world-data-$stamp"
    mkdir -p "$PREP_ROOT"
    state_set phase installing
    state_set edition "$edition"
    state_set source "$METRIC_SOURCE"
    state_set source_level_sha256 "$METRIC_LEVEL_SHA256"
    state_set center_x "$center_x"
    state_set center_z "$center_z"
    state_set radius_chunks "$radius_chunks"
    state_set radius_blocks "$((radius_chunks * 16))"
    state_set player_mode "$player_mode"
    state_set rollback_world "$rollback"
    state_set installed_at "$stamp"

    trap 'recover_install_failure $LINENO' ERR
    if [[ -d "$staging" ]]; then
        staged_hash=$(sha256sum "$staging/level.dat" 2>/dev/null | awk '{print $1}')
        if [[ "$staged_hash" != "$METRIC_LEVEL_SHA256" ]]; then
            mv "$staging" "$PREP_ROOT/abandoned-staging-$stamp"
        fi
    fi
    if [[ ! -d "$staging" ]]; then
        say "Copying the authorized Paralon world into staging"
        mkdir -p "$staging"
        cp -a --reflink=auto "$METRIC_SOURCE/." "$staging/"
    fi
    [[ "$(sha256sum "$staging/level.dat" | awk '{print $1}')" == "$METRIC_LEVEL_SHA256" ]] ||
        die "staged level.dat does not match the inspected source"

    stop_server
    say "Creating the pre-Paralon world backup"
    create_world_backup "$stamp"

    [[ ! -e "$rollback" ]] || die "rollback target already exists: $rollback"
    mv "$MC_ROOT/world" "$rollback"
    preserve_world_owned_data "$rollback" "$staging" "$player_mode" "$quarantine"
    mv "$staging" "$MC_ROOT/world"
    state_set imported_data_quarantine "$quarantine"
    state_set world_swapped true
    start_server

    apply_world_border "$center_x" "$center_z" "$radius_chunks"
    state_set phase world-installed
    trap - ERR
    say "Paralon installed. Chunky has not started."
}

logs_since_contain() {
    local epoch="$1" expression="$2" file modified
    shopt -s nullglob
    for file in "$MC_ROOT"/logs/*.log "$MC_ROOT"/logs/*.log.gz; do
        modified=$(stat -c %Y "$file" 2>/dev/null || echo 0)
        (( modified >= epoch )) || continue
        if [[ "$file" == *.gz ]]; then
            gzip -cd "$file" 2>/dev/null | grep -Eq "$expression" && return 0
        else
            grep -Eq "$expression" "$file" && return 0
        fi
    done
    shopt -u nullglob
    return 1
}

recover_chunky_start_failure() {
    local line="$1"
    trap - ERR
    set +e
    printf '\nFAIL: Chunky setup failed at line %s; restoring the pre-pregeneration configs.\n' "$line" >&2
    stop_server
    if [[ -d "$STATE_DIR/config-before-pregen" ]]; then
        cp -a "$STATE_DIR/config-before-pregen/DistantHorizons.toml" "$MC_ROOT/config/DistantHorizons.toml"
        cp -a "$STATE_DIR/config-before-pregen/chunky/config.json" "$MC_ROOT/config/chunky/config.json"
    fi
    start_server
    state_set phase world-installed
    exit 1
}

recover_dh_start_failure() {
    local line="$1"
    trap - ERR
    set +e
    printf '\nFAIL: DH setup failed at line %s; restoring the safe idle configs.\n' "$line" >&2
    stop_server
    configure_phase idle
    start_server
    state_set phase chunky-complete
    exit 1
}

start_chunky() {
    local current_phase center_x center_z radius_blocks started_at start_line output
    current_phase=$(phase)
    case "$current_phase" in
        chunky-running|chunky-complete|dh-running|dh-complete|complete)
            say "Chunky phase already started or completed; current phase is $current_phase"
            return
            ;;
        world-installed) ;;
        *) die "Chunky can start only after world installation; phase is $current_phase" ;;
    esac
    require_tasks_idle
    backup_pregen_configs
    trap 'recover_chunky_start_failure $LINENO' ERR
    stop_server
    configure_phase chunky
    start_server
    "$PHASE_CHECK" chunky "$MC_ROOT"
    require_tasks_idle

    center_x=$(state_get center_x)
    center_z=$(state_get center_z)
    radius_blocks=$(state_get radius_blocks)
    started_at=$(date +%s)
    start_line=$(wc -l < "$MC_ROOT/logs/latest.log")
    tmux send-keys -t "=$SESSION:" "chunky world minecraft:overworld" Enter
    tmux send-keys -t "=$SESSION:" "chunky shape circle" Enter
    tmux send-keys -t "=$SESSION:" "chunky center $center_x $center_z" Enter
    tmux send-keys -t "=$SESSION:" "chunky radius $radius_blocks" Enter
    tmux send-keys -t "=$SESSION:" "chunky start" Enter
    output=$(wait_for_log "$start_line" '\[Chunky\].*Task started' 30) || {
        printf '%s\n' "$output"
        die "Chunky did not report a started task"
    }
    printf '%s\n' "$output"
    state_set chunky_started_epoch "$started_at"
    state_set phase chunky-running
    trap - ERR
}

wait_chunky() {
    local current_phase started_at
    current_phase=$(phase)
    case "$current_phase" in
        chunky-complete|dh-running|dh-complete|complete)
            say "Chunky already completed; current phase is $current_phase"
            return
            ;;
        chunky-running) ;;
        *) die "Chunky wait requires phase chunky-running; phase is $current_phase" ;;
    esac
    started_at=$(state_get chunky_started_epoch)
    while true; do
        server_is_live || start_server
        query_tasks || { printf '%s\n' "$TASK_OUTPUT"; die "could not query Chunky progress"; }
        printf '%s\n' "$TASK_OUTPUT"
        if logs_since_contain "$started_at" '\[Chunky\].*Task cancelled'; then
            die "Chunky was cancelled; refusing to advance to Distant Horizons"
        fi
        if logs_since_contain "$started_at" '\[Chunky\].*Task finished for minecraft:overworld'; then
            state_set chunky_completed_epoch "$(date +%s)"
            state_set phase chunky-complete
            say "Chunky completed"
            return
        fi
        if grep -q '\[Chunky\].*No tasks running' <<<"$TASK_OUTPUT"; then
            die "Chunky is idle but no completion marker exists; refusing to assume success"
        fi
        sleep 30
    done
}

start_dh() {
    local current_phase center_x center_z radius_chunks started_at output
    current_phase=$(phase)
    case "$current_phase" in
        dh-running|dh-complete|complete)
            say "DH phase already started or completed; current phase is $current_phase"
            return
            ;;
        chunky-complete) ;;
        *) die "DH can start only after verified Chunky completion; phase is $current_phase" ;;
    esac
    require_tasks_idle
    trap 'recover_dh_start_failure $LINENO' ERR
    stop_server
    configure_phase dh-pregen
    start_server
    "$PHASE_CHECK" dh-pregen "$MC_ROOT"
    require_tasks_idle
    center_x=$(state_get center_x)
    center_z=$(state_get center_z)
    radius_chunks=$(state_get radius_chunks)
    started_at=$(date +%s)
    output=$(send_and_wait "dh pregen start minecraft:overworld $center_x $center_z $radius_chunks" 'Starting pregen' 30) || {
        printf '%s\n' "$output"
        die "Distant Horizons did not report a started task"
    }
    printf '%s\n' "$output"
    state_set dh_started_epoch "$started_at"
    state_set phase dh-running
    trap - ERR
}

wait_dh() {
    local current_phase started_at
    current_phase=$(phase)
    case "$current_phase" in
        dh-complete|complete)
            say "DH already completed; current phase is $current_phase"
            return
            ;;
        dh-running) ;;
        *) die "DH wait requires phase dh-running; phase is $current_phase" ;;
    esac
    started_at=$(state_get dh_started_epoch)
    while true; do
        require_server_live
        TASK_OUTPUT=$(send_and_wait "dh pregen status" '(Pregen is not running|Generated radius:)' 20) || {
            printf '%s\n' "$TASK_OUTPUT"
            die "could not query DH progress"
        }
        printf '%s\n' "$TASK_OUTPUT"
        if logs_since_contain "$started_at" 'Pregen is cancelled'; then
            die "Distant Horizons pregeneration was cancelled"
        fi
        if logs_since_contain "$started_at" 'Pregen is complete'; then
            state_set dh_completed_epoch "$(date +%s)"
            state_set phase dh-complete
            say "Distant Horizons pregeneration completed"
            return
        fi
        if grep -q 'Pregen is not running' <<<"$TASK_OUTPUT"; then
            die "DH is idle but no completion marker exists; refusing to assume success"
        fi
        sleep 30
    done
}

finalize_prep() {
    local current_phase
    current_phase=$(phase)
    [[ "$current_phase" == complete ]] && { say "Paralon preparation is already complete"; return; }
    [[ "$current_phase" == dh-complete ]] || die "finalize requires phase dh-complete; phase is $current_phase"
    stop_server
    configure_phase idle
    start_server
    "$PHASE_CHECK" idle "$MC_ROOT"
    require_tasks_idle
    state_set phase complete
    state_set completed_at "$(date +%Y%m%d-%H%M%S)"
    say "Paralon is installed, Chunky is complete, DH LOD pregeneration is complete, and Regnum is idle"
}

rollback_world() {
    local current_phase rollback failed stamp
    current_phase=$(phase)
    [[ "$current_phase" != uninitialized && "$current_phase" != rolled-back ]] ||
        die "there is no active Paralon installation to roll back"
    rollback=$(state_get rollback_world)
    [[ -n "$rollback" && -d "$rollback" ]] || die "rollback world is missing: ${rollback:-<unset>}"
    if [[ "${PARALON_CONFIRM:-}" != "ROLL BACK PARALON" ]]; then
        printf 'Type ROLL BACK PARALON to continue: '
        read -r PARALON_CONFIRM
    fi
    [[ "$PARALON_CONFIRM" == "ROLL BACK PARALON" ]] || die "rollback not confirmed"
    stamp=$(date +%Y%m%d-%H%M%S)
    failed="$PREP_ROOT/removed-paralon-$stamp"
    stop_server
    [[ -d "$MC_ROOT/world" ]] && mv "$MC_ROOT/world" "$failed"
    mv "$rollback" "$MC_ROOT/world"
    if [[ -d "$STATE_DIR/config-before-pregen" ]]; then
        cp -a "$STATE_DIR/config-before-pregen/DistantHorizons.toml" "$MC_ROOT/config/DistantHorizons.toml"
        cp -a "$STATE_DIR/config-before-pregen/chunky/config.json" "$MC_ROOT/config/chunky/config.json"
    fi
    start_server
    state_set removed_paralon "$failed"
    state_set phase rolled-back
    say "Prior Regnum world restored; removed Paralon remains at $failed"
}

show_status() {
    local current_phase checker_mode=idle
    current_phase=$(phase)
    printf 'host=%s\nuser=%s\nserver_root=%s\nphase=%s\n' "$(hostname)" "$(whoami)" "$MC_ROOT" "$current_phase"
    printf 'edition=%s\ncenter=%s,%s\nradius_chunks=%s\nradius_blocks=%s\n' \
        "$(state_get edition '<not installed>')" "$(state_get center_x '?')" "$(state_get center_z '?')" \
        "$(state_get radius_chunks '?')" "$(state_get radius_blocks '?')"
    if server_is_live; then
        echo "server=healthy on port $PORT"
        case "$current_phase" in
            chunky-running|chunky-complete) checker_mode=chunky ;;
            dh-running|dh-complete) checker_mode=dh-pregen ;;
        esac
        "$PHASE_CHECK" "$checker_mode" "$MC_ROOT" || true
        query_tasks && printf '%s\n' "$TASK_OUTPUT" || true
    else
        echo "server=not healthy"
        [[ -z "$(port_line)" ]] || echo "port_holder=$(port_line)"
    fi
    [[ ! -f "$STATE_DIR/backup_archive" ]] || echo "backup=$(state_get backup_archive)"
    [[ ! -f "$STATE_DIR/rollback_world" ]] || echo "rollback=$(state_get rollback_world)"
}

self_test() {
    local root json toml fake_world output output_again config_hash backup_source backup_archive
    local original_session tmux_prefix
    root=$(mktemp -d /tmp/prepare-paralon-test.XXXXXX)
    json="$root/config.json"
    toml="$root/config.toml"
    fake_world="$root/incoming/world"
    mkdir -p "$fake_world/region"
    printf '{"forceLoadExistingChunks": false}\n' > "$json"
    printf 'distantGeneratorMode = "PRE_EXISTING_ONLY"\nenableDistantGeneration = true\n' > "$toml"
    printf 'test-level' > "$fake_world/level.dat"
    python3 - "$fake_world/region/r.-1.-1.mca" "$fake_world/region/r.0.0.mca" <<'PY'
import pathlib, sys
for name in sys.argv[1:]:
    header = bytearray(4096)
    header[:4] = b"\x00\x00\x02\x01"
    pathlib.Path(name).write_bytes(header)
PY
    set_json_bool "$json" forceLoadExistingChunks true
    set_toml_value "$toml" enableDistantGeneration false
    grep -q '"forceLoadExistingChunks": true' "$json"
    grep -q '^enableDistantGeneration = false$' "$toml"
    config_hash=$(sha256sum "$json" "$toml")
    set_json_bool "$json" forceLoadExistingChunks true
    set_toml_value "$toml" enableDistantGeneration false
    [[ "$(sha256sum "$json" "$toml")" == "$config_hash" ]]
    output=$(REGNUM_PARALON_TESTING=1 REGNUM_INCOMING_ROOT="$root/incoming" "$0" inspect "$fake_world")
    output_again=$(REGNUM_PARALON_TESTING=1 REGNUM_INCOMING_ROOT="$root/incoming" "$0" inspect "$fake_world")
    [[ "$output_again" == "$output" ]]
    grep -q '^REGION_COUNT=2$' <<<"$output"
    grep -q '^ALLOCATED_CHUNKS=2$' <<<"$output"
    grep -q '^MIN_RADIUS_CHUNKS=' <<<"$output"
    backup_source="$root/backup-source"
    backup_archive="$root/backup.tar.gz"
    mkdir -p "$backup_source/world/region"
    printf 'backup-level' > "$backup_source/world/level.dat"
    python3 - "$backup_source/world/region" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for index in range(4096):
    root.joinpath(f"payload-{index:04d}-{'x' * 64}").touch()
PY
    tar -C "$backup_source" -czf "$backup_archive" world/level.dat world/region
    if (set -o pipefail; tar -tzf "$backup_archive" | grep -qx 'world/level.dat'); then
        die "backup regression fixture did not reproduce the early-exit pipe failure"
    fi
    verify_world_backup "$backup_archive"
    require_command tmux
    original_session="$SESSION"
    tmux_prefix="paralon-selftest-$$-$RANDOM"
    tmux new-session -d -s "${tmux_prefix}-wizard" "sleep 30"
    SESSION="$tmux_prefix"
    tmux has-session -t "$SESSION" 2>/dev/null ||
        die "tmux prefix regression fixture did not reproduce the ambiguous match"
    if server_session_exists; then
        die "exact server session check matched the wizard session prefix"
    fi
    tmux new-session -d -s "$SESSION" "sleep 30"
    server_session_exists || die "exact server session check missed the real session"
    [[ "$(tmux display-message -p -t "=$SESSION:" '#{session_name}')" == "$SESSION" ]] ||
        die "exact server pane target missed the real session"
    tmux send-keys -t "=$SESSION:" Space
    tmux kill-session -t "=$SESSION"
    tmux kill-session -t "=${tmux_prefix}-wizard"
    SESSION="$original_session"
    case "$root" in /tmp/prepare-paralon-test.*) rm -r -- "$root" ;; *) die "unsafe self-test directory" ;; esac
    echo "PASS: idempotent config mutation, map inspection, backup verification, and exact tmux targeting"
}

action="${1:-status}"
[[ $# -gt 0 ]] && shift

require_command python3
require_command realpath
require_command sha256sum

case "$action" in
    self-test)
        [[ $# -eq 0 ]] || usage
        self_test
        ;;
    status)
        [[ $# -eq 0 ]] || usage
        validate_identity
        show_status
        ;;
    inspect)
        [[ $# -eq 1 ]] || usage
        validate_identity
        source_metrics "$1"
        print_metrics
        ;;
    install)
        [[ $# -eq 6 ]] || usage
        validate_identity
        init_mutation_state
        install_world "$@"
        ;;
    chunky-start)
        [[ $# -eq 0 ]] || usage
        validate_identity
        init_mutation_state
        start_chunky
        ;;
    chunky-wait)
        [[ $# -eq 0 ]] || usage
        validate_identity
        init_mutation_state
        wait_chunky
        ;;
    dh-start)
        [[ $# -eq 0 ]] || usage
        validate_identity
        init_mutation_state
        start_dh
        ;;
    dh-wait)
        [[ $# -eq 0 ]] || usage
        validate_identity
        init_mutation_state
        wait_dh
        ;;
    finalize)
        [[ $# -eq 0 ]] || usage
        validate_identity
        init_mutation_state
        finalize_prep
        ;;
    rollback)
        [[ $# -eq 0 ]] || usage
        validate_identity
        init_mutation_state
        rollback_world
        ;;
    *) usage ;;
esac
