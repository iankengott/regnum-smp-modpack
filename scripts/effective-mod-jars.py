#!/usr/bin/env python3
"""List the jars Minecraft effectively loads, including AutoModpack's overlay."""

import argparse
import hashlib
import json
import locale
import pathlib
import sys


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            value.update(chunk)
    return value.hexdigest()


def game_dir(instance):
    for name in ("minecraft", ".minecraft"):
        candidate = instance / name
        if candidate.is_dir():
            return candidate
    raise SystemExit(f"ERROR: no minecraft/ directory under {instance}")


def selected_overlay(game):
    config = game / "automodpack" / "automodpack-client.json"
    if not config.is_file():
        return None
    try:
        selected = json.loads(config.read_text()).get("selectedModpack", "")
    except (OSError, ValueError) as error:
        raise SystemExit(f"ERROR: cannot read {config}: {error}") from error
    if not selected:
        return None

    base = (game / "automodpack" / "modpacks").resolve()
    overlay = (base / selected / "mods").resolve()
    if base not in overlay.parents:
        raise SystemExit(f"ERROR: unsafe AutoModpack selection: {selected}")
    if not overlay.is_dir():
        raise SystemExit(f"ERROR: selected AutoModpack overlay has no mods/: {overlay}")
    return overlay


def effective_jars(instance):
    game = game_dir(instance)
    roots = [game / "mods"]
    overlay = selected_overlay(game)
    if overlay is not None:
        roots.append(overlay)

    chosen = {}
    hashes = {}
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.glob("*.jar"), key=lambda item: item.name):
            previous = chosen.get(path.name)
            if previous is None:
                chosen[path.name] = path
                continue
            previous_hash = hashes.setdefault(previous, digest(previous))
            current_hash = digest(path)
            if previous_hash != current_hash:
                raise SystemExit(
                    f"ERROR: conflicting effective jars named {path.name}: "
                    f"{previous} != {path}"
                )
    try:
        locale.setlocale(locale.LC_COLLATE, "en_US.UTF-8")
    except locale.Error as error:
        raise SystemExit(f"ERROR: en_US.UTF-8 collation is unavailable: {error}") from error
    return [chosen[name] for name in sorted(chosen, key=locale.strxfrm)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--instance", type=pathlib.Path, required=True)
    args = parser.parse_args()
    for path in effective_jars(args.instance.resolve()):
        sys.stdout.buffer.write(str(path).encode() + b"\0")


if __name__ == "__main__":
    main()
