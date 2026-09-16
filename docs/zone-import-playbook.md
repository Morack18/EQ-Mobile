# Zone import playbook

This is the repeatable process for bringing a classic/P1999-era zone into EQ
Mobile. It is based on the completed Halas slice. Treat the generated runtime
assets and JSON as outputs; never edit source files under `resources/` during a
normal import.

## Invariants

- The game is an offline Godot simulation. EQEmu/ProjectEQ data is input data,
  not code to port or a runtime database dependency.
- Each generated dataset records its source archive/revision, era filters,
  source zone IDs, and coordinate contract.
- A zone is not accepted because it looks approximately right. Geometry scale,
  static props, every visible spawn, and every retained patrol point must be
  checked against collision built from that zone's authored geometry.
- Do not assume another zone shares Halas axes, origin, scale, or heading
  orientation. Calibrate each zone independently and record the result.

## 1. Keep inputs out of Godot scanning

Keep `resources/.gdignore` in place. Reference inputs include the EQ client,
EQEmu source, LanternExtractor, and Lantern exports. Copy only the deliberate
runtime assets into `assets/imported/<zone>/`; Godot must not attempt to import
the full reference archive.

## 2. Import geometry and props

1. Copy the extracted zone GLB into `assets/imported/<zone>/`.
2. Inspect its root transform and compare it with a native-scale character.
   Store only the compensating `geometry_scale` in `data/<zone>.json`; do not
   rescale the supplied source GLB.
3. Copy Lantern's object-placement manifest to `data/<zone>_objects.csv` and
   only the GLBs it references to `assets/imported/<zone>/objects/`.
4. Establish and document a prop transform separately from NPCs. Halas props
   use an X mirror, whereas Halas server NPC data uses a different conversion.
5. Build temporary triangle collision from the imported zone mesh before
   validating placements. Replace it with mobile-friendly collision/navmesh
   once the zone is accepted.
6. Add a read-only scale/provenance validator that checks copied runtime GLBs
   and placement manifests against their export source, verifies any declared
   root-scale compensation resolves to one, and rejects missing referenced
   props. Run it after every source-asset refresh.

## 3. Generate classic NPC source data

Use a read-only importer against a pinned content archive. Filter at minimum:

- target zone table row and client zone ID;
- original-EQ expansion (`0`);
- no event-content flags;
- complete `npc_types` references;
- grids whose points belong to the target zone.

Preserve source IDs and the NPC appearance fields: `race`, `gender`,
`texture`, and `face`. Preserve grid point order, heading, and pause duration.
Cross-zone/missing grid references must remain data provenance only; they must
not become fabricated local patrols.

For Halas, `tools/import_peq_halas.py` is the working reference implementation.
Its server rows use `[x, y, elevation]`; `grid_entries.zoneid` is the client
zone number, while the `zone` table also has a separate auto-increment ID.

## 4. Calibrate coordinates before trusting positions

For each candidate axis/sign mapping:

1. Convert every static spawn and valid patrol point.
2. Ray-cast down onto the imported zone collision near its server elevation.
3. Count points that agree within a small vertical tolerance.
4. Select a mapping only when it is the clear, documented winner; retain only
   vertical ground correction after that—never use collision to hide a wrong
   horizontal conversion.

Halas proved `(-server_y, elevation, server_x)`, with all 67 visible static
spawns and 178 retained patrol points terrain-aligned. Its heading conversion
is kept alongside that contract in `HalasNpcPopulation`. Future zones must
perform the same audit rather than copying this conversion blindly.

## 5. Export actor appearance variants

An NPC visual key is derived from its server appearance data:

`family + texture skin + face head`

Map race/gender to the actual EQ actor family first; never substitute a nearby
body merely because it is available in the zone export. Export the required
skin/head combinations as separate animated GLBs, because Godot imports the
GLB material selection into its `PackedScene`.

Normalize each extracted NPC rig by its measured loaded-model height, then set the
result to the server's resolved `size`: `server size / measured GLB height`.
For a zero/non-positive source size, resolve `size` first through EQEmu's
race-gender default-height table. This matches the original client's units
without assuming that different Lantern exports share an authored scale.
Ground the model using its measured feet and place its nameplate above the
resolved height.

