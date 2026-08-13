# Regnum SMP Modpack AI handoff

This file is the starting point for any AI or developer continuing the Regnum
SMP Modpack. This repository is currently a scaffold only: it has no manifest,
configuration set, release artifact, or verified pack behavior. The target is
NeoForge 1.21.1.

## Read first

1. Read `README.md` for confirmed scope, boundaries, and status.
2. Run `hostname; whoami` before using any machine-specific path.
3. Until a numbered `ROADMAP.md` exists, `README.md` is authoritative. Once a
   numbered roadmap is added, its unfinished queue becomes the canonical work
   order and this handoff must be updated to point to it.

Never report pack commands, manifests, tests, launchers, services, or supported
combinations that do not yet exist in this scaffold.

## Current checkpoint

As of 2026-08-13, this is a documentation-only repository scaffold targeting
NeoForge 1.21.1. No mod list has been approved and no reproducible client or
server pack has been implemented. The first milestone remains an explicit mod
list decision and stable reproducible base pack before custom-mod integration.

## Subagent collaboration

Use only **Sol high** for bounded manifest, configuration, or test work and
**Luna max** for cross-mod design, integration, or difficult review. If those
profiles are unavailable, keep the work in the parent. Do not assign
overlapping files. The parent owns integration, documentation, and the
complete verification ladder.

## Repository and machine boundaries

- Main PC identity: `nixos` / `iank`.
- Main-PC checkout:
  `/home/iank/Desktop/my mods/mods-editing/regnum-smp-modpack`
- Public remote:
  `https://github.com/iankengott/regnum-smp-modpack`
- No Hermes mirror, development port, launcher, or service exists for this
  repository yet. Do not invent or operate one without explicit setup.
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

Gameplay code remains in its owning repositories: Vector-Regnum, Origins,
Combat, Progression, World/Story, and Administration. Do not patch around an
owning mod's defect in pack configuration when its source or public API is the
correct fix; document and coordinate the cross-repository requirement.

## Required verification ladder

Use verification proportionate to the change. At the current scaffold stage:

1. Check Markdown links and factual consistency, search for stale scaffold
   claims, and run `git diff --check`.
2. When manifests and configuration exist, use their documented validation
   tools; verify schema, pinned versions, hashes, dependency/load-order rules,
   client/server inclusion, JSON, and shell syntax. Confirm the same inputs
   reproduce the same pack contents.
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
