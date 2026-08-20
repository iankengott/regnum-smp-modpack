# Regnum SMP Modpack

Canonical NeoForge 1.21.1 modpack configuration, manifest, compatibility
matrix, and distribution project for the Regnum SMP.

Repository: [iankengott/regnum-smp-modpack](https://github.com/iankengott/regnum-smp-modpack)

**This repository is the live pack.** Pushing to `main` changes what the Regnum
live server runs, and every subscribed client pulls the change on its next
sync. Treat `main` accordingly.

## Owns

- The approved NeoForge 1.21.1 mod list and reproducible server/client pack.
- MineColonies and other third-party dependency selection.
- Veil/shader/Create compatibility, performance profiles, and pack-level
  configuration.
- WATUT/Requiem replacement or port decisions, release archives, and install docs.
- Cross-mod integration testing for the Regnum suite.

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

To add a mod from Modrinth, install an exact version ID into the live instance
and regenerate the manifest in one verified step:

```bash
scripts/install-modrinth-mod.sh MODRINTH_VERSION_ID
```

The installer rejects versions that do not list Minecraft 1.21.1 and NeoForge,
checks the primary file's SHA-512 from Modrinth, and is safe to rerun.

## Pack customizations

- Chunky 1.4.23 is included for operator-controlled chunk pregeneration. It
  remains idle until an operator starts a task. `minecraft/config/chunky/config.json`
  resumes saved tasks after a restart and limits progress messages to one every
  five seconds.

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

## Planned rendering dependency

[FoundryMC Veil](https://github.com/FoundryMC/Veil) is approved as
Vector-Regnum's optional client rendering foundation after its NeoForge port.
It is not in a manifest yet. Before inclusion, select and pin the exact tested
Minecraft 1.21.1 version, verify its LGPL-3.0 redistribution obligations and
transitive licenses, classify every artifact as client/common/server, and test
Veil present and absent with the supported shader, renderer, Create, and Regnum
suite combinations. Dedicated servers and mandatory gameplay telegraphs must
remain functional without client rendering classes.

The pack is announced on the [Regnum Hub](https://iankengott.github.io/regnum-hub/).
