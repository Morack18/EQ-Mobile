# Phase 6 — Zone Runtime Contract

Phase 6 turns Halas into the first instance of a generic EQ Mobile zone
architecture. Runtime systems must not require Halas-specific gameplay logic.

## Definition versus runtime state

A `ZoneDefinition` is immutable content. It owns:

- stable `eqm:zone:*` identity;
- geometry and static-object references;
- world-space conversion contract;
- bounds and player safe point;
- NPC population reference;
- world-object/interactable reference;
- transition reference;
- environment presentation settings.

`ZoneRuntimeState` is mutable local-save state. It owns:

- per-spawn-point occupant selection;
- per-spawn-point respawn state;
- spawn controller/patrol runtime data needed across unload/reload;
- interactable-world-object state such as an opened door and remaining
  close timer.

A spawned NPC remains a transient `GameplayEntity`. Its definition identity
does not replace the stable spawn-point identity.

## Spawn ownership

The neutral model follows the source distinction visible in EQEmu:

`SpawnPoint -> SpawnGroup -> candidate NpcArchetype -> runtime actor`

The spawn point owns location, heading, grid reference, respawn timing and
current occupant state. A spawn group owns weighted candidates and group-level
spawn behavior. Candidate selection must eventually use the canonical
`SimulationRng`; once selected, the choice belongs to zone runtime state so a
zone unload/reload does not silently reroll a living occupant.

Respawn countdowns must use the canonical simulation timer framework. The
`respawn_remaining` value in `ZoneRuntimeState` is a serialization boundary,
not a second clock.

`ZoneSpawnResolver` is the generic definition-resolution boundary. During the
Halas migration it deliberately reproduces the previous presentation roster
selection (`spawn2_id % total_weight`) so architectural work does not silently
change visible content. Once a SpawnPoint has a selected definition, reload
must preserve that valid selection rather than reroll it. A later reviewed
slice may move first-selection randomness to canonical `SimulationRng`.

## World objects and doors

Doors are one specialization of the generic world-object/interactable
architecture. A definition may eventually contain:

- model/appearance;
- position and heading;
- initial open/closed state;
- open behavior;
- key/lock requirements;
- trigger relationships;
- automatic close timing;
- destination-zone information.

No authentic Halas door records are enabled by this contract alone. The
checked-in Halas world-object dataset remains empty until source rows are
classic-filtered and reviewed.

## Environment

Environment settings are zone data, not `main.gd` constants. Halas currently
records the presentation values that EQ Mobile already uses, explicitly marked
as current-runtime evidence rather than claimed classic source values.

Future import work can add source-backed safe coordinates, fog, sky, weather,
gravity, clipping and similar zone metadata without changing the loader.

## Transitions

`ZoneTransitionRequest` is the runtime handoff contract. It identifies:

- source zone;
- target zone;
- target entry reference and/or explicit target position;
- optional target heading;
- transition reason.

Phase 6 establishes the contract before implementing live zone-line traversal.

## Source basis

The structural split is informed by:

- EQEmu `zone/spawn2.h` and `zone/spawn2.cpp`;
- EQEmu `zone/spawngroup.h` and `zone/spawngroup.cpp`;
- EQEmu `zone/zone_save_state.cpp`;
- EQEmu generated repositories for `spawn2`, `spawngroup`, `spawnentry`,
  `grid`, `grid_entries`, `doors`, `zone_points`, `object`, and `zone`.

EQ Mobile reimplements these concepts as offline Godot-native data/state. It
does not port EQEmu server/database infrastructure.

## Foundation gate

Adding zone #2 must not require another `Main` implementation.

The remaining Phase 6 work is therefore to:

1. route startup content through `ZoneDefinitionLoader`;
2. make world geometry, props, environment and coordinate transforms consume
   ZoneDefinition data rather than Halas constants;
3. replace the Halas-only population/adapter boundary with a generic
   zone-spawn presentation/runtime bridge;
4. persist `ZoneRuntimeState` per zone;
5. support unload/reload through one runtime zone host;
6. extend the existing zone pipeline validator to enforce these contracts;
7. import/review doors and zone transitions separately from the architecture.
## Spawn selection authority

`ZoneSpawnResolver` is the generic definition-resolution boundary. During the
Halas migration it deliberately reproduces the previous presentation roster
selection (`spawn2_id % total_weight`) so architectural work does not silently
change visible content.

