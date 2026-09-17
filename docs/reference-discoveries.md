# Reference discoveries

This is the durable index of implementation-relevant findings from the local
reference repositories. Record source paths and the Godot adaptation, not a
copy of reference implementation code.

## Movement and size — EQEmu

- `resources/EQEmu-master/zone/client.cpp` constructs a standard client with
  run speed `0.7`.
- `resources/EQEmu-master/zone/mob.cpp` resolves that value as
  `base_runspeed = runspeed * 40`, giving `28` for client-update
  animation/wire semantics. `resources/eqoxide-main/crates/eqoxide-net/src/action_loop.rs`
  maps its physical 44 u/s controller rate back to that value, so EQ Mobile
  uses 44 u/s for physical player movement rather than treating 28 as a world
  speed.
- `resources/EQEmu-master/common/races.cpp:GetRaceGenderDefaultHeight` is the
  authority for native model-size fallback. `resources/EQEmu-master/zone/npc.cpp`
  assigns that default directly when an NPC's database `size` is non-positive;
  otherwise the database value itself is the actor's native world height.
  Halas currently uses Human 6, Barbarian 7, Wolf 4, Halas ferry 6, and Halas
  citizen 7.
- `resources/EQEmu-master/zone/npc.cpp` confirms NPC initialization applies
  that race/gender default when source size is non-positive.

## Client rendering and movement — eqoxide

- `resources/eqoxide-main/crates/eqoxide-core/src/physics.rs` defines the
  local controller's physical `RUN_SPEED` as 44 world units/s and derives walk
  as `44 * (0.3 / 0.7)` (about 18.857), with a 20 u/s walk/run animation
  threshold. `crates/eqoxide-net/src/action_loop.rs` maps physical 44 u/s back
  to the EQ client-update animation value 28, so EQ Mobile does not treat
  `0.7 * 40 = 28` as a physical world speed. The same snapshot's
  `src/app.rs` direct manual-drive path uses 35 u/s; EQ Mobile selects that
  value for its corresponding two-stick controller after Android-feel testing
  found 44 u/s too fast. This remains an explicit eqoxide inconsistency, not a
  claim that one universal physical rate is proven.
- `resources/eqoxide-main/src/movement.rs` uses `GROUND_SNAP_TOL = 0.5` and
  `SKIN = 0.05`; EQ Mobile adapts these as Godot floor-snap length and safe
  margin while preserving its existing bounded two-unit step-up. Its small
  grounded downward bias remains a Jolt/Godot triangle-seam stability
  adaptation, not a claimed native client rule.
- `resources/eqoxide-main/src/camera_state.rs` follows with
  `1 - exp(-FOLLOW_RATE * dt)` at `FOLLOW_RATE = 5.0`. EQ Mobile initially
  used that frame-rate-independent follow form, but its third-person mobile
  camera now anchors its orbit pivot directly to the player and aims at the
  player visual center, per the product requirement that the player remain
  centered on screen. Physics interpolation remains the presentation smoothing
  mechanism; camera collision still retracts the camera before aiming.
- The imported `assets/imported/halas/characters/hlm_s0_h0.glb` provides
  `idle`, `walk`, `attack`, `death`, `swimming`, and `treading`, but no run
  clip. Resolved motion above the 20 u/s threshold therefore keeps the walk
  clip as a documented temporary fallback rather than faking run by changing
  animation playback speed.

- `resources/eqoxide-main/README.md` identifies the most relevant reference
  areas: zone terrain/object placement, per-race/gender skinned models,
  equipment material swaps, relative race sizes from
  `GetRaceGenderDefaultHeight`, collision/pathfinding, and smooth NPC
  movement.
- Before implementing a client-facing system, inspect the relevant eqoxide
  document/module first (for example `docs/collision-system.md`,
  `docs/character-models.md`, or `docs/zone-rendering.md`) and cross-check
  gameplay formula/authority with EQEmu.
- EQ Mobile adapts behavior into offline Godot-native systems. It does not
  reproduce eqoxide's network, HTTP, asset-server, or EQEmu-server architecture.
- `resources/eqoxide-main/docs/collision-system.md` confirms that one zone
  triangle-collision representation should serve grounding, movement gating,
  and camera obstruction. EQ Mobile now uses the imported zone collision for
  player `CharacterBody3D` movement/grounding and raycasts the third-person
  camera line, pulling the camera in before a wall to avoid clipping.
