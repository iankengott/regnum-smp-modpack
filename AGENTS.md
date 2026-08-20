# Regnum SMP Modpack AI handoff

This file is the starting point for any AI or developer continuing the Regnum
SMP Modpack. The repository now holds the live pack: the full mod configuration
set and hash manifests for NeoForge 1.21.1. It still has no release artifact or
verified pack behavior.

The checkout is a live Prism Launcher instance directory. Most of what sits
beside the tracked files — jars, worlds, logs, LODs — is deliberately
untracked, and `.gitignore` is whitelist-only. Read `README.md` before adding
any path to git.

## Read first

1. Read `README.md` for confirmed scope, boundaries, and status.
2. Run `hostname; whoami` before using any machine-specific path.
3. Until a numbered `ROADMAP.md` exists, `README.md` is authoritative. Once a
   numbered roadmap is added, its unfinished queue becomes the canonical work
   order and this handoff must be updated to point to it.

Never report pack commands, manifests, tests, launchers, services, or supported
combinations that do not yet exist.

## Current checkpoint

As of 2026-08-20, the repository tracks the live pack's configuration and
manifests, generated from the main PC's working instance: 269 mods, 7 resource
packs, 1 shader pack, and 2 datapacks, on Minecraft 1.21.1 / NeoForge 21.1.248.
The mod list is what is installed, not an approved list — approval, a
compatibility matrix, and a reproducible release artifact are still open.

## Subagent collaboration

Use only **Sol high** for bounded manifest, configuration, or test work and
**Luna max** for cross-mod design, integration, or difficult review. If those
profiles are unavailable, keep the work in the parent. Do not assign
overlapping files. The parent owns integration, documentation, and the
complete verification ladder.

## Repository and machine boundaries

- Main PC identity: `nixos` / `iank`.
- Main-PC checkout — the live Prism instance, and the source of truth for
  manifests:
  `/home/iank/.local/share/PrismLauncher/instances/1.21.1`
  The older documentation-only checkout at
  `/home/iank/Desktop/my mods/mods-editing/regnum-smp-modpack` predates this
  and will read as stale; do not commit from it.
- Public remote:
  `https://github.com/iankengott/regnum-smp-modpack`
- A `regnum-modpack-sync` systemd **user** timer on the main PC polls origin
  and fast-forwards the instance, declared in `/etc/nixos/home.nix`. It is
  guarded: it skips while Minecraft is running and never discards local edits.
- No Hermes mirror, development port, or launcher exists for this repository
  yet. Do not invent or operate one without explicit setup.
- Never touch production/modpack servers, Minecraft tmux sessions, unrelated
  saves, or another Regnum repository while testing this project.
- Preserve unrelated user changes and keep generated worlds, logs, caches,
  credentials, and distributable binaries out of git unless the documented
  release process explicitly owns them.

## Scope and integration boundary

This repository owns the approved NeoForge 1.21.1 mod manifest, reproducible
client/server pack, third-party dependency selection, pack-level configuration,
compatibility matrix, performance profiles, release archives, and install
documentation. It also owns cross-mod integration testing for the Regnum suite.
That matrix includes Vector-Regnum's optional Veil client backend, shaderpacks,
other renderer replacements, Create, and Veil-absent fallback behavior.

Gameplay code remains in its owning repositories: Vector-Regnum, Origins,
Combat, Progression, World/Story, and Administration. Do not patch around an
owning mod's defect in pack configuration when its source or public API is the
correct fix; document and coordinate the cross-repository requirement.

## Required verification ladder

Use verification proportionate to the change. At the current scaffold stage:

1. Check Markdown links and factual consistency, search for stale scaffold
   claims, and run `git diff --check`.
2. For manifest or config changes: run `scripts/check-mods.sh` (exits non-zero
   on drift between `minecraft/mods/` and `manifest/mods.tsv`), regenerate with
   `scripts/generate-manifest.sh` rather than hand-editing any TSV, and confirm
   a re-run produces no diff. Verify pinned versions, hashes,
   dependency/load-order rules, client/server inclusion, licenses and
   redistribution notices, JSON, and shell syntax.
3. Test pack changes with fresh, isolated NeoForge 1.21.1 dedicated-server and
   client instances. Run cross-mod connection, world creation/load, restart,
   upgrade, and representative gameplay smoke tests; inspect player-visible
   results directly and review both client and server logs.

This is not a standalone Java mod, so do not invent a Gradle build or unit-test
ladder for the pack. Individual bundled Regnum mods must pass their own Java 21
Gradle, test, JSON, shell, dedicated-server/client, and visual verification in
their owning repositories. Do not claim a validator, launcher, manifest,
profile, or test command exists until it is actually present and verified.
Documentation-only changes do not require launching Minecraft.

## Regression and safety invariants

- Client and server manifests are explicit, version-pinned, reproducible, and
  reject missing or mismatched required dependencies.
- Server-only and client-only mods/configuration stay on the correct side;
  dedicated servers never require client rendering classes or client secrets.
- Pack configuration does not silently override owning-mod security,
  permissions, claims, PvP, resource, lifecycle, or accessibility guarantees.
- World-affecting mod removals or upgrades require migration notes, backup and
  rollback guidance, and testing against a copied world—not production data.
- Compatibility claims name exact tested versions and evidence. Untested
  combinations are clearly marked unsupported or experimental.
- Veil remains an optional client enhancement for Vector-Regnum. Test it
  present and absent, post-processing enabled and disabled, resource reload,
  supported shader/renderer combinations, Create, accessibility profiles, and
  a dedicated server that never loads Veil client classes.
- Required licenses and redistribution permissions are verified before any
  third-party mod or asset is included in a release.
- Secrets, personal tokens, server credentials, player data, live addresses,
  logs, and worlds never enter manifests, configuration, archives, or git.
- Performance profiles retain correct gameplay and server-authoritative state;
  optimization may not hide required truth telegraphs or disable safety limits.
- Every release documents NeoForge, Minecraft, Java, mod, config, and world
  compatibility plus install, update, downgrade, backup, and rollback steps.

## Keeping the handoff current

After a meaningful change, update `README.md`, this file, the compatibility
matrix/release documentation when present, and any numbered `ROADMAP.md` in the
same pass. Record only verified commands, test evidence, and supported
combinations. Update the `Regnum SMP Modpack` Obsidian project hub in the
main-PC memory vault whenever scope, status, paths, integration decisions,
compatibility, releases, or priorities change.

Do not call a pack milestone complete because a manifest or archive exists. It
needs reproducibility, validation, isolated client/server smoke tests, bounded
failure and rollback behavior, and direct inspection of player-visible results.
