#!/usr/bin/env python3
"""Extract classic-era Halas NPC content from a ProjectEQ SQL archive.

Usage:
    python3 tools/import_peq_halas.py resources/reference-data/projecteq/peq-<stamp>.zip data/halas_npcs_source.json

The raw archive is retained under resources/reference-data/projecteq. The output
is a source-data snapshot for the Godot importer: spawn locations, candidate
NPC types, patrol grids, and the server-side fields needed for later combat,
merchant, faction, and loot systems.

This importer deliberately targets original EverQuest (expansion 0), the
project's classic/P1999 content baseline. It accepts only base zone instances,
spawns available in that era, and spawns with no event content flags. It does
not claim that a current ProjectEQ dump is an exact P1999 database: any
P1999-specific roster or behavior correction belongs in a reviewed overlay.
"""

from __future__ import annotations

import csv
import io
import json
import re
import hashlib
import sys
import zipfile
from pathlib import Path


SQL_MEMBER = "peq-dump/create_tables_content.sql"
CLASSIC_EXPANSION = 0


def rows_for_table(archive: Path, table: str):
    """Stream simple mysqldump INSERT rows for one table."""
    marker = f"INSERT INTO `{table}` VALUES".encode()
    reading = False
    with zipfile.ZipFile(archive) as bundle, bundle.open(SQL_MEMBER) as raw:
        for raw_line in raw:
            line = raw_line.decode("latin-1").rstrip("\r\n")
            if line == marker.decode():
                reading = True
                continue
            if not reading:
                continue
            if not line.startswith("("):
                reading = False
                continue
            # Rows end in either `),` or `);`; both suffixes contain the
            # closing parenthesis plus one delimiter byte.
            payload = line[1:-2]
            yield next(csv.reader(
                io.StringIO(payload),
                delimiter=",",
                quotechar="'",
                escapechar="\\",
                doublequote=False,
            ))
            if line.endswith(";"):
                reading = False


def as_float(value: str) -> float:
    return float(value) if value != "NULL" else 0.0


def as_int(value: str) -> int:
    return int(float(value)) if value != "NULL" else 0


def is_available_in_classic(row: list[str]) -> bool:
    """Return whether a spawn2 row is available in original EverQuest.

    In the PEQ schema -1 means an unbounded expansion limit.  Event-gated
    spawns are excluded even when their expansion bounds are otherwise valid.
    """
    min_expansion = as_int(row[15])
    max_expansion = as_int(row[16])
    has_event_flags = row[17] != "NULL" or row[18] != "NULL"
    return (
        min_expansion in (-1, CLASSIC_EXPANSION)
        and max_expansion in (-1, CLASSIC_EXPANSION)
        and not has_event_flags
    )


def table_columns(archive: Path, table: str) -> dict[str, int]:
    """Read a PEQ table's column order for table-specific availability rules."""
    marker, names, reading = f"CREATE TABLE `{table}` (", [], False
    with zipfile.ZipFile(archive) as bundle, bundle.open(SQL_MEMBER) as raw:
        for raw_line in raw:
            line = raw_line.decode("latin-1").rstrip("\r\n")
            if line == marker:
                reading = True
            elif reading and line.startswith(")"):
                break
            elif reading:
                match = re.match(r"\s*`([^`]+)`", line)
                if match:
                    names.append(match.group(1))
    if not names:
        raise SystemExit(f"Could not read schema for {table}")
    return {name: index for index, name in enumerate(names)}