- The same collision reference distinguishes walkable floor/low height changes
  from chest-height obstructions. EQ Mobile adapts that with a grounded Godot
  controller: a 60-degree maximum walkable slope, floor snapping, and
  collide-and-slide remain active, while steeper terrain stays blocking.
- `resources/eqoxide-main/src/movement.rs` and
  `crates/eqoxide-core/src/physics.rs` define native `STEP_UP = 2.0` EQ units.
  A blocked grounded character is raised by that amount only when the raised
  sweep has headroom/travel clearance and lands on valid floor within the step
  band; a taller wall remains blocking. EQ Mobile implements this bounded
  step-offset rule in its Godot `CharacterBody3D` controller.
- `resources/eqoxide-main/crates/eqoxide-renderer/src/models.rs` confirms that
  EQ zone world units are feet and the client must normalize each skinned
  character rig individually: `mesh_scale = target_height / measured_model_height`,
  then lift its feet to the spawn elevation. It uses the same EQEmu default
  heights for playable races (Human 6, Barbarian/HLM 7) and a Wolf target of 4.
  Lantern's raw GLB dimensions are therefore never a gameplay scale authority.
  EQ Mobile selects idle before measuring each imported model's loaded bounds,
  normalizes it to `npc_types.size` (or the EQEmu fallback), and grounds it at
  the server position. The HLM player uses that exact same 7-foot path.
- `resources/eqoxide-main/crates/eqoxide-core/src/physics.rs` defines the
  reference client wall-collision radius as `1.0` EQ unit. EQ Mobile's player
  capsule uses that radius with a 7-unit HLM standing span, so the physical
  player is no longer a tiny body beneath a correctly scaled character model.
- `resources/eqoxide-main/crates/eqoxide-renderer/src/camera.rs:entity_model_matrix_heading`
  establishes that exported glTF character models face local `+X`; EQ headings
  are `0=north`, counter-clockwise. `resources/eqoxide-main/src/movement.rs`
  gives the matching motion basis: `forward = (-sin(heading), cos(heading))`.
  EQ Mobile keeps Godot `Node3D` local `-Z` as the movement-facing axis (so
  `look_at()` is authoritative), rotates each character visual `+90°` around
  Y beneath that node, and converts a static EQ heading to Godot yaw as
  `π/2 - heading * TAU/512`. This aligns player motion, NPC patrol motion, and
  source spawn/waypoint headings without baking a correction into the models.
- `resources/eqoxide-main/crates/eqoxide-nav/src/collision.rs:Collision::build`
  flattens **both** zone terrain and every transformed placed-object mesh into
  one triangle-query world. `resources/OpenEQ-master/Engine/EngineCore.cs`
  independently builds its physics octree from collidable fixed model meshes.
  EQ Mobile now creates exact triangle collision from each imported zone mesh
  and each placed static-prop mesh. Terrain uses layer 1 for grounding/spawn
  validation; props use layer 2 so they block player movement and camera rays
  without becoming false NPC terrain surfaces. Dynamic NPC visual meshes are
  not collision geometry in this reference model.
- `resources/eqoxide-main/src/movement.rs:manual_wish` defines the EQ-facing
  basis as `(-sin(heading), cos(heading))` in east/north for a heading in the
  0–512 source-unit turn. The Lantern HLF character export is 180° mirrored
  relative to the other shipped Halas families: Skoni (HLF, spawn2 `10041`)
  validates the per-family correction, while HLM/Barbarian/Human/Wolf retain
  the standard conversion. `HalasNpcPopulation` performs a startup audit over
  every non-patrolling actor, asserting that its source spawn heading and
  rendered model-facing direction align; patrol stops use the same conversion.

## Recording rule

- `resources/eqoxide-main/crates/eqoxide-core/src/physics.rs` defines client
  gravity as `120` EQ units/s² and a grounded jump impulse of `31` EQ units/s
  (the source documents an approximately four-unit jump peak).
  `resources/eqoxide-main/src/movement.rs` caps falling speed at `128` units/s.
  EQ Mobile now uses those values directly in its native-unit player controller,
  rather than Godot's project gravity.
- The same `movement.rs` suspends gravity in water, uses `30` units/s upward
  buoyancy, and floats an idle swimmer two units under the water surface.
  It allows camera-pitched forward/back movement to dive or rise and uses the
  jump input as continuous swim-up. EQ Mobile follows those movement values.
  Exact client water inclusion comes from eqoxide's bounded `.wtr` `RegionMap`
  (`crates/eqoxide-nav/src/collision.rs`). No Halas `.wtr` file is present in
  the supplied resources, so the current implementation deliberately uses the
  exported `t75_agua1` Halas water-surface triangles as an authored fallback
  (while excluding deeper `d_halaswater1` geometry from land collision);
  it is not a claim of exact original water-region boundaries or depth.