For Halas the relevant mappings are Halas citizen `hlm`/`hlf`, Barbarian
`bam`/`baf`, Human `hum`/`huf`, and wolf `wol`. `face` uses the source's
zero-based/default convention (face `0` is head variant `0`). Clamp only when
the original model has no corresponding variant, and log/document that as an
appearance limitation rather than silently selecting a random skin. A server
`texture` that represents armor/equipment needs a future equipment appearance
layer; it is not evidence of a base-body skin that exists in the model.

Use `tools/export_halas_character_variants.sh` as the reference export recipe:

- output profile: `--game` (`idle`, `walk`, `attack`, `death`) plus original
  water clips `--animation swimming='l06|l09'` and
  `--animation treading='l08|p07'`;
- retain the validated V-flips for every body-part family;
- use a separate reduced part list for non-humanoids such as wolves;
- preserve the HLF `hufbi_l` -> `bi_l` animation-track alias in the Lantern
  converter. It fixes the legacy female left-arm bind-pose mismatch.

## 6. Verify in Godot

After new GLBs are copied, run a Godot import pass before runtime testing. GLBs
with embedded textures can require several passes in headless environments as
Godot creates import metadata and texture sidecars.

Minimum checks:

```bash
python3 -m py_compile tools/<zone>_importer.py
python3 -m json.tool data/<zone>_npcs_source.json >/dev/null
XDG_DATA_HOME=/tmp/eq-mobile-xdg godot --headless --path . --import
XDG_DATA_HOME=/tmp/eq-mobile-xdg godot --headless --path . --quit-after 4 res://scenes/Main.tscn
```

The final scene run must have no missing model resources, script errors, or
placement-audit shortfall. Inspect representative NPCs of each race, gender,
skin, head, and patrol family in the actual mobile renderer as well.

## 7. Required local pipeline checks

Before a zone is accepted, run the token-free local pipeline. It is the
default entry point for every future zone import; do not recreate these checks
in an AI conversation or rely on a device build to discover missing assets.

```bash
python3 tools/zone_pipeline.py validate --config data/zones/<zone>.pipeline.json
python3 tools/zone_pipeline.py package-check --config data/zones/<zone>.pipeline.json
godot --headless --path . --export-pack eqmobile /tmp/<zone>-package-check.pck
python3 tools/zone_pipeline.py package-check \
  --config data/zones/<zone>.pipeline.json \
  --pck /tmp/<zone>-package-check.pck
```

`validate` checks the zone definition, geometry scale compensation, placement
record shape, and every referenced prop GLB. `package-check` verifies that the
runtime data manifest and imported prop dependencies are actually in the PCK.
This catches export-filter and dynamically-loaded-resource mistakes before an
APK is made. Keep the per-zone config beside its runtime data; it records only
paths and deterministic checks, never credentials or machine-specific state.

To stage a Lantern export, copy `data/zones/zone-template.pipeline.json`, set
its paths and create the referenced zone definition first. Then run:

```bash
python3 tools/zone_pipeline.py stage-assets \
  --config data/zones/<zone>.pipeline.json
```

The command copies the geometry, unmodified placement manifest, only the GLBs
referenced by that manifest, and image sidecars declared inside each GLB. It
refuses to replace an existing runtime asset unless `--overwrite` is supplied.
It never modifies anything under `resources/`.

For ProjectEQ content archives that use the currently supported SQL dump
format, import classic-era NPC source data with:

```bash
python3 tools/zone_pipeline.py import-npcs \
  --config data/zones/<zone>.pipeline.json \
  --archive resources/reference-data/projecteq/peq-<stamp>.zip
```

The `peq` config section records the client short name and output JSON. The
importer preserves source IDs, candidate weights, appearance fields, and valid
in-zone patrols while applying the established classic expansion/event filter.
It is intentionally independent of coordinate calibration: run the candidate
transform terrain audit for every zone after import.

## Required deliverables for every zone

- `data/<zone>.json` with geometry/scale and source metadata.
- `data/zones/<zone>.pipeline.json` and a passing `zone_pipeline.py validate`
  plus packaged-PCK check.
- Object placement manifest and only referenced runtime prop assets.
- Classic-filtered NPC source JSON with source IDs and provenance.
- A zone-specific coordinate validator/audit result.
- Reproducible character export command/script and only required variants.
- A zone note in `docs/<zone>-import.md` recording transforms, counts,
  exceptions, visual findings, and follow-up work.
