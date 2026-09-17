Markdown
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

Version-2 saves persist **remaining simulation durations** for cooldowns, dying, and respawn timers. Closing the app therefore pauses those timers. Real-world Unix time is used only when migrating the legacy save format whose ability cooldowns were stored as Unix deadlines. Any future mechanic that intentionally advances while offline must be modeled separately rather than reusing simulation elapsed time implicitly.

This pause-on-close behavior is recorded as `DEV-010` in `docs/deviation-registry.md`.

## Randomness semantics

`SimulationRng` is the single simulation RNG abstraction. Its seed and generator state are serializable. Tests provide fixed seeds. The same initial state, elapsed-time advances, commands, and seed therefore reproduce the same stochastic damage sequence.

The persistence boundary encodes the RNG's 64-bit seed and generator state as decimal strings inside schema-version-2 JSON and decodes them back to integers before restoring the simulation. This preserves exact deterministic continuation across actual save-file I/O while remaining able to read existing schema-version-2 envelopes whose RNG fields are numeric.

The existing Halas spawn-roster selection based on `spawn2_id % total_weight` remains explicitly deterministic content selection; it is not a simulation random roll.

## Content and provenance

`ContentService` is the gameplay JSON repository boundary. Zone, item, class/ability, faction, merchant, and NPC datasets are loaded once and exposed by stable keys/references. `HalasNpcPopulation` receives already-loaded NPC content and remains a presentation adapter.

Imported Halas source HP, AC, damage, delay, loot, faction, and merchant fields remain provenance metadata. `HalasEntityAdapter` creates imported runtime entities with combat disabled by default. The Phase 3 foundation test uses an explicit project-owned safe test override only to prove that an imported NPC can traverse the same generic combat/lifecycle pipeline; it never promotes unreviewed PEQ values to authoritative gameplay data.

The foundation gate resolves its imported NPC through the actual typed relationship chain:

`SpawnPoint -> SpawnGroup -> candidate npc_ref -> NpcArchetype`

The test deliberately selects a spawn-referenced NPC for which source HP, damage, and loot provenance exists, then proves the normal runtime definition still has combat disabled, project-safe neutral health, no damage profile, and no rewards. Its test-only combat configuration supplies project-owned fixture health/hostility and still does not copy source PEQ HP, damage, or loot.

## Persistence

`PersistenceService` is the only owner of the production `user://offline_slice_save.json` path. Save schema version 2 stores a simulation snapshot instead of reconstructing authoritative gameplay fields in `main.gd`. It centralizes JSON validation, invalid/corrupt handling, zone checks, migration from the former flat save structure, and deterministic RNG persistence.

Phase 3 tests use separate Phase 3-only temporary `user://` paths. They exercise `save_simulation()` and `load_simulation()` rather than only serialization helpers and clean the temporary files before and after use.

## Foundation implementation record

### Selected era profile

The project default remains:

`original_classic_pre_kunark`

Phase 3 is an architecture phase. Passing this foundation gate does **not** claim that current combat, progression, faction, range, facing, health, damage, reward, or timing constants are authenticated original-classic EverQuest numerical behavior.

### Authority sources

The Phase 3 authority boundary is:

- `docs/foundation-contract.md` governs canonical era, source authority, evidence labels, provenance, and deviations.
- `docs/identity-contract.md` governs stable definitions, imported source IDs, runtime occurrences, and typed cross-dataset references.
- Gameplay rules eventually requiring classic authority must follow the foundation contract's priority of local `resources/EQEmu-master/` plus classic-specific evidence. Current configurable/default behavior is not classic authority by itself.
- `data/halas_npcs.json` supplies imported Halas structural relationships. Its metadata identifies PEQ `spawn2`, `spawnentry`, `npc_types`, and `grid_entries` source tables, while its review state remains `current_unreviewed_peq`.
- EQ Mobile's Domain / Presentation / Services separation, deterministic simulation clock, event model, RNG abstraction, save envelope, and validation gate are project-owned architecture decisions rather than claims about original EverQuest internals.

### Evidence and review state for material rules

