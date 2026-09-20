# Classic/P1999 Data Fidelity Audit

Player race/model size is source-backed. Exact Classic/P99 physical collision-hull dimensions are not established by available authoritative evidence; the current Godot capsule/controller is an explicit mobile/offline implementation adaptation. Later-client eqoxide dimensions are not labeled Classic/P99 values.

This audit is the pre-Phase-7 gate for deciding whether current EQ Mobile
gameplay/world data may be described as matching the selected
`original_classic_pre_kunark` / P1999 target.

It supplements `docs/foundation-contract.md`. It does not lower that contract's
source-authority requirements.

## Status meanings

- **GREEN** — implementation/data matches the applicable authoritative source
  or is an explicitly accepted documented deviation.
- **YELLOW** — source data is preserved, but classic/P1999-specific review is
  incomplete or conflicting.
- **RED** — current runtime behavior/data differs from the applicable source,
  relies on an unreviewed fixture/default for a real game role, or has a known
  unresolved fidelity discrepancy.
- **EXEMPT** — project-owned development-only fixture that is not represented
  as EverQuest/P1999 content.

Exact-to-PEQ is not automatically P1999-exact. `current_unreviewed_peq` remains
YELLOW until reviewed classic/P1999 evidence promotes or corrects it.

## Audit categories

| Order | Category | Status | Current blocker/evidence |
| --- | --- | --- | --- |
| 1 | Static/non-NPC model transforms | GREEN | Lantern manifest/GLBs are preserved; runtime consumes source position, complete `RotX`/`RotY`/`RotZ` orientation, and all three source scale fields. |
| 2 | NPC spawn/patrol position and elevation | GREEN | Mapped Spawn2 and grid waypoint coordinates remain canonical; terrain checks are diagnostic only. |
| 3 | NPC source heading and rendered facing | GREEN | Source heading vectors map through each zone axis contract; visual offsets are presentation-only. |
| 4 | NPC source size and rendered scale | GREEN | Generic EQEmu source/default/fixed-size resolution drives independent rendered geometry; Halas is a validation fixture. |
| 5 | Player model, scale, collision body, spawn/safe point | RED | Gameplay race is Barbarian while presentation is HLM placeholder; spawn is project-authored. |
| 6 | NPC roster, appearance, patrols, source statistics | YELLOW | Classic-filtered deterministic PEQ snapshot; reviewed P1999 overlay still empty. |
| 7 | Player/NPC movement and controller constants | YELLOW | Mixture of source-backed, conflicting-reference, and project-selected values. |
| 8 | Combat/progression/faction/merchant/item/rewards | YELLOW / EXEMPT | Several systems remain inferred, disabled, or development fixtures. |
| 9 | Environment/water/presentation rules | YELLOW | Several values are runtime presentation settings rather than verified classic data. |

## Category 1 — static/non-NPC model transforms

Primary source evidence:

Reference source archive used for this review:

- `LanternExtractor-main.zip`
- SHA-256:
  `480a1a937016cc8ab588121d8b7f706b4b259d4af477413adc951f475cba569b`
- The repository's `resources/LanternExtractor/` directory contains the
  Lantern executable, PDB, Halas exports, and conversion tooling rather than
  the C# source checkout. The executable runtime gate therefore does not
  require a nonexistent local source tree.

- `LanternExtractor-main.zip:LanternExtractor-main/LanternExtractor/EQ/Wld/Fragments/ObjectInstance.cs`
- `LanternExtractor-main.zip:LanternExtractor-main/LanternExtractor/EQ/Wld/Exporters/ObjectInstanceWriter.cs`
- `LanternExtractor-main.zip:LanternExtractor-main/LanternExtractor/EQ/Wld/Exporters/GltfWriter.cs`
- `resources/OpenEQ-master/converter/wld.py` as independent corroboration

The Halas runtime object manifest is an exact copy of Lantern's exported
placement manifest. Positions and all three scale components are already
preserved.

Lantern retains a complete object-instance rotation and its GLTF exporter
consumes yaw, pitch, and roll. The Halas manifest contains placements with
non-zero `RotZ`, so preserving only yaw is insufficient.

EQ Mobile now reconstructs Lantern's source yaw/pitch/roll basis and changes
that complete orientation into the zone coordinate frame with:

`R_world = M * R_source * M^-1`

where `M` is the zone's signed object-axis mapping. For Halas this correctly
handles the X reflection while retaining source-authored roll.

The Phase 6 foundation test independently proves that yaw-only placements retain
the previously validated Halas heading result and that a non-zero source
`RotZ` survives the reflected coordinate conversion.

