#!/usr/bin/env bash
# Publish the versioned Regnum operator docs to a Hermes admin directory.
set -euo pipefail

usage() {
    echo "usage: $0 SSH_HOST [REMOTE_REGNUM_DIR]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
server="$1"
remote_dir="${2:-regnum}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$remote_dir" =~ ^[A-Za-z0-9._/-]+$ ]] || {
    echo "FAIL: unsafe remote directory: $remote_dir" >&2
    exit 1
}
[[ "$remote_dir" != /* && "$remote_dir" != *..* ]] || {
    echo "FAIL: remote directory must be relative and contain no '..': $remote_dir" >&2
    exit 1
}

files=(
    README.md
    regnum_server_custom_config_notes.md
    scripts/check-dh-chunky.sh
    scripts/prepare-paralon-world.sh
    scripts/prepare-paralon-wizard.sh
    scripts/sync-hermes-admin-docs.sh
)

for file in "${files[@]}"; do
    [[ -f "$repo_root/$file" ]] || {
        echo "FAIL: missing $repo_root/$file" >&2
        exit 1
    }
done

git -C "$repo_root" diff --quiet -- "${files[@]}" || {
    echo "FAIL: operator docs differ from the checked-out commit" >&2
    exit 1
}
git -C "$repo_root" diff --cached --quiet -- "${files[@]}" || {
    echo "FAIL: operator docs have staged changes" >&2
    exit 1
}

commit="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "FAIL: could not resolve the source commit" >&2
    exit 1
}
remote_commit="$(git -C "$repo_root" ls-remote origin refs/heads/main | awk '{print $1}')"
[[ "$remote_commit" == "$commit" ]] || {
    echo "FAIL: local HEAD $commit does not match GitHub main ${remote_commit:-<missing>}" >&2
    exit 1
}

remote_admin="$remote_dir/admin"
ssh -o BatchMode=yes "$server" "mkdir -p \"\$HOME/$remote_admin/scripts\""
rsync -a --checksum \
    "$repo_root/README.md" \
    "$repo_root/regnum_server_custom_config_notes.md" \
    "$server:~/$remote_admin/"
rsync -a --checksum \
    "$repo_root/scripts/check-dh-chunky.sh" \
    "$repo_root/scripts/prepare-paralon-world.sh" \
    "$repo_root/scripts/prepare-paralon-wizard.sh" \
    "$repo_root/scripts/sync-hermes-admin-docs.sh" \
    "$server:~/$remote_admin/scripts/"
ssh -o BatchMode=yes "$server" \
    "printf '%s\\n' '$commit' > \"\$HOME/$remote_admin/SOURCE_COMMIT\""

for file in "${files[@]}"; do
    local_hash="$(sha256sum "$repo_root/$file" | awk '{print $1}')"
    remote_hash="$(ssh -o BatchMode=yes "$server" \
        "sha256sum \"\$HOME/$remote_admin/$file\"" | awk '{print $1}')"
    [[ "$local_hash" == "$remote_hash" ]] || {
        echo "FAIL: hash mismatch for $file" >&2
        exit 1
    }
    echo "PASS: $file $local_hash"
done

remote_commit="$(ssh -o BatchMode=yes "$server" \
    "cat \"\$HOME/$remote_admin/SOURCE_COMMIT\"")"
[[ "$remote_commit" == "$commit" ]] || {
    echo "FAIL: remote source commit is $remote_commit, expected $commit" >&2
    exit 1
}

remote_phase="$(ssh -o BatchMode=yes "$server" \
    "cat \"\$HOME/$remote_dir/paralon-prep/state/phase\" 2>/dev/null || printf uninitialized")"
case "$remote_phase" in
    chunky-running|chunky-complete) remote_mode=chunky ;;
    dh-running|dh-complete) remote_mode=dh-pregen ;;
    *) remote_mode=idle ;;
esac
ssh -o BatchMode=yes "$server" \
    "bash \"\$HOME/$remote_admin/scripts/check-dh-chunky.sh\" '$remote_mode' \"\$HOME/$remote_dir/new-server/mc\""
echo "PASS: Hermes admin docs match commit $commit"