| Rule or data | Evidence/review state | Phase 3 treatment |
| --- | --- | --- |
| Domain / Presentation / Services separation, event model, simulation clock, persistence boundary, and seeded RNG service | Project-owned architecture; not a historical gameplay-value claim | Foundational EQ Mobile implementation structure. |
| Halas `SpawnPoint -> SpawnGroup -> npc_ref -> NpcArchetype` relationships | `confirmed_source_behavior` in the generated dataset provenance, sourced from PEQ `spawn2`, `spawnentry`, and `npc_types` | Used as structural identity/reference evidence only. |
| Offline single-process simulation | `intentional_mobile_offline_deviation` | Recorded as `DEV-001`. |
| Cooldown/death/respawn timers pausing while the application is closed | `intentional_mobile_offline_deviation` | Recorded as `DEV-010`. |
| Training Spark health, damage, XP, loot, behavior, and Training Strike tuning | `temporary_fixture_default` | Development-only fixture values; see `DEV-003`. |
| Player fixture health, combat size, and inventory capacity | `temporary_fixture_default` | Development-only values pending reviewed character/inventory rules. |
| Imported PEQ/current NPC HP, AC, damage, delay, loot, and related gameplay fields | Dataset review state `current_unreviewed_peq`; gameplay activation remains unreviewed | Kept as source/provenance data and not enabled as authoritative combat or loot. |
| `ProgressionState.xp_threshold()` cubic formula and hell-level modifiers | `inference` pending classic-era source review | Retained as deterministic architecture-era behavior; not declared authentic `original_classic_pre_kunark` progression. |
| Faction reaction thresholds/fallbacks in `FactionSystem` | `inference` pending classic/P1999 threshold review | Retained as deterministic offline behavior; see `DEV-005`. |
| `Simulation.DEFAULT_MELEE_FACING_DOT`, `Simulation.ORDINARY_MELEE_EFFECTIVE_SIZE`, fallback melee range, and default facing behavior | `inference` pending dedicated classic combat review | Used for generic attack validation without claiming classic numerical authority. |
| Safe health/hostility values applied to a real imported NPC by the Phase 3 foundation test | `temporary_fixture_default` | Test-only values proving the shared pipeline; never a PEQ gameplay activation. |

No new `classic_specific_evidence` for authentic combat, progression, faction, or NPC-stat numerical values is claimed by Phase 3.

### Import and provenance boundary

Generated/imported Halas data preserves source identities and typed references according to `docs/identity-contract.md`. Phase 3 consumes those relationships through `ContentService` and presentation adapters without editing imported source snapshots to satisfy tests.

A current PEQ value does not become gameplay authority merely because the generic simulation can represent it:

- PEQ NPC HP is not copied into active runtime combat health.
- PEQ minimum/maximum damage is not copied into active attack profiles.
- PEQ loot-table references do not automatically award loot.
- Imported PEQ combat and auto-hostility remain disabled by default.
- The foundation test's imported-NPC configuration is explicitly marked `architecture_test_override`.
- The entity retains `source_combat_enabled = false` metadata while the test-only override exercises the generic simulation.

### Known uncertainty

The following areas remain outside the Phase 3 completion claim:

- authentic original-classic XP thresholds and level modifiers;
- authentic classic/P1999 faction reaction thresholds;
- authentic melee range, size interaction, facing threshold, hit chance, mitigation, avoidance, and damage formulas;
- authentic player and NPC health derivation;
- authentic imported NPC combat statistics and hostility;
- authentic imported loot awarding;
- future mechanics that might intentionally progress while the application is closed.

These uncertainties do not block the architecture gate. When a later implementation needs authoritative classic values and substantial source investigation is required, follow the manual `RESEARCH TASK FOR CHATGPT` handoff in `AGENTS.md` before promoting temporary or inferred values.

No additional source research is required solely to close Phase 3.

### Mobile/offline deviations

The authoritative deviation record remains `docs/deviation-registry.md`.

Phase 3 depends on:

- `DEV-001`: offline Godot simulation rather than a continuously hosted network/server architecture.
- `DEV-010`: simulation cooldown, dying/death, and respawn timers pause while the application is closed. Real-world time is used only for legacy migration or a future mechanic explicitly designed to require offline passage.

## Foundation gate proof

`tests/run_phase3_tests.gd` covers:

- entity lifecycle transitions;
- seeded RNG reproducibility;
- generic attack/damage/death event ordering;
- exactly-once death, XP, and item rewards;
- current deterministic progression behavior;
- headless inventory mutation;
- actual temporary `user://` persistence I/O;
- corrupt-save rejection without mutating the existing simulation;
- supported legacy-schema migration;
- simulation-clock-driven cooldowns without wall-clock waiting;
- deterministic replay;
- Training Spark plus a genuinely spawn-referenced imported Halas NPC through the same generic entity/combat/lifecycle machinery.

The persistence round trip verifies player and non-player runtime entity state, inventory, XP/progression, wallet, faction values, remaining cooldown, exact RNG snapshot/state, and simulation clock state. The legacy test uses only fields already handled by `_migrate_legacy_save()` and deliberately avoids legacy wall-clock cooldown deadlines so the test remains deterministic.

The imported-NPC proof resolves:

`SpawnPoint -> SpawnGroup -> candidate npc_ref -> NpcArchetype`

It verifies source HP/damage/loot fields exist for the resolved imported definition, verifies those values are absent from the normal runtime combat/reward configuration, and then kills the entity through `Simulation.request_attack -> damage -> death` using only explicit project-owned safe fixture values.

## Canonical Phase 3 validation

The canonical Phase 3 architecture gate is:

```bash
tools/run_phase3_tests.sh

The script first runs a headless editor/compile scan and fails on SCRIPT ERROR, Parse Error, Compile Error, or Failed to load script. It then runs res://tests/run_phase3_tests.gd, propagates the Godot process exit code, independently rejects script/parse/compile/load errors even when Godot exits zero, and requires the expected test-suite PASS marker.

The existing Android build-tools warning does not match the gate's script-error conditions and is not a Phase 3 architecture failure.