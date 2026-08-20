# Regnum SMP Modpack

Canonical NeoForge 1.21.1 modpack configuration, manifest, compatibility
matrix, and distribution project for the Regnum SMP.

Repository: [iankengott/regnum-smp-modpack](https://github.com/iankengott/regnum-smp-modpack)

**This repository is the live pack.** Pushing to `main` changes what the Regnum
live server runs, and every subscribed client pulls the change on its next
sync. Treat `main` accordingly.

## Layout

| Path | Contents |
|---|---|
| `minecraft/config/` | Every mod's configuration — the substance of the pack |
| `minecraft/defaultconfigs/` | Per-world config defaults |
| `manifest/` | Mod, resource pack, shader pack, datapack, and loader inventories |
| `mmc-pack.json` | Minecraft, NeoForge, and LWJGL versions |
| `scripts/` | Manifest generation, drift checking, and instance sync |
| `regnum_server_custom_config_notes.md` | Server-side Distant Horizons / Chunky notes |

## What is not in git, and why

The checkout is a live Prism Launcher instance directory, so most of what sits
beside these files is deliberately untracked. `.gitignore` is whitelist-only:
everything is ignored, and tracked paths are re-included one at a time.

- **No mod jars, resource packs, shader packs, or datapack zips.** They are
  third-party artifacts under their own licenses and are not ours to
  redistribute. `manifest/` records each one by filename, byte size, and
  SHA-256 instead, which is enough to verify or reproduce a pack without
  shipping the files.
- **No worlds, logs, backups, screenshots, or Distant Horizons LOD data.** The
  instance carries several gigabytes of these; none of it is pack definition.
- **No `instance.cfg`.** It pins an absolute `/nix/store` Java path and this
  machine's memory settings, so syncing it between installs would break
  launching. Set these by hand in Prism:

  | Setting | Value |
  |---|---|
  | Java | 21 |
  | JVM arguments | `-XX:+UseZGC` |

- **No `options.txt`, `servers.dat`, or per-player mod state.** Keybinds and
  server lists belong to the player, not the pack.

## Working on the pack

The instance directory itself is the checkout — edit configs in Prism or by
hand, then commit from there.

```bash
cd ~/.local/share/PrismLauncher/instances/1.21.1

scripts/generate-manifest.sh   # after adding/removing/updating any jar or pack
scripts/check-mods.sh          # do the jars on disk match manifest/mods.tsv?
git add -A && git commit -m "..." && git push
```

`generate-manifest.sh` is the only way `manifest/` should ever change; do not
hand-edit the TSVs.

## Subscribing a client

A second machine clones into a fresh Prism instance directory, supplies its own
jars to match `manifest/mods.tsv`, and then either runs `scripts/sync-instance.sh`
by hand or installs the timer described below.

`sync-instance.sh` is deliberately conservative and refuses rather than
clobbers. It skips while Minecraft is running, uses `--ff-only` so a diverged
branch stops the sync instead of merging, and skips when tracked files are
dirty so local config edits are never silently lost. When a pull changes
`manifest/`, it runs `check-mods.sh` and reports which jars now need fetching.

### Automatic updates

Git has no push-to-client mechanism, so the client polls. On the main PC this
is a systemd user timer declared in `/etc/nixos/home.nix`:

```bash
systemctl --user list-timers regnum-modpack-sync   # when it next runs
systemctl --user start regnum-modpack-sync         # sync right now
journalctl --user -u regnum-modpack-sync -n 50     # what it did
```

## Boundary

Gameplay code remains in its owning repositories:
[Vector-Regnum](https://github.com/iankengott/vector-regnum),
[Origins](https://github.com/iankengott/regnum-origins),
[Combat](https://github.com/iankengott/regnum-combat),
[Progression](https://github.com/iankengott/regnum-progression),
[World/Story](https://github.com/iankengott/regnum-world-story), and
[Administration](https://github.com/iankengott/regnum-administration).

The pack is announced on the [Regnum Hub](https://iankengott.github.io/regnum-hub/).
