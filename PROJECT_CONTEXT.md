# EQ Mobile — Project Context

Last updated: 2026-09-16

## Product intent

EQ Mobile is an **offline, Android-first, single-player RPG** inspired by the
exploration, combat, progression, and zone-based structure of EverQuest. It is
being built in Godot 4 and must work without a network connection or a running
server.

## Canonical era

The project targets the **classic/P1999 era**. Content, mechanics, zones, NPC
rosters, itemization, appearances, quests, and progression must be selected
and validated against that era. Do not silently use later-expansion, seasonal,
or event content from a general PEQ dump. Every imported dataset must record
its source version and the classic-era filtering rules used.

The phrase “1-to-1 EverQuest” is a product aspiration, not an implementation
or distribution plan: publishing a literal clone, original EverQuest assets,
or Daybreak intellectual property requires appropriate rights. Until those
rights are confirmed, create original branding, art, text, audio, quests, and
world content; treat the supplied client files as private reference material
only. This is not legal advice.

The binding implementation policy is [docs/foundation-contract.md](docs/foundation-contract.md).
It defines the pre-Kunark default, later-era opt-in rules, source authority,
evidence labels, provenance boundary, and the required
[deviation registry](docs/deviation-registry.md). New systems must follow it
before choosing a source value or behavior.

Spatial conversions and native-unit physics are governed by
[docs/world-mathematics.md](docs/world-mathematics.md). New zones must declare
and validate their own world-space contract; Halas math is not implicit global
behavior.

Stable definition keys, source identities, runtime instances, and generated-data
validation are governed by [docs/identity-contract.md](docs/identity-contract.md).
Runtime systems must consume those neutral contracts rather than SQL layouts.

## Current workspace

- Engine: Godot 4.7 project (`project.godot`), Mobile renderer and Jolt 3D
  physics enabled.
- Current playable slice: `scenes/Main.tscn` provides mobile movement/camera,
  combat against a data-defined test NPC, respawn, minimal original fixture
  loot/inventory and XP/level loops, and local persistence. Its
  placeholder player is the animated `hlm_s0_h0` actor normalized to the same
  classic HLM size (`7` EQ world feet) as Halas-citizen NPCs; two-stick movement uses eqoxide's
  35 native EQ-sized-unit/s manual-drive path. EQEmu's `0.7 * 40 = 28` value is
  retained as client-update animation/wire semantics, not physical speed; the
  separate eqoxide 44 u/s controller constant remains a documented source discrepancy. The player is a gravity-driven `CharacterBody3D`
  with a grounded capsule collider against zone terrain and walls; its
  third-person camera retracts against the same collision instead of clipping
  through zone walls.
- Current zone geometry: a deliberate runtime copy of the supplied Halas GLB
  is referenced by `data/halas.json`; `resources/.gdignore` excludes all
  reference material from Godot scanning. See `docs/halas-import.md` for its
  provenance and known follow-up work.
- Current Halas props: all 445 Lantern object placements are loaded from
  `data/halas_objects.json`, using 91 explicit runtime GLB copies in
  `assets/imported/halas/objects/`. A classic-filtered Halas NPC population
  is instantiated from the derived `data/halas_npcs.json`, with source-driven
  race/gender/skin/head variants in `assets/imported/halas/characters/` and patrols
  from the source grids. The raw ProjectEQ snapshot remains
  `data/halas_npcs_source.json`; its empty, versioned P1999 correction overlay
  is applied deterministically and awaits reviewed corrections before the roster
  can be treated as exact.
- Reusable import knowledge: `docs/zone-import-playbook.md` is the required
  source of truth for future zone imports. It records the validation-first
  geometry, coordinate, animation, and appearance pipeline learned from Halas.
- Target: Android first; design controls, readability, performance budgets,
  save/resume behavior, and offline data access for touch devices from day one.

## Supplied reference resources

| Resource | Location | Use in EQ Mobile | Important boundary |
| --- | --- | --- | --- |
| eqoxide | `resources/eqoxide-main/` | Primary client-behavior reference: zone rendering/placement, character models and animation, movement/collision, inventory, spells, combat, client state, and UI behavior. Consult it before designing a corresponding client-facing system. | Reference only. EQ Mobile remains a clean, offline Godot implementation; do not adopt its EQEmu network, HTTP API, asset-server, or Rust architecture. Verify its license before reusing any code. |
| OpenEQ | `resources/OpenEQ-master/` | Companion client/reference implementation for original EQ zone formats, model transforms, placement rotation, camera, and network-facing movement/heading fields. Consult it alongside eqoxide when an import or client-coordinate behavior is involved. | Reference only. Preserve its license obligations; adapt observed behavior into original Godot-native code rather than copying implementation. |
| EQEmu | `resources/EQEmu-master/` | Reference for gameplay systems and data concepts: zones, spawn groups, NPC stats, loot, factions, quests, respawn, and combat rules. | GPL-3.0. Do not copy/link its code into a proprietary project. Any distribution of a derivative of its code must meet GPL obligations. Prefer a clean, original Godot implementation informed by documented behavior. |
| EverQuest client | `resources/EverQuest/` | Private research/reference for archive naming, zone organization, formats, and owned local installation behavior. Includes `.s3d`, `.eqg`, executables, audio, UI, maps, and configuration. | Original proprietary client/assets. Do not package, redistribute, publish extracted derivatives, or represent as owned project assets without authorization. |
| LanternExtractor | `resources/LanternExtractor/` | Local extraction/inspection pipeline. Its bundled `tools/eqmob-gui/` is a Godot 4 desktop GUI for previewing and exporting Lantern-produced GLB assets. | Verify LanternExtractor and source-asset licensing before use. Extraction capability does not grant redistribution rights. No exported GLB files were observed in `Exports/` during initial inventory. |

