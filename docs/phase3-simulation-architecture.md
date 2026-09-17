# Phase 3 — Simulation Architecture

## Boundary contract

Phase 3 establishes three explicit layers.

- **Domain (`scripts/domain/`)** owns gameplay entities, lifecycle transitions, combat validation/resolution, rewards, inventory mutation, progression, faction standing, simple NPC behavior, and typed gameplay events. Domain code contains no HUD, camera, scene-node, Halas population, or file-I/O dependency.
- **Presentation (`scripts/presentation/` plus scene adapters)** owns Node3D/view bindings, selection/highlighting, animation, line-of-sight queries against the rendered world, and translation of input into domain commands. A presentation node is never the canonical gameplay entity.
- **Services (`scripts/services/`)** own gameplay content I/O, save-file I/O/migration, authoritative simulation time, and simulation randomness.

`main.gd` is the composition root: it constructs services and domain systems, builds the world/views, wires input to commands, forwards external presentation facts such as a line-of-sight result, applies domain events to views, and coordinates autosave. It does not calculate damage, XP thresholds, inventory mutation, faction standing, death/respawn transitions, or save serialization.

## Entity identity and lifecycle

Every runtime participant uses `GameplayEntity`, with a stable runtime `entity_id` independent of any Node3D and a separate stable content `definition_id`. Runtime state is copied from content definitions and then evolves independently of the source definition.

Lifecycle transitions are explicit:

`created -> spawned -> active -> dying -> dead -> respawning -> spawned -> active`

`removed` is a permanent terminal state and is distinct from temporary death. Death can begin only from `active`, so a life can emit one death transition. The simulation keys reward completion by `entity_id + life_number`, preventing duplicate loot or XP from repeated downstream processing.

## Events

`GameplayEvent` defines structured events for attack requested/performed, damage, heal, death, XP awarded, item gained/lost, level changed, faction changed, spawn, and despawn. Events carry stable entity IDs and domain data only. Presentation converts them to status text, animation, visibility, or other UI behavior.

## Time semantics

`SimulationClock` is the only authoritative elapsed-time source for combat cooldowns and lifecycle/respawn timing. Tests advance it manually; gameplay never waits on wall-clock time.

Version-2 saves persist **remaining simulation durations** for cooldowns, dying, and respawn timers. Closing the app therefore pauses those timers. Real-world Unix time is used only once when migrating the legacy save format whose ability cooldowns were stored as Unix deadlines. Any future mechanic that intentionally advances while offline must be modeled separately rather than reusing simulation elapsed time implicitly.

## Randomness semantics

`SimulationRng` is the single simulation RNG abstraction. Its seed and generator state are serializable. Tests provide fixed seeds. The same initial state, elapsed-time advances, commands, and seed therefore reproduce the same stochastic damage sequence.

The existing Halas spawn-roster selection based on `spawn2_id % total_weight` remains explicitly deterministic content selection; it is not a simulation random roll.

## Content and provenance

`ContentService` is the gameplay JSON repository boundary. Zone, item, class/ability, faction, merchant, and NPC datasets are loaded once and exposed by stable keys/references. `HalasNpcPopulation` receives already-loaded NPC content and remains a presentation adapter.

Imported Halas source HP, AC, damage, delay, loot, faction, and merchant fields remain provenance metadata. `HalasEntityAdapter` creates imported runtime entities with combat disabled by default. The Phase 3 foundation test uses an explicit project-owned safe test override only to prove that an imported NPC can traverse the same generic combat/lifecycle pipeline; it never promotes unreviewed PEQ values to authoritative gameplay data.

## Persistence

`PersistenceService` is the only owner of `user://offline_slice_save.json`. Save schema version 2 stores a simulation snapshot instead of reconstructing authoritative gameplay fields in `main.gd`. It centralizes JSON validation, invalid/corrupt handling, zone checks, and migration from the former flat save structure.

## Foundation gate proof

`tests/run_phase3_tests.gd` runs headlessly and covers lifecycle transitions, seeded RNG reproducibility, attack/damage/death ordering, exactly-once death/XP/item rewards, progression thresholds, inventory mutation, persistence serialization round-trip, manual-clock cooldowns, deterministic replay, and the fixture/imported-NPC shared factory/combat path.

The gate specifically instantiates both the Training Spark and a real definition from `halas_npcs.json` through `EntityFactory` as `GameplayEntity`, kills both through `Simulation.request_attack`, verifies the common death event path, and verifies Training Spark generic respawn. Imported PEQ combat remains disabled outside that explicit safe architecture-test override.