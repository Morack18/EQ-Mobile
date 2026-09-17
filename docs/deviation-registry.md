# EQ Mobile Deviation Registry

This is the single record of deliberate differences between source behavior and
EQ Mobile. Entries are not bugs or unknowns; unknowns belong in the relevant
research note until a decision is made.

| ID | System | Source behavior / authority | EQ Mobile decision | Evidence label | Review trigger |
| --- | --- | --- | --- | --- | --- |
| DEV-001 | Architecture | EQEmu is a networked server and EQ clients use protocol/server authority. | Offline Godot simulation; no network, database server, or protocol port. | `intentional_mobile_offline_deviation` | Any multiplayer/server feature proposal. |
| DEV-002 | Input/UI | Classic UI is desktop-oriented. | Touch controls, long-press merchant interaction, and simplified mobile panels are original adaptations. | `intentional_mobile_offline_deviation` | UI system redesign or accessibility review. |
| DEV-003 | Training Spark | No source-backed equivalent exists. | Original fixture NPC, loot, damage, XP, and Training Strike tune the vertical slice only. | `temporary_fixture_default` | Replace with reviewed imported content. |
| DEV-004 | Imported NPC combat | Current PEQ rows are structurally useful but not verified P1999 stats. | Imported NPC combat and auto-hostility remain disabled pending reviewed correction data. | `inference` | Per-NPC classic stat/faction review. |
| DEV-005 | Faction thresholds | EQEmu rule defaults are configurable current values. | Use them as data-backed offline defaults, not verified P1999 constants. | `inference` | Classic/P1999 threshold evidence. |
| DEV-006 | Inventory slots | Titanium client uses protocol-specific slot IDs. | Eight ordered logical root slots; no protocol IDs, bags, bank, or cursor semantics yet. | `intentional_mobile_offline_deviation` | Dedicated classic inventory/bag pass. |
| DEV-007 | Merchant economy | Full EQ price calculation includes unimplemented faction/CHA/rule modifiers. | Browse-only merchant UI displays source base prices; no purchases or sales. | `intentional_mobile_offline_deviation` | Atomic merchant transaction implementation. |
| DEV-008 | Grounded movement | No reviewed classic-client source establishes the project’s Godot floor angle, snap distance, or safe margin. | Use 60° floor angle, 0.5-unit snap, and 0.05 safe margin as temporary grounded-controller stability values. | `temporary_fixture_default` | Dedicated classic slope/collision evidence and device validation. |
| DEV-009 | Step-up | eqoxide documents a 2-unit native step bound, but EQ Mobile implements it through Godot sweep/landing checks rather than the reference client code. | Preserve a bounded 2-unit step-up with explicit headroom/travel/walkable-landing checks. | `intentional_mobile_offline_deviation` | Native collision-controller replacement or contradictory classic evidence. |

## Entry rules

Add an entry before shipping a deliberate behavior difference. Keep the source
authority, evidence label, concrete decision, and condition for revisiting it.
If the source behavior is unknown, do not call it a deviation; classify the
claim as an `inference` in the relevant research record instead.