Once a SpawnPoint has a valid selected definition, zone reload must preserve
that selection rather than reroll it. A later reviewed slice may move initial
selection randomness to canonical `SimulationRng`.

Presentation code must not independently resolve SpawnGroup candidates.
`ZoneSpawnResolver` is the single authority for selected NPC definition
identity. A zone presentation may consume the resolved SpawnPoint record and
build a view for it, but may not reroll or replace that selection.
## Patrol runtime ownership

`ZoneRuntimeState` owns live SpawnPoint patrol state. Runtime state includes
the current grid identity, patrol waypoint index, waypoint pause remaining,
world-space position, and world-space heading.

During the Halas migration, `HalasNpcPopulation` remains the compatibility
movement controller and visual presentation. It must read the canonical patrol
values from `ZoneRuntimeState` before movement and write the resulting pose and
patrol state back afterward. Its local actor patrol fields are compatibility
mirrors only and are not the persistence authority.

Authored grid waypoints remain content definition data. Runtime location,
waypoint progress, and pause progress are mutable zone state and must survive
zone unload/reload.
## Zone persistence staging

Save schema 5 stores `ZoneStateStore.snapshot()` beside the simulation
snapshot. Schema-4 saves migrate by wrapping their single `zone_state` in
the store under the saved active `zone_key`. Older saves migrate with an
empty runtime snapshot for their saved zone; spawn resolution then seeds
current definition defaults.

Loading is deliberately staged. The save envelope is read and migrated once.
Zone runtime state restores before `ZoneSpawnResolver` runs, so persisted NPC
selection, patrol progress, position, and world-object state are available
while the zone is constructed. The simulation snapshot restores only after
runtime actors have been created, because `Simulation.restore_snapshot()`
restores existing entity instances rather than constructing missing ones.

Offline elapsed-time policy remains `freeze`; adding zone persistence does not
create a second gameplay clock.
## Per-zone unload/reload state

`ZoneStateStore` owns dormant runtime snapshots keyed by stable zone key.
Unloading a zone captures its `ZoneRuntimeState` into the store before live
zone nodes/state are discarded. Reloading constructs a fresh
`ZoneRuntimeState` and restores the stored snapshot before spawn resolution or
presentation construction.

Zone snapshots are isolated. Spawn occupancy, selected NPC definition, patrol
progress, respawn state, and world-object state from one zone must never leak
into another zone.

The store validates the complete payload before replacing its current state,
so malformed persisted data cannot partially overwrite otherwise-valid zone
snapshots.

The store is now both the generic in-memory unload/reload boundary and the
schema-5 disk-persistence boundary. `zone_key` remains the active-zone marker;
dormant zones remain isolated under `zone_states` until a transition contract
explicitly activates one of them.
## ZoneHost lifecycle boundary

`ZoneHost` is the generic owner of active-zone lifecycle state. It owns the
active zone definition, active `ZoneRuntimeState`, `ZoneStateStore`,
`ZoneSpawnResolver`, and the resolved spawn-definition set.

Preparing a zone creates a fresh active runtime and restores any dormant
snapshot already held by the state store. Unloading captures the active runtime
before clearing active-zone references. Reloading therefore reconstructs
runtime state independently of presentation nodes.

During the migration, `main.gd` keeps compatibility aliases for the host-owned
runtime/store/resolver and still constructs geometry, world objects, Halas NPC
presentation, player nodes, and UI. Those presentation responsibilities move
behind the zone boundary in later slices; they are deliberately not part of
this first lifecycle extraction.
## Active-zone presentation lifetime

`ZonePresentationHost` owns one `ActiveZonePresentation` root for the prepared active zone.
Zone geometry, zone-specific environment/light nodes, fallback terrain, static
object placements, and their descendant collision nodes attach beneath this
root.

Unloading a zone captures its `ZoneRuntimeState`, immediately detaches the
presentation root from the scene tree, queues that root for deletion, and only
then clears the active-zone lifecycle references. This prevents geometry or
collision from the previous zone remaining active during a zone switch.

