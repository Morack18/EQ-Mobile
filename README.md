# EQ Mobile

An offline, Android-first Godot 4 prototype.

## Run the vertical slice

Open this folder in Godot 4.7 or newer and press **Run**. The starting scene is
`scenes/Main.tscn`.

Desktop controls are WASD/arrow keys to move, Space to jump, Tab to target the
nearest Halas NPC, and click to attack. On a device, use the lower-left
joystick to move, drag the right side to orbit the camera, hold **JUMP** to
jump or swim upward, tap an NPC to target it, and tap **ATTACK** when in range.

The prototype currently starts in [Halas](data/halas.json), rendering the GLB
and all 445 static object placements from Lantern's manifest. It includes a
player, one original Training Spark fixture NPC, basic pursuit/attacks,
death/respawn, and offline persistence. Defeating that fixture awards an
original Training Spark Fragment and persists its count; it does not enable
loot for the imported Halas NPC roster. Press `R` on desktop to clear its local
save. Player defeat temporarily locks movement and attacks, then returns the
player to the configured safe spawn with full health. The fixture also awards
explicit tuned XP, displaying cumulative progress and applying the configured
classic-era level cap; it does not assign XP to imported Halas NPCs.

See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for source-resource boundaries,
architecture, and the next milestones.

## Validate Halas import data

Run the read-only checks after regenerating Halas source data or refreshing
imported assets:

```bash
python3 tools/validate_halas_zone_data.py
python3 tools/validate_halas_spawn_coordinates.py
python3 tools/validate_halas_asset_scale.py
python3 tools/validate_halas_merchant_data.py
python3 tools/apply_halas_npc_overlay.py --verify-only
python3 tools/validate_training_slice_data.py
```

`data/eqemu_default_heights.json` is generated from the local EQEmu source for
future zone importers; refresh it with `python3 tools/generate_eqemu_default_heights.py`.
The runtime Halas NPC snapshot is derived from the raw ProjectEQ snapshot and
the reviewed P1999 overlay. After either input changes, regenerate it with
`python3 tools/apply_halas_npc_overlay.py`, then run the verification command
above.
