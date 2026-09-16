# Reference discoveries

This is the durable index of implementation-relevant findings from the local
reference repositories. Record source paths and the Godot adaptation, not a
copy of reference implementation code.

## Movement and size — EQEmu

- `resources/EQEmu-master/zone/client.cpp` constructs a standard client with
  run speed `0.7`.
- `resources/EQEmu-master/zone/mob.cpp` resolves that value as
  `base_runspeed = runspeed * 40`, giving a classic unmodified base rate of
  `28`. EQ Mobile uses 28 native EQ-sized world units per second for player
  run movement.
- `resources/EQEmu-master/common/races.cpp:GetRaceGenderDefaultHeight` is the
  authority for native model-size fallback. `resources/EQEmu-master/zone/npc.cpp`
  assigns that default directly when an NPC's database `size` is non-positive;
  otherwise the database value itself is the actor's native world height.
  Halas currently uses Human 6, Barbarian 7, Wolf 4, Halas ferry 6, and Halas
  citizen 7.
- `resources/EQEmu-master/zone/npc.cpp` confirms NPC initialization applies
  that race/gender default when source size is non-positive.

## Client rendering and movement — eqoxide

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