Category 1 is GREEN.

## Category 2 — NPC spawn/patrol position and elevation

`ZoneNpcPopulation` preserves the active zone's mapped `Spawn2.position_eq`
for fresh actors and the mapped grid `position_eq` for every canonical patrol
target. Runtime persistence can restore an in-progress actor position, but
terrain diagnostics never rewrite either source-derived positions or restored
runtime state. The current small controller retains horizontal waypoint arrival
and assigns the complete canonical target at arrival.

This is a reusable zone-population rule, not a Halas exception. Future
grounding/path correction belongs to movement/presentation routing and must not
mutate source definitions or canonical patrol destinations. The Category 2
probe independently records terrain agreement as diagnostic evidence; Halas
currently has 242 hits and three no-hit boat/grid-17 points, including Spawn2
10047 (`The_Gwenavyne`).

Source basis: supplied EQEmu review of `zone/spawn2.cpp:Spawn2::Process`,
`zone/waypoints.cpp:AssignWaypoints`, `zone/mob_ai.cpp:NPC::AI_DoMovement`, and
`MobMovementManager::UpdatePathGround`; classified as
`confirmed_source_behavior` for this implementation contract.

Category 2 is GREEN.

## Category 3 — NPC source heading and rendered facing

For a nonnegative source heading, EQ Mobile builds the canonical source-space
vector `[sin(theta), cos(theta), 0]`, where `theta` uses the active zone's
configured `server_heading_units_per_turn`. `ZoneWorldSpace` maps that vector
through the active `server_axis_map`, derives actor yaw from the resulting
horizontal world direction, and persists that canonical world yaw.

Model/root-orientation corrections remain local visual metadata. They never
alter the actor/world heading, saved heading, source Spawn2 heading, or source
waypoint heading. Patrol movement faces its actual horizontal travel direction;
a source waypoint heading is applied only at a paused (`pause_seconds > 0`)
stop when the source value is nonnegative.

The generic foundation runner independently verifies source cardinal vectors,
the Halas axis map, a synthetic non-Halas 1024-unit turn, canonical persistence,
and patrol arrival rules. The Halas real-content startup audit verifies 62
static source-headed actors with a worst world-direction/rendered-facing
alignment of 1.0.

Source basis: supplied EQEmu review of `common/misc_functions.cpp:FixHeading`,
`zone/position.cpp:CalculateHeadingAngleBetweenPositions`,
`zone/waypoints.cpp:UpdateWaypoint`, and `zone/mob_ai.cpp:AI_DoMovement`;
classified as `confirmed_source_behavior` for this implementation contract.

Category 3 is GREEN.

## Category 4 — NPC source size and rendered scale

`NpcSizeContract` keeps `source_size`, `effective_size`, and
`rendered_height` separate. Positive source size wins, otherwise the shared
EQEmu race/gender default-height document is used, with an unknown-race
fallback of 6. EQEmu's fixed LavaDragon (race 49, 5) and Wurm (race 158, 15)
rules are retained before either branch.

Presentation descriptors choose either `normalized_height`, which scales a raw
mesh to effective EQ size, or `native_units`, which applies the
effective/default-size ratio while preserving native mesh proportions.
Nameplates and pick capsules use rendered height. The content service owns the
default-height document; presentation never reads it from disk.

The reusable foundation test covers source overrides, zero fallback,
gender-specific defaults, unknown races, fixed races, both scale modes, and
presentation geometry. `npc_size_fidelity_probe.gd` validates Halas only as a
fixture: all 68 source types retain the 61×7, 5×6, 2×3 source-size distribution
and both sled dogs render at their explicit size of 3. The imported ferry's raw
height is 10.166 units against its default size of 6, so it is explicitly
classified as a generic `native_units` descriptor rather than normalized as a
character mesh.

Source basis: supplied EQEmu review of
`common/races.cpp:GetRaceGenderDefaultHeight` and `zone/npc.cpp`; classified
as `confirmed_source_behavior` for this implementation contract.

Category 4 is GREEN.

## Promotion rule

A category becomes GREEN only when:

1. its source authority is documented;
2. source/runtime comparisons are automated where possible;
3. transforms/formulas have executable tests;
4. classic/P1999-specific values have reviewed evidence rather than merely
   current PEQ provenance; and
5. intentional mobile/offline differences are recorded as deviations.

The final pre-Phase-7 gate will be:

~~~bash
python3 tools/classic_p1999_fidelity_audit.py --require-all-green
~~~

It is expected to fail until every non-exempt category is GREEN.
