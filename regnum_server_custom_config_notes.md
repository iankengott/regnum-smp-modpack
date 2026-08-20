# Regnum Server Custom Config Notes

This file summarizes the custom server changes made or intended to preserve while rebuilding/restoring the Minecraft server.

## Target Final State

The intended setup is:

```text
Distant Horizons installed
Distant Horizons mode = PRE_EXISTING_ONLY
Distant Horizons radius = 625 chunks
Chunky installed
ChunkyBorder installed
chunky-offline installed
C2ME installed
max-tick-time=-1
view-distance=10
simulation-distance=6
Chunky square border radius = 625c
Chunky pregeneration running for overworld
```

---

## Distant Horizons Settings

Config file:

```bash
~/regnum/config/DistantHorizons.toml
```

Set:

```toml
distantGeneratorMode = "PRE_EXISTING_ONLY"
```

Reason: Chunky will generate/save real chunks. Distant Horizons should only build LODs from chunks that already exist, instead of forcing live full chunk generation.

Also set:

```toml
lodChunkRenderDistanceRadius = 625
```

Reason: 625 chunks equals 10,000 blocks of DH LOD radius.

Earlier value tried but moved away from:

```toml
distantGeneratorMode = "INTERNAL_SERVER"
```

That corresponds to “Full - Save Chunks,” but at 625 chunks it caused server watchdog freezes because it forced real chunk generation through Distant Horizons.

---

## Server Watchdog / `server.properties`

Config file:

```bash
~/regnum/server.properties
```

Set:

```properties
max-tick-time=-1
```

Reason: disables the watchdog killing the server when chunk generation causes a long tick.

Also keep vanilla render/simulation distance sane:

```properties
view-distance=10
simulation-distance=6
```

Reason: do not use vanilla view distance for extreme rendering. Chunky and Distant Horizons handle the huge area, not vanilla Minecraft.

---

## Chunky Mods Added

These were added to support pregeneration and world borders:

```text
Chunky-NeoForge-1.4.23.jar
ChunkyBorder-1.2.18.jar
chunky-offline-v1.1.0.jar
```

Purpose:

```text
Chunky = pregenerate real chunks
ChunkyBorder = apply a world border from the Chunky selection
chunky-offline = let Chunky keep working without players online
```

Install location:

```bash
~/regnum/mods/
```

---

## Chunky Setup Commands

Once the server launches correctly, run these in the server console:

```mcfunction
chunky world minecraft:overworld
chunky shape square
chunky center 0 0
chunky radius 625c
chunky border add
chunky start
```

Equivalent radius:

```text
625 chunks = 10,000 blocks
```

Check progress:

```mcfunction
chunky progress
```

Pause/resume:

```mcfunction
chunky pause
chunky continue
```

---

## C2ME

Wanted/installed:

```text
C2ME NeoForge for Minecraft 1.21.1
```

Purpose: speed up chunk generation, chunk loading, and chunk I/O. Logs previously showed C2ME loaded and Distant Horizons detected it, meaning DH would use C2ME-handled methods for pre-existing chunk access.

Install location:

```bash
~/regnum/mods/
```

---

## JVM / Launch Files Needed

The working server needs these launch pieces:

```text
start.sh
run.sh
server.jar
user_jvm_args.txt
libraries/
versions/
```

The important NeoForge file path verified earlier was:

```text
~/regnum/libraries/net/neoforged/neoforge/21.1.228/unix_args.txt
```

If rebuilding from an old working server backup, copy these from the backup into the new `~/regnum` folder.

---

## Player / Server Identity Files to Preserve

Copy these from the old working server if wiping/replacing:

```text
eula.txt
ops.json
whitelist.json
banned-players.json
banned-ips.json
server.properties
```

---

## Verification Commands After Restoring

Run:

```bash
cd ~/regnum

echo "=== DH ==="
grep -nE 'distantGeneratorMode|lodChunkRenderDistanceRadius' config/DistantHorizons.toml

echo
echo "=== Server properties ==="
grep -nE 'max-tick-time|view-distance|simulation-distance' server.properties

echo
echo "=== Key mods ==="
ls mods | grep -iE 'chunky|distant|c2me'

echo
echo "=== Launcher files ==="
find . -maxdepth 6 \( -iname '*unix_args.txt' -o -iname 'server.jar' -o -iname 'run.sh' -o -iname 'start.sh' \) -print
```

Expected output should include:

```text
distantGeneratorMode = "PRE_EXISTING_ONLY"
lodChunkRenderDistanceRadius = 625
max-tick-time=-1
view-distance=10
simulation-distance=6
Chunky-NeoForge...
ChunkyBorder...
chunky-offline...
DistantHorizons...
c2me...
start.sh / run.sh / server.jar / unix_args.txt present
```

---

## Launch and Confirm Mods Loaded

Start server:

```bash
cd ~/regnum
./start.sh
```

After boot, check logs:

```bash
grep -iE 'chunky|chunkyborder|distant|c2me' logs/latest.log | tail -120
```

Then apply the Chunky square border and begin pregeneration from the server console:

```mcfunction
chunky world minecraft:overworld
chunky shape square
chunky center 0 0
chunky radius 625c
chunky border add
chunky start
```

Check progress:

```mcfunction
chunky progress
```