def spawnentry_available_in_classic(row: list[str], columns: dict[str, int]) -> bool:
    return (
        as_int(row[columns["min_expansion"]]) in (-1, CLASSIC_EXPANSION)
        and as_int(row[columns["max_expansion"]]) in (-1, CLASSIC_EXPANSION)
        and row[columns["content_flags"]] == "NULL"
        and row[columns["content_flags_disabled"]] == "NULL"
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive = Path(sys.argv[1])
    destination = Path(sys.argv[2])

    if not archive.is_file():
        raise SystemExit(f"Archive not found: {archive}")

    zone_id = None
    zone_table_id = None
    for row in rows_for_table(archive, "zone"):
        # grid_entries.zoneid stores zone.zoneidnumber (the client zone ID),
        # not zone.id (the PEQ table's auto-increment primary key).
        if row[3] == "halas" and as_int(row[2]) == 0:
            zone_table_id = as_int(row[0])
            zone_id = as_int(row[1])
            break
    if zone_id is None:
        raise SystemExit("Halas was not found in the PEQ zone table")

    spawns = []
    excluded_spawns = 0
    for row in rows_for_table(archive, "spawn2"):
        if row[2] != "halas" or as_int(row[3]) != 0:
            continue
        if not is_available_in_classic(row):
            excluded_spawns += 1
            continue
        spawns.append({
            "spawn2_id": as_int(row[0]),
            "spawn_group_id": as_int(row[1]),
            "position_eq": [as_float(row[4]), as_float(row[5]), as_float(row[6])],
            "heading_eq": as_float(row[7]),
            "respawn_seconds": as_int(row[8]),
            "grid_id": as_int(row[10]),
            "min_expansion": as_int(row[15]),
            "max_expansion": as_int(row[16]),
        })
    group_ids = {spawn["spawn_group_id"] for spawn in spawns}

    candidates: dict[int, list[dict]] = {group_id: [] for group_id in group_ids}
    npc_ids: set[int] = set()
    spawnentry_columns = table_columns(archive, "spawnentry")
    for row in rows_for_table(archive, "spawnentry"):
        group_id = as_int(row[0])
        if group_id not in candidates:
            continue
        if not spawnentry_available_in_classic(row, spawnentry_columns):
            continue
        npc_id = as_int(row[1])
        npc_ids.add(npc_id)
        candidates[group_id].append({"npc_type_id": npc_id, "chance": as_int(row[2])})

    npc_types = {}
    for row in rows_for_table(archive, "npc_types"):
        npc_id = as_int(row[0])
        if npc_id not in npc_ids:
            continue
        npc_types[npc_id] = {
            "id": npc_id,
            "name": row[1],
            "lastname": None if row[2] == "NULL" else row[2],
            "level": as_int(row[3]),
            "race": as_int(row[4]),
            "class": as_int(row[5]),
            "gender": as_int(row[9]),
            "texture": as_int(row[10]),
            # Preserve EQ's authoritative zero-based/default face ID.  The
            # extracted model head variants use the same convention.
            "face": as_int(row[33]),
            "size": as_float(row[13]),
            # Server-authoritative NPC values. Keep raw values rather than
            # deriving gameplay statistics from level or client appearance.
            "hp": as_int(row[7]),
            "mana": as_int(row[8]),
            "hp_regen_rate": as_int(row[14]),
            "hp_regen_per_second": as_int(row[15]),
            "loottable_id": as_int(row[17]),
            "merchant_id": as_int(row[18]),
            "npc_spells_id": as_int(row[21]),
            "npc_faction_id": as_int(row[23]),
            "mindmg": as_int(row[26]),
            "maxdmg": as_int(row[27]),
            "aggroradius": as_int(row[31]),
            "assistradius": as_int(row[32]),
            "armor_class": as_int(row[64]),
            "npc_aggro": as_int(row[65]),
            "attack_speed": as_float(row[67]),
            "attack_delay": as_int(row[68]),
            "run_speed": as_float(row[53]),
            "walk_speed": as_float(row[104]),
        }

    # Do not emit a runtime spawn whose selected NPC type is missing from the
    # archive. A small number of historic PEQ spawn entries can outlive their
    # npc_types record; retaining them would create a broken actor reference.
    missing_npc_type_spawns = 0
    valid_spawns = []
    for spawn in spawns:
        group_id = spawn["spawn_group_id"]
        candidates[group_id] = [
            candidate for candidate in candidates[group_id]
            if candidate["npc_type_id"] in npc_types
        ]
        if candidates[group_id]:
            valid_spawns.append(spawn)
        else:
            missing_npc_type_spawns += 1
    spawns = valid_spawns

    grid_ids = {spawn["grid_id"] for spawn in spawns if spawn["grid_id"] != 0}
    grids = {}
    for row in rows_for_table(archive, "grid_entries"):
        if as_int(row[1]) != zone_id:
            continue
        grid_id = as_int(row[0])
        if grid_id not in grid_ids:
            continue
        grids.setdefault(grid_id, []).append({
            "number": as_int(row[2]),
            "position_eq": [as_float(row[3]), as_float(row[4]), as_float(row[5])],
            "heading_eq": as_float(row[6]),
            # PEQ's grid_entries.pause is stored in seconds.
            "pause_seconds": as_int(row[7]),
        })
    for points in grids.values():
        points.sort(key=lambda point: point["number"])

    unavailable_grid_references = 0
    for spawn in spawns:
        if spawn["grid_id"] != 0 and spawn["grid_id"] not in grids:
            # Some historic PEQ spawn rows retain a pathgrid reference that has
            # no entries for this zone. It is not a valid Halas patrol route.
            spawn["unavailable_grid_id"] = spawn["grid_id"]
            spawn["grid_id"] = 0
            unavailable_grid_references += 1
        spawn["candidates"] = candidates[spawn["spawn_group_id"]]

    # Retain the group relationship as a first-class definition. Candidates are
    # duplicated on a spawn for backward-compatible runtime selection, but the
    # source distinction remains available to neutral-schema importers.
    spawn_groups = {
        str(group_id): {"id": group_id, "candidates": candidates[group_id]}
        for group_id in sorted({spawn["spawn_group_id"] for spawn in spawns})
    }

    result = {
        "schema_id": "eqm.halas.npcs.raw",
        "schema_version": 1,
        "dataset_id": "eqm:dataset:halas-npcs-raw",
        "meta": {
            "era_profile": "original_classic_pre_kunark",
            "design_target": "classic_p1999",
            "review_state": "current_unreviewed_peq",
            "evidence": [
                {
                    "label": "confirmed_source_behavior",
                    "claim": "PEQ spawn/group/NPC relationships",
                }
            ],
            "sources": [
                {
                    "namespace": "peq",
                    "artifact": archive.name,
                    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "member": SQL_MEMBER,
                    "tables": ["zone", "spawn2", "spawnentry", "npc_types", "grid_entries"],
                }
            ],
            "generator": {"tool": "tools/import_peq_halas.py"},
            "filters": {
                "zone_short_name": "halas",
                "zone_version": 0,
                "expansion_id": CLASSIC_EXPANSION,
                "content_flags": "excluded",
            },
            "overlay": None,
        },
        "source": {
            "archive": archive.name,
            "zone": "halas",
            "zone_id": zone_id,
            "zone_table_id": zone_table_id,
            "schema": "ProjectEQ content SQL",
            "target_era": "classic_p1999",
            "expansion_id": CLASSIC_EXPANSION,
            "spawn_filter": (
                "zone version 0; expansion range includes classic; "
                "no content flags or disabled-content flags"
            ),
            "p1999_overlay": "pending reviewed P1999-specific corrections",
        },
        "spawns": spawns,
        "spawn_groups": spawn_groups,
        "npc_types": list(npc_types.values()),
        "grids": grids,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(
        f"Wrote {len(spawns)} classic Halas spawns, {len(npc_types)} NPC types, "
        f"and {len(grids)} grids to {destination} "
        f"({excluded_spawns} non-classic/event, {missing_npc_type_spawns} "
        f"incomplete, and {unavailable_grid_references} cross-zone grid "
        f"references excluded)"
    )


if __name__ == "__main__":
    main()