Presentation caches such as imported object scenes, baked reflected meshes,
two-sided material copies, shared prop collision shapes, prop counters, and
authored-water triangles are build-local compatibility state in `main.gd`.
They reset whenever a fresh active presentation root is created and are not
part of `ZoneRuntimeState` or `ZoneStateStore`.

The zone NPC population is also a child of this root. Player presentation,
camera, HUD, and other persistent application UI remain outside it.
## Zone-owned NPC teardown

Zone NPC view nodes are transient presentation. Their gameplay actors also use
stable transient runtime IDs, so destroying only the view nodes is
insufficient: those IDs must be structurally released from `Simulation` before
the same zone can construct them again.

`Simulation.remove_entity()` remains the gameplay removal operation. It marks
an actor `REMOVED`, performs target/timer/effect cleanup, emits `DESPAWN`, and
retains the entity tombstone.

`Simulation.release_entity()` is the structural lifetime operation used by zone
unload. It performs equivalent cleanup when necessary, suppresses `DESPAWN` by
default, purges queued events involving the released transient identity,
removes the runtime ID from `Simulation.entities`, and clears death-reward
dedupe state for that runtime identity.

The active-zone unload order is:

1. Capture `ZoneRuntimeState` into `ZoneStateStore`.
2. Clear NPC selection and interactions while views are still valid.
3. Unbind every zone-owned entity from `EntityViewRegistry`.
4. Release each zone-owned transient entity from `Simulation`.
5. Clear NPC presentation aliases and runtime-ID maps.
6. Let `ZonePresentationHost` detach and delete `ActiveZonePresentation`.

`ZoneHost` remains presentation-agnostic. `main.gd` coordinates the domain
`ZoneHost` and presentation-layer `ZonePresentationHost`, ensuring transient
domain actors and view bindings are released before the zone presentation is
detached.
## Executable zone transition staging

The first executable zone-transition slice uses a project-original geometry-empty
fixture zone, `eqm:zone:phase6_transition_fixture`. It is explicitly test
content and is not presented as authentic EverQuest geography or behavior.

A coordinate-based `ZoneTransitionRequest` is executed in this order:

1. Validate the request source/target.
2. Load and validate the target `ZoneDefinition`.
3. Stage a fresh `ContentService` for the target while the current zone remains
   active.
4. Validate the target `ZoneWorldSpace`.
5. Sync current presentation poses into domain state.
6. Capture and unload the active zone.
7. Activate the target definition/runtime through `ZoneHost`.
8. Resolve SpawnPoints and construct a new `ActiveZonePresentation`.
9. Rebuild target world/static objects/NPC presentation.
10. Reposition the persistent player view/domain actor at the requested
    coordinate while updating its death-respawn spawn to the new zone's
    configured `player_spawn`.

Target content is staged before teardown so a malformed target cannot destroy
the currently playable zone.

The Phase 6 smoke test performs `Halas -> geometry-empty fixture -> Halas` and verifies
that Halas transient NPC IDs can be reconstructed, Halas runtime state is
restored, fixture state becomes dormant in `ZoneStateStore`, the persistent
player survives both transitions, and the canonical Halas static-object counts
return after reload.

Entry-reference and explicit target-heading execution remain intentionally
unimplemented in this slice. `ZoneTransitionRequest` can represent them, but
the executor rejects unsupported placement semantics rather than silently
inventing behavior.
The fixture still declares `geometry_scene` because that field is mandatory in
the generic zone-definition contract. Its scene is a project-authored empty
`Node3D` at
`res://scenes/fixtures/phase6_transition_fixture_geometry.tscn`; it contains no
imported EverQuest geometry or collision.
## Domain / presentation host separation

`ZoneHost` is a domain/runtime coordinator and must not depend on Godot scene
nodes. It owns the active `ZoneDefinition`, `ZoneRuntimeState`,
`ZoneStateStore`, `ZoneSpawnResolver`, and resolved spawn definitions.

`ZonePresentationHost` is the presentation-layer lifetime owner. It is a
`Node3D` and owns the current `ActiveZonePresentation` scene subtree.

`main.gd` is the orchestration boundary between them. During unload it captures
domain state, releases transient actor/view bindings, clears
`ZonePresentationHost`, and then clears `ZoneHost`. During load it prepares the
domain host first, then creates the presentation subtree.

This preserves the Phase 3 rule that domain logic does not depend on UI or
scene-tree nodes.
