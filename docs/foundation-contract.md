# EQ Mobile Foundation Contract — Phase 0

This document is the governing contract for source authority, era selection,
evidence, provenance, and deliberate differences from EverQuest. Read it before
designing or importing a new system. It resolves source conflicts before code is
written; it does not authorize copying reference code or proprietary assets.

## 1. Canonical era contract

EQ Mobile targets the original EverQuest / P1999-style experience, not the
latest behavior in a general-purpose PEQ dump or a modern EQEmu server.

The default gameplay baseline is **original classic, pre-Kunark**. A system may
only opt into a later era when its data definition and documentation name one
of these explicit profiles:

| Profile | Meaning | Rule |
| --- | --- | --- |
| `original_classic_pre_kunark` | Original game baseline before Kunark | Default for new mechanics and caps. |
| `classic_kunark` | Kunark-era behavior/content | Requires a documented reason and source evidence. |
| `classic_velious` | Velious-era behavior/content | Requires a documented reason and source evidence. |
| `p1999_phase_specific` | A P1999 rule/content tied to a named historical phase | Must record the phase and reviewed evidence. |

“Classic/P1999” is a design target, not evidence by itself. P1999 may differ by
historical phase, and PEQ/EQEmu may contain later or server-configured behavior.
No current value becomes canonical merely because it appears in either source.
When a mechanic differs across profiles, the implementation must name the chosen
profile in its data or documentation and record the difference in
[`deviation-registry.md`](deviation-registry.md).

## 2. Source-authority matrix

Use the first applicable authority. A lower row can fill a gap, but must not
silently override a higher row.

| Question | Primary authority | Secondary / corroboration | Not canonical by itself |
| --- | --- | --- | --- |
| Client-visible controls, camera, movement presentation, UI behavior, rendering | local `resources/eqoxide-main/`, then `resources/OpenEQ-master/` | owned client observations | modern server code, PEQ rows |
| Gameplay rules, persistence concepts, combat/faction/item semantics | local `resources/EQEmu-master/` plus classic-specific evidence | ProjectEQ schema/data for relationships | current configurable defaults presented as P1999 fact |
| Classic/P1999-specific values, availability, corrections | reviewed evidence recorded in a versioned correction overlay | compatible primary/reference sources | unreviewed PEQ values, generic memory |
| Zone/client archive format and extracted data | owned local client files and extraction outputs | LanternExtractor format behavior | extracted proprietary files as distributable project assets |
| EQ Mobile mobile/offline behavior | project-owned Godot code/data | source-informed design notes | claiming an adaptation is original EQ behavior |

If applicable primary authorities disagree, stop and record the conflict as an
**inference** or request research; do not choose whichever source is easiest to
implement.

## 3. Evidence classification

Every material gameplay claim in source notes, generated data metadata, or a
deviation entry must carry one of these labels:

| Label | Meaning | Required record |
| --- | --- | --- |
| `confirmed_source_behavior` | Directly observed in a specific local source implementation or schema | exact repository path and symbol/table/line area |
| `classic_specific_evidence` | Directly supports the selected classic/P1999 profile | source, target profile, and why it applies |
| `inference` | Reasoned conclusion from incomplete/conflicting sources | inputs, reasoning, and review trigger |
| `temporary_fixture_default` | Original development-only data/tuning used to exercise a system | owner/system and replacement condition |
| `intentional_mobile_offline_deviation` | Deliberate EQ Mobile behavior difference | source behavior, mobile/offline reason, and impact |

An absence of a label means the claim is not ready to guide implementation.

## 4. Licensing and provenance boundary

- `resources/` is reference input. Never edit it and never treat it as
  distributable project content.
- Reference implementations inform clean Godot-native code; do not copy source
  code, protocol structures, or GPL implementation into EQ Mobile.
- Proprietary EverQuest files and derived extractions remain private reference
  material. They must not be packaged, redistributed, or represented as owned
  assets without explicit rights.
- Runtime project data must be project-owned or explicitly authorized. Every
  importer records source archive/version, source tables/files, transform,
  target-era filter, review state, and generation date when available.
- Generated data must preserve source IDs and provenance separately from
  project decisions. A reviewed correction overlay changes the derived output;
  it never rewrites raw source snapshots.

## 5. Required implementation record

Before a new system is considered foundationally complete, its documentation
must state: selected era profile, authority sources, evidence labels for its
material rules, import/provenance boundary, known uncertainty, and any mobile
or offline deviation. Add each deliberate difference to the registry below.

## 6. Deviation registry

The authoritative registry is [`deviation-registry.md`](deviation-registry.md).
Do not create competing deviation lists in feature documents. Feature documents
may link to a registry ID.
