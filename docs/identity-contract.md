# Phase 2 — Identity and Data Contracts

This contract separates a stable definition key, source provenance, and runtime
occurrence. Game code references typed keys; import tools translate source rows
into them. Runtime code must not depend on PEQ/EQEmu SQL table layouts.

## Key grammar

`<namespace>:<domain>:<local-id>` is the required definition-key grammar.

| Namespace | Meaning | Examples |
| --- | --- | --- |
| `eqm` | EQ Mobile-owned composite/curated definitions | `eqm:zone:halas`, `eqm:quest:example` |
| `peq` | One-to-one ProjectEQ-derived definition | `peq:npc:29026`, `peq:item:14233` |
| `eqemu` | Stable EQ semantic enumeration | `eqemu:class:1`, `eqemu:skill:30` |
| `client` | Private client/extraction source identity | `client:zone_geometry:halas` |
| `fixture` | Original development-only content | `fixture:item:training_spark_fragment` |

Names are presentation, never foreign keys. Corrections preserve the key of the
corrected source entity; an overlay has its own dataset key and does not fork
the entity identity.

## Definition versus instance

| Domain | Definition key | Runtime/save instance rule |
| --- | --- | --- |
| Zone | `eqm:zone:<slug>` | loaded zone is transient; save position is keyed by zone definition |
| NPC archetype | `peq:npc:<npc_types.id>` | spawned actor is a transient occurrence |
| Spawn point/group | `peq:spawn:<spawn2.id>` / `peq:spawn_group:<id>` | current respawn/occupant state belongs to the spawn point |
| Item | `peq:item:<items.id>` or `fixture:item:<slug>` | inventory entry references definition key plus quantity/charges |
| Loot table/drop | `peq:loot_table:<id>` / `peq:loot_drop:<id>` | roll is transient, not a new definition |
| Faction/NPC faction | `peq:faction:<id>` / `peq:npc_faction:<id>` | player standing is keyed by faction definition |
| Spell | `peq:spell:<spells_new.id>` | learned/cast state later references definition key |
| Skill/class/race | `eqemu:skill:<id>` / `eqemu:class:<id>` / `eqemu:race:<id>` | player values reference definition keys; no runtime definition copy |
| Quest | `eqm:quest:<slug>` | active progress is save state keyed by quest definition |

## Neutral schema minimums

All generated datasets use `schema_id`, `schema_version`, a dataset key,
`era_profile`, `design_target`, `review_state`, evidence, source artifact/hash,
generator/input digest, filters, and overlay metadata when applicable. Do not
embed nondeterministic wall-clock timestamps in generated JSON.

- `ZoneDefinition`: key, source refs, geometry ref, world contract, spawn
  dataset ref, player spawn, bounds.
- `NpcArchetype`: key/source ID, identity, appearance, raw gameplay fields,
  typed faction/loot/merchant refs, activation state.
- `SpawnPoint`: key/source ID, zone ref, spawn-group ref, position/heading,
  respawn and era availability.
- `SpawnGroup`: key/source ID and candidate NPC refs with chance/availability.
- `ItemDefinition`: key/source ID, item fields, container definition,
  review/provenance; distinct from inventory instances.
- `LootTable`/`LootDrop`: distinct reusable definitions; never flatten drops.
- `FactionDefinition`: key/source ID, base/bounds/modifiers; NPC faction bundles
  are separate definitions.
- `QuestDefinition`: project-owned shell only until reviewed quest evidence
  supports dialogue/objective/reward behavior.

## Required validation

Generated/runtime data must reject duplicate definition/source IDs, malformed
keys, missing foreign references, incompatible source IDs, absent schema
versions, and unsupported era metadata. Optional numeric source foreign keys
use `null` in neutral data, never fabricated `*:0` keys.

Current raw PEQ snapshots remain source-shaped for deterministic overlay
application. Their Phase 2 typed keys are derived at import/runtime boundaries
until the versioned importer schema migration is complete.