- `resources/eqoxide-main/src/app.rs` routes forward/back through camera pitch
  while swimming, uses a `35` EQ-unit/s swim movement rate, and permits the
  controller's bounded step-up to haul a swimmer over a shore lip. Its action
  priority renders the active swim stroke whenever horizontal **or vertical**
  travel occurs and treads water when stationary. `tools/src/main.rs` maps the
  original source clips as `L06`/`L09` swim and `L08`/`P07` tread-water idle.
  EQ Mobile mirrors those controls for its left-move/right-look touch layout
  and requests clips named `swimming` and `treading` from its HLM asset.
- `resources/eqoxide-main/crates/eqoxide-core/src/game_state.rs` treats a
  selected target as a stable spawn ID and clears target-derived state when the
  entity departs. `eqoxide-ipc/src/lib.rs` exposes a "Target nearest" HUD
  command. EQ Mobile's first real Halas target layer preserves this contract by
  selecting from the loaded source roster via `spawn2_id` (rather than a node
  name or temporary visual instance) and displaying the matching source name
  and level. Mobile selection ray-picks a dedicated `Area3D` interaction proxy,
  which is not part of terrain/object collision and therefore does not make NPC
  visuals into physical world blockers. Combat remains deliberately disabled for
  these targets until their authoritative stat/loot/faction records are imported.

For each future discovery, add: reference repository/path, concise observed
behavior or formula, the Godot adaptation, and any known deviation or open
question.

## Player combat foundation

- `resources/EQEmu-master/common/classes.h:26-121` defines Warrior as numeric
  class ID `1`. EQ Mobile persists only `class_id` and derives its display name,
  attack profile, and learned abilities from static `data/player_classes.json`.
- `resources/EQEmu-master/zone/client_process.cpp:397-455` shows normal melee
  as a latched auto-attack loop: a ready timer validates range, line of sight,
  and facing before one attack round. `zone/attack.cpp:3491-3592` supplies the
  ordinary unarmed fallback delay of `35` tenths (3.5 seconds). EQ Mobile uses
  that cadence and exactly one swing per ready round; haste, dual wield, and
  extra swings are intentionally deferred.
- `resources/EQEmu-master/zone/aggro.cpp:1113-1250` supplies the ordinary
  `CombatRange` small-body branch: effective size floors at 8 and range squared
  is `size² × 4`, yielding 256 / a 16-unit horizontal radius. `zone/mob.cpp:
  7597-7615` supplies the roughly ±56.25-degree facing cone. EQ Mobile adapts
  those two bounds and uses its authored world collision ray for line of sight.
- `resources/EQEmu-master/zone/special_attacks.cpp:325-622`,
  `common/features.h:119-142`, and `common/ptimer.*` establish the useful shape
  of a melee combat ability: eligibility-gated, independently timed, and
  persistent across reload. EQ Mobile's original `Training Strike` is a
  Warrior-only level-1 fixture ability with a five-second wall-clock
  `combat_ability` cooldown. It does not consume mana/endurance or reset the
  primary auto-attack timer.
- Existing Training Spark damage stays explicitly deterministic behind
  `_resolve_fixture_melee_damage()`. The current sources' complete hit,
  avoidance, mitigation, skills, and item stack is not treated as a safe
  classic-era formula until corresponding player/NPC data is imported.

## Imported NPC interaction safety

- ProjectEQ's source relationship is `spawn2 → spawngroup → spawnentry →
  npc_types`; imported Halas actors retain their stable `spawn2_id` and now
  carry their raw NPC type references for faction, merchant, loot, HP, AC,
  damage, and attack delay. `npc_types.attack_delay` is an EQ tenths-style raw
  value (EQEmu `zone/zonedb.cpp:1897` converts it to milliseconds by ×100),
  but remains non-operative until reviewed combat is deliberately enabled.
- `npc_types.npc_faction_id` joins through `npc_faction.primaryfaction`; it is
  not itself an answer to player hostility. EQEmu reaction also needs player
  race/class/deity and personal faction. The Halas overlay has no reviewed
  classic gameplay corrections, so faction zero is shown as indifferent and
  nonzero factions as unresolved; imported combat stays disabled.
- `merchant_id` and `loottable_id` are displayed as candidate/reference-only
  interaction states. They do not authorize merchant transactions or random
  loot rolls until their item data and classic correctness are reviewed.
