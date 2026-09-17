Markdown
# EQ Mobile — Time, Timer, and Randomness Contract

## Scope

This document defines the Phase 4 foundation contract for gameplay time,
timers, pause/suspend behavior, offline elapsed time, and deterministic
randomness.

Gameplay systems should use these services rather than independently calling
engine timing or randomness APIs.

## Canonical simulation clock

`SimulationClock` is the canonical gameplay clock.

Gameplay-domain code expresses time relative to
`SimulationClock.now_seconds()`.

`Simulation.advance(delta_seconds)` is the normal owner of simulation-clock
advancement.

The simulation clock:

- advances only while gameplay is running;
- never moves backwards;
- stops while explicitly paused;
- does not automatically advance from wall-clock passage;
- can be restored exactly from a save.

`Time.get_unix_time_from_system()` is isolated behind
`SimulationClock.real_world_unix_ms()`.

Real-world time is permitted only for non-simulation concerns such as:

- save metadata;
- diagnostics;
- migration of legacy saves that stored absolute wall-clock cooldowns.

## Canonical timer bank

`SimulationTimerBank` provides the generic gameplay timer mechanism.

At runtime each timer is stored as a deadline against the canonical simulation
clock.

At persistence boundaries those deadlines become remaining durations. This
means changing the device clock, suspending the application, or leaving the app
closed does not silently change gameplay state.

Stable timer keys follow:

```text
<category>|<owner>|<timer>

Current categories are:

cooldown
spawn
ai
effect
cast
recast
merchant_restock

New gameplay systems should normally extend this timer model instead of
introducing engine Timer nodes, independent tick counters, or wall-clock
timestamps for gameplay rules.

Presentation-only timing such as camera interpolation, animation presentation,
touch gestures, and autosave cadence may continue to use frame delta when it
does not determine simulation state.

Attack timers

Attack and ability recovery use the cooldown category.

Combat profiles continue to provide the recovery duration. Simulation
converts that duration into a canonical simulation timer when an attack is
successfully performed.

Cooldowns therefore stop whenever simulation time stops.

Initial spawn timers

Entities registered without immediate spawning may use
Simulation.schedule_spawn().

The delayed initial spawn uses the spawn timer category and emits the normal
SPAWN gameplay event when it becomes active.

No classic spawn delay is invented by this architecture. Content or a
source-backed spawn system must provide the duration.

Death and respawn timers

Existing death and respawn lifecycle state remains owned by GameplayEntity,
but lifecycle deadlines are calculated exclusively from the canonical
simulation clock supplied by Simulation.

Persistence stores lifecycle deadlines as relative values:

dying_remaining
respawn_remaining

As a result, respawn and death-state timing have the same pause and offline
semantics as the generic timer bank.

AI think/update timers

Simulation.claim_ai_think() provides a deterministic per-entity AI cadence.

SimpleNpcBehaviorSystem may consume think_interval_seconds from behavior
data.

If the field is absent or zero, the current every-frame behavior remains
unchanged. This provides timer architecture without inventing an unsupported
classic-EQ AI interval.

Buff and debuff duration framework

Simulation.apply_timed_effect() provides the duration foundation for buffs,
debuffs, and other temporary entity effects.

The framework currently owns:

target identity;

effect identity;

remaining duration;

arbitrary effect metadata;

automatic expiration;

save/restore state.

The Phase 4 framework intentionally does not invent classic rules for:

stacking;

stat calculations;

dispels;

death removal;

zoning behavior;

beneficial/detrimental spell classification.

Those rules require source-backed implementation later.

Spell cast and recast framework

The simulation provides:

begin_spell_cast
spell_cast_remaining
spell_cast_ready
complete_spell_cast
interrupt_spell_cast
spell_recast_remaining

One active cast is supported per entity.

Cast time uses the cast timer category. Successful completion can start a
recast timer.

Spell resolution itself is deliberately separate from timing. Future spell
systems can consume the completion result without creating another clock or
timer convention.

Merchant restock architecture

Merchant stock does not currently require active restocking.

The canonical future architecture is nevertheless reserved through:

schedule_merchant_restock
merchant_restock_remaining
merchant_restock_due
consume_merchant_restock_due

Actual inventory mutation and classic restock values remain future,
source-backed work.

Pause behavior

Explicit simulation pause freezes gameplay time.

While paused:

the simulation clock does not advance;

Simulation.advance() performs no lifecycle processing;

attack cooldowns do not recover;

scheduled spawns do not occur;

death and respawn timers do not progress;

AI cadence does not progress;

timed effects do not expire;

casts do not complete;

recast timers do not recover;

merchant restock timers do not progress.

Presentation/UI systems may remain active if a future pause menu requires them,
but they must not advance gameplay state.

Android suspend and resume

RuntimeLifecycleBridge listens for Godot application pause and resume
notifications.

On application pause:

the canonical simulation clock is paused;

the current simulation is synchronously saved;

gameplay process callbacks are disabled;

gameplay physics callbacks are disabled.

On application resume:

gameplay processing is restored;

gameplay physics processing is restored;

the canonical simulation clock resumes from the same simulation time.

Android may terminate a suspended process, so saving on the pause notification
provides a recovery point for a later launch.

Offline elapsed-time rule

EQ Mobile explicitly uses:

offline_elapsed_policy = freeze

Real-world time spent with the application suspended or closed does not advance
gameplay.

Offline time therefore does not automatically:

finish attack cooldowns;

trigger initial spawns;

respawn NPCs;

finish player death timing;

expire buffs or debuffs;

complete spell casts;

finish spell recasts;

run AI updates;

trigger merchant restocks.

Save schema version 3 records saved_unix_ms for diagnostics but never feeds
the observed elapsed time into Simulation.advance().

Any future feature that intentionally progresses while offline must be an
explicitly documented exception rather than changing canonical simulation
semantics globally.

Deterministic randomness

SimulationRng is the canonical gameplay RNG service.

Gameplay-domain systems should not independently call:

randf
randi
randomize
RandomNumberGenerator.new

Application startup may seed SimulationRng from non-deterministic runtime
data.

Deterministic tests inject a fixed seed.

Save state preserves both:

seed
state

The persistence layer serializes those 64-bit values as decimal strings at the
JSON boundary, preventing loss of deterministic continuation through JSON
number precision.

Persistence

Save schema version 3 preserves:

canonical simulation elapsed time;

deterministic RNG seed;

exact RNG state;

generic timer remaining durations;

death/respawn remaining durations;

timed effects;

active spell casts;

existing inventory, wallet, progression, faction, entity, and reward state.

Version-2 saves are migrated by converting their cooldown dictionary into
generic cooldown timers.

Older saves that used absolute wall-clock cooldown timestamps are converted
once during legacy migration. After migration, gameplay timers are entirely
simulation-relative.

Foundation gate

New gameplay code should not introduce independent gameplay clocks, timer
semantics, or RNG instances without an explicit architectural reason.

The default dependency flow is:

gameplay time
    -> SimulationClock

gameplay deadlines
    -> SimulationTimerBank
       or GameplayEntity lifecycle deadlines derived from SimulationClock

gameplay randomness
    -> SimulationRng

persistence
    -> remaining simulation durations + exact RNG state