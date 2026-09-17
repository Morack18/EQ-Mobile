# Phase 1 — World Mathematics

`scripts/eq_world_space.gd` is the only shared implementation authority for
native EQ unit constants and coordinate conversion. Zone-specific contracts are
declared in the zone JSON and must be validated before a zone is accepted.

## Canonical unit and precision

- One Godot world unit equals one native EQ world unit after that asset's
  declared import compensation. Halas geometry uses `geometry_scale: 10.0`
  solely to cancel its exported `0.1` root scale.
- Positions are persisted as full JSON floating-point coordinates. Do not round
  gameplay positions; `0.001` world units is the comparison precision for
  deterministic conversion tests.
- Character height, collision radius, gravity, jump velocity, fall cap, and
  manual movement speed are centralized in `EqWorldSpace` or named game rules.
  Rendering-scale normalization never changes a character's world-space body.

## Halas coordinate contract

Halas uses two declared input conventions; they must not be conflated.

| Input | Godot world conversion | Consumer |
| --- | --- | --- |
| PEQ/EQEmu server `[x, y, elevation]` | `[-y, elevation, x]` | spawns, patrols, server-position audits |
| Lantern prop `[x, y, z]` | `[-x, y, z]` | object placements |
| EQ heading `0..512` | `π/2 - heading × τ/512` | static spawn/patrol facing |
| Lantern prop heading degrees | negated Godot yaw | object placements |

The server transform was chosen by the collision audit against authored Halas
terrain; it is not a universal assumption. The prop transform is separately
defined because Lantern's Halas zone root mirrors X.

Axis transforms are encoded as signed one-based component maps in zone data:
`[-2, 3, 1]` means `[-source.y, source.elevation, source.x]`. The generic
`EqWorldSpace.map_position()` applies those maps, so a new calibration provides
data rather than duplicating coordinate arithmetic.

## Shared physics assumptions

- Terrain and prop collision are built in the same transformed Godot world
  space as actors and camera rays.
- Player grounding, slope-stop, floor snap, bounded step-up, and camera
  obstruction all use that collision world. A camera must never apply its own
  coordinate conversion.
- Native values currently centralized from the documented source-informed
  movement pass: gravity `120`, jump velocity `31`, fall cap `128`, manual
  mobile movement `35`, collision radius `1`.
- The existing `60°` floor angle, snap/margin values, and `2`-unit step rule
  are named Godot adaptations; see the deviation registry where applicable.

## Required tests for every zone

1. Add the source-to-world transform and asset compensation to that zone's
   `world_space_contract` metadata.
2. Run pure conversion assertions in `EqWorldSpace.run_contract_tests()`.
3. Ray-test all visible static spawns and retained patrol points against the
   zone's terrain collision. A horizontal transform must win clearly; terrain
   snap may correct only a small documented vertical discrepancy.
4. Audit source heading against rendered forward direction for static actors.
5. Validate prop positions/headings and camera collision in the same world
   space before accepting the zone.

No second zone may copy Halas axis math without a new calibration result.
