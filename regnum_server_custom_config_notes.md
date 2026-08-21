# Regnum server Distant Horizons and Chunky workflow

This is the operational recipe for the live Regnum server. It records verified
state separately from work that an operator has not started.

## Verified state on 2026-08-20

- Distant Horizons 3.2.0-b, Chunky 1.4.23, and C2ME
  0.4.0-alpha.0.120 are installed on Hermes.
- Both mods load, and Distant Horizons registers its C2ME integration.
- `distantGeneratorMode = "PRE_EXISTING_ONLY"`.
- The live server's DH render radius is 150 chunks. The tracked Prism client
  config currently uses 50 chunks. Neither value sets the pre-generation area.
- Chunky has `continueOnRestart = true` and a five-second update interval.
- `max-tick-time=-1`, `view-distance=10`, and `simulation-distance=6`.
- `chunky progress` and `dh pregen status` both report no running task.
- ChunkyBorder and chunky-offline are not installed. Neither is required for
  the workflow below.

The earlier 625-chunk plan was never started. Do not report the 10,000-block
area as generated until both stages finish and their output is checked.

## Why the two stages must be separate

Chunky saves complete Minecraft chunks. Distant Horizons builds a separate LOD
database. Distant Horizons 3.2.0-b warns that Chunky can produce chunks faster
than its LOD queue can process. When the queue drops old work, the result is
holes in the LOD database.

Do not start Chunky while `enableDistantGeneration = true`. Use Chunky first
with DH ingestion disabled, then use DH's own pre-generator to scan the saved
chunks. `PRE_EXISTING_ONLY` keeps the second stage from creating terrain beyond
the real world.

Run the phase check from the pack checkout before each stage:

```bash
scripts/check-dh-chunky.sh idle "$PWD"
scripts/check-dh-chunky.sh chunky SERVER_ROOT
scripts/check-dh-chunky.sh dh-pregen SERVER_ROOT
```

For Hermes without copying the script permanently:

```bash
ssh HERMES_HOST \
  'bash -s -- chunky /home/ian-kengott/regnum/new-server/mc' \
  < scripts/check-dh-chunky.sh
```

## Stage 1: generate saved chunks with Chunky

1. Take a world backup and stop the server cleanly.
2. In the live server's `config/DistantHorizons.toml`, set:

   ```toml
   distantGeneratorMode = "PRE_EXISTING_ONLY"
   enableDistantGeneration = false
   ```

3. Start the server and require the `chunky` phase check to pass.
4. Select the exact area. This example is the old 10,000-block-radius plan:

   ```mcfunction
   chunky world minecraft:overworld
   chunky shape square
   chunky center 0 0
   chunky radius 625c
   chunky start
   ```

5. Monitor with `chunky progress`. Let it finish before stage 2. Do not start a
   DH pre-generation task at the same time.

The `625c` argument means 625 chunks, or 10,000 blocks. Pick the radius from
the actual map boundary. `lodChunkRenderDistanceRadius` is only a render
distance and is not a substitute for the command radius.

## Stage 2: build LODs from the saved chunks

1. Stop the server cleanly.
2. Set `enableDistantGeneration = true` and keep
   `distantGeneratorMode = "PRE_EXISTING_ONLY"`.
3. Start the server and require the `dh-pregen` phase check to pass.
4. Run DH's pre-generator over the same center and chunk radius:

   ```mcfunction
   dh pregen start minecraft:overworld 0 0 625
   ```

5. Monitor with `dh pregen status`. Do not open the server to normal play until
   it reports completion and the server log has no fatal, out-of-memory, or
   pre-generation failure.
6. Connect a real client and inspect the outer edge and several interior areas
   for missing LOD tiles. Keep the backup until that visual check passes.

The server's `enableServerGeneration` setting controls whether clients may ask
it to generate missing LODs during play. It does not replace the explicit
`dh pregen` stage.

## Routine idle state

After both stages, leave:

```toml
distantGeneratorMode = "PRE_EXISTING_ONLY"
enableDistantGeneration = true
```

Require the `idle` phase check to pass. Chunky should have no running task.

Useful status commands:

```mcfunction
chunky progress
dh pregen status
```

Chunky 1.4.23 saves active tasks during a clean shutdown and the tracked config
continues them after restart. An extra chunky-offline mod is not needed on this
dedicated server. Install ChunkyBorder only if the server needs its separate
border integration; it is unrelated to reliable LOD generation.

Upstream references:

- [Distant Horizons server-owner pre-generation guidance](https://gitlab.com/distant-horizons-team/distant-horizons/-/wikis/1-user-guide/1-frequently-asked-questions/5-server-owners/Server-Owners)
- [Chunky FAQ: using Chunky with Distant Horizons](https://github.com/pop4959/Chunky/wiki/FAQ#can-i-use-chunky-to-pre-generate-my-world-with-the-distanthorizons-mod)