## Architecture decisions

1. Build an **offline simulation**, not an EQEmu server port. Gameplay executes
   locally in Godot; no TCP protocol, login, world process, or MySQL runtime.
2. Keep content as versioned, human-readable data in `res://data/` during
   development. Export to compact runtime resources later only if profiling
   demands it.
3. Define a neutral import schema rather than coupling game code to EQEmu SQL:
   `ZoneDefinition`, `SpawnPoint`, `SpawnGroup`, `NpcArchetype`, `LootTable`,
   `ItemDefinition`, `FactionDefinition`, and `QuestDefinition`.
4. Save local state under `user://`: player, per-zone spawn state/respawn
   timers, quest flags, inventory, and settings. The app must remain playable
   in airplane mode.
5. Treat coordinate conversion, units, axes, scale, headings, and collision as
   a dedicated import concern. Validate each imported zone in a visual test
   scene before production use.
6. Treat NPC appearance as source data: select the exact actor family from
   race/gender and the variant from texture/face; do not share a convenient
   default model across distinct classic races.
6. Prefer original placeholder assets for early development. Do not block the
   gameplay vertical slice on asset extraction.

## Suggested repository layout

```text
assets/                 # Original/licensed project assets only
data/                   # Source-controlled game definitions (JSON/CSV/Tres)
docs/                   # Technical notes and import contracts
scenes/                 # Reusable Godot scenes
scripts/
  domain/               # Pure gameplay rules and state
  presentation/         # 3D, UI, animation, audio
  services/             # Persistence, content loading, clock
tools/                  # One-way import/validation tools; never runtime deps
tests/                  # Deterministic rules/import tests
```

## First vertical slice (the immediate goal)

Make one small original test zone playable on an Android device:

1. Touch movement and a mobile camera.
2. One player character with health, target selection, basic melee attack, and
   a clearly readable HUD.
3. One hostile NPC spawned from a data file, with pursuit, attack, death, and
   timed respawn.
4. Local save/resume that preserves player position and NPC respawn state.
5. An Android debug build installed and tested on a physical device.

This validates the hard architectural assumptions—touch UX, Android rendering,
offline persistence, data-driven spawns, and the gameplay loop—before an
attempt to import large zones or reproduce broad systems.

## Content-import roadmap (after the slice works)

1. Document and test the minimal neutral schema with a hand-authored sample.
2. Write a **read-only** EQEmu database exporter that maps selected data into
   the neutral schema. Preserve source IDs and record its transform/version.
3. Build a zone import validator: bounds, duplicate IDs, missing NPCs,
   invalid headings, out-of-navmesh spawns, and unresolved references.
4. Add one zone at a time, with original/licensed geometry and assets unless
   rights for other assets have been confirmed.
5. Expand systems in dependency order: combat → loot/inventory → leveling and
   abilities → factions → quests → merchants/crafting → companions.

## Working rules for future changes

- Never modify files inside `resources/`; they are input references.
- Keep import tools idempotent, read-only against inputs, and record source
  version plus conversion settings in generated metadata.
- Do not rely on desktop-only controls, hover, tiny targets, or keyboard-only
  interaction for core play.
- Profile on target Android hardware before accepting rendering/asset budgets.
- Record material assumptions and source/provenance in `docs/` as imports are
  added.
- Before guessing classic behavior, search `resources/eqoxide-main/` and
  `resources/OpenEQ-master/` for the client-side implementation, then use
  `resources/EQEmu-master/` for server/gameplay-data authority where relevant.
  Adapt the findings into clean Godot-native offline code.
- Add implementation-relevant results from those repositories to
  `docs/reference-discoveries.md`, including source path, behavior/formula,
  Godot adaptation, and any deviation.
- Follow `docs/zone-import-playbook.md` for every zone; expand it when a new
  import reveals a reusable fact or a new validation requirement.
- For every new zone, create `data/zones/<zone>.pipeline.json` and run
  `tools/zone_pipeline.py validate` plus its PCK `package-check` before an APK
  is exported. These local checks are the default for repeatable import work;
  do not spend AI tokens rechecking asset inclusion or placement references.
