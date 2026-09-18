# Phase 5 — Generic Actor Contract

## Scope

Phase 5 extends the existing `GameplayEntity` rather than creating a parallel
player/NPC hierarchy.

`GameplayEntity` remains the generic runtime participant established by the
Phase 3 simulation architecture. Player characters and NPCs share fundamental
actor state where the concepts are genuinely common, while `kind`,
attachments, controllers, source metadata, and content definitions preserve
their differences.

This is EQ Mobile architecture. It does not claim that the containers or state
names reproduce an original EverQuest server implementation exactly.

## Shared actor identity

The generic actor contract contains:

- stable runtime `entity_id`;
- stable content `definition_id`;
- actor `kind`;
- display name;
- race ID and typed race reference;
- gender ID;
- class ID and typed class reference;
- level.

Definition identity remains governed by `docs/identity-contract.md`.

Names and appearance model names are never substitutes for typed gameplay
identity.

## Appearance separation

`appearance` is a dedicated actor attachment.

Gameplay identity fields such as race, gender, class, faction, and level do
not belong inside appearance.

Appearance may contain presentation facts such as:

- model or model path;
- texture/skin;
- face/head;
- source visual size;
- future hair/beard/color/material values.

The current player HLM model remains an explicit presentation placeholder and
is therefore allowed to differ from the player fixture's gameplay race
identity.

Halas keeps its existing source-driven model selection. Phase 5 exposes those
source appearance facts through the generic actor contract instead of making
the Halas presentation adapter the only place that can describe them.

## Stats and resources

Actors contain separate `base_stats` and `derived_stats` dictionaries.

Phase 5 intentionally does not populate authentic classic formulas merely to
fill these containers. Empty dictionaries are valid until source-reviewed stat
rules are implemented.

Shared resources are:

- current/max HP;
- current/max mana;
- current/max endurance.

HP continues to use the established `health` / `max_health` field names to
avoid unnecessary Phase 3 combat churn.

Mana and endurance default to zero where the current slice has no reviewed
gameplay rule requiring them.

## Spatial and movement state

Actors own:

- position;
- spawn position;
- normalized facing;
- heading conversion helpers;
- movement state;
- movement velocity.

Current generic movement states are project-owned descriptive states:

- `idle`;
- `moving`;
- `swimming`;
- `airborne`.

The actor state describes simulation/runtime state. Scene nodes remain
presentation objects and are not canonical gameplay entities.

The existing Halas patrol implementation remains a zone-specific
presentation compatibility path in this phase. Every successfully built Halas
NPC now has a generic domain actor, and its presentation position, facing, and
current patrol velocity are mirrored into that actor each frame.

The presentation patrol remains authoritative until that rule is migrated to a
generic controller/AI system. Save restoration therefore does not push mirrored
Halas actor positions back into presentation patrol nodes.

## Target and combat state

Actors carry a stable target entity ID.

For the local player, `GameplayEntity.target_entity_id` is the canonical
runtime target. Halas selection remains presentation/interaction context;
selecting an NPC writes that NPC's stable runtime entity ID to the player
actor. Clearing Halas selection explicitly restores the existing Training
Spark fixture as the default target when that fixture exists, instead of
relying on an implicit fallback in `main.gd`.

Because targets are intentionally transient rather than persisted, startup
restores that same project-owned default after save loading.

Current generic combat states are:

- `disabled`;
- `idle`;
- `engaged`;
- `casting`.

`Simulation` remains the public gameplay-mutation boundary for targeting,
attacks, casts, damage, and canonical effect duration.

These states describe architecture. They do not introduce new classic-EQ
aggro, hate, attack, mitigation, or spell rules.

## Lifecycle

The existing lifecycle remains:

`created -> spawned -> active -> dying -> dead -> respawning -> spawned`

`removed` remains terminal.

Spawn restores the actor's HP, mana, and endurance to their configured maxima.
Death clears movement, target, and transient combat state.

Phase 5 does not invent a buff-removal-on-death rule. Permanent entity removal
may clear its effect attachment; ordinary death does not.

## Attachments

The actor provides neutral attachment points for:

- faction identity;
- inventory;
- equipment;
- effects/buffs;
- controller/AI;
- appearance.

An attachment describes an association; it does not imply that every actor
uses the same subsystem.

For example, the current player inventory remains owned by `Simulation` /
`InventoryState`, while imported Halas NPCs do not suddenly receive player
inventory behavior merely because the generic actor has an inventory
attachment point.

`SimpleNpcBehaviorSystem` consumes behavior and combat-profile configuration
from `controller_attachment`. The legacy metadata lookup remains only as a
compatibility path for existing Phase 3 fixtures while they are migrated.

## Effects

The actor effect container mirrors active effects attached to that actor.

Canonical duration and expiration remain owned by the Phase 4
`SimulationTimerBank` through `Simulation.apply_timed_effect()`.

Save/restore rebuilds actor effect containers from the canonical persisted
timed-effect records. This avoids two independent timing authorities.

## Player specialization

The local player uses the same actor fields for:

- race/gender/class;
- level;
- HP/resources;
- position/facing;
- movement;
- targeting/combat;
- lifecycle;
- appearance attachment.

Player-only progression, wallet, inventory implementation, input controller,
and faction standing remain specialized systems rather than being forced onto
every NPC.

## NPC specialization

Imported Halas NPCs use the same actor fields for structural identity and
appearance.

Source-derived race, gender, class, level, faction reference, texture, face,
and visual size may populate the identity or appearance portions of the generic
actor contract because they describe the source actor/appearance relationship.

Source visual size remains `appearance.source_size`. It does not populate
`combat_size`, because `combat_size` currently participates in melee-range
gameplay and therefore requires its own reviewed authority.

Current PEQ HP, mana, AC, damage, attack delay, loot, and similar unreviewed
gameplay values remain provenance metadata and do not become active merely
because the generic actor model can represent those systems.

The Training Spark remains a project-owned fixture with its existing explicit
fixture combat values.

Every Halas NPC successfully built by `HalasNpcPopulation` is registered
with `Simulation` immediately and bound to its presentation node. Target
selection therefore selects an existing actor; it does not create an actor on
demand.

Unsupported or unrendered source rows do not receive fabricated runtime actors.
The domain roster follows the presentation roster that was actually built.

## Source review

Local EQEmu source review of the common `Mob` abstraction (`zone/mob.h`) shows
that race, gender, class, level, position/heading, target, health/resources,
buff state, inventory access, and AI/controller-related state are common actor
concerns, while `Client` and `NPC` specialize behavior.

EQ Mobile uses that only as architectural evidence for the shared-vs-specialized
boundary. Phase 5 does not copy current EQEmu formulas or promote modern
behavior to original-classic authority.

## Persistence

Current HP, mana, and endurance are included in each entity runtime snapshot.

The new mana/endurance fields are additive and default safely when loading
older schema-v3 snapshots, so Phase 5 does not require a save-schema bump for
this change.

Movement, target, combat descriptive state, static identity, attachments, and
appearance are reconstructed from content/runtime behavior rather than added
as duplicate save authorities.

## Foundation gate

Phase 5 passes when:

1. player and every built Halas NPC runtime object use `GameplayEntity`;
2. race, gender, class, level, stats, resources, spatial state, target, combat,
   lifecycle, faction, attachments, effects, controller, and appearance all
   have a generic representation;
3. player-only and NPC-only systems remain specialized rather than being
   artificially merged;
4. Halas source appearance is represented separately from gameplay identity;
5. imported unreviewed combat statistics remain inactive;
6. the Phase 3 architecture and Phase 4 time/RNG/persistence contracts continue
   to pass unchanged.
