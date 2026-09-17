#!/usr/bin/env python3
"""Extract faction definitions referenced by the existing Halas NPC snapshot."""

from __future__ import annotations

import json
import re
import sys
import zipfile
from pathlib import Path

from import_peq_halas import as_int, rows_for_table


SQL_MEMBER = "peq-dump/create_tables_content.sql"
THRESHOLDS = {"ally": 1100, "warmly": 750, "kindly": 500, "amiably": 100,
              "indifferently": 0, "apprehensively": -100, "dubiously": -500,
              "threateningly": -750}


def columns(archive: Path, table: str) -> dict[str, int]:
    marker, result, reading = f"CREATE TABLE `{table}` (", [], False
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
                    result.append(match.group(1))
    if not result:
        raise SystemExit(f"Could not read {table} columns")
    return {name: index for index, name in enumerate(result)}


def field(row: list[str], mapping: dict[str, int], name: str) -> str:
    return row[mapping[name]]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: import_peq_halas_factions.py ARCHIVE OUTPUT")
    archive, output = Path(sys.argv[1]), Path(sys.argv[2])
    raw_npcs = json.loads((Path("data") / "halas_npcs_source.json").read_text())
    bundle_ids = {int(n["npc_faction_id"]) for n in raw_npcs["npc_types"] if int(n["npc_faction_id"]) > 0}
    npc_cols = columns(archive, "npc_faction")
    bundles: dict[int, dict] = {}
    for row in rows_for_table(archive, "npc_faction"):
        bundle_id = as_int(field(row, npc_cols, "id"))
        if bundle_id in bundle_ids:
            bundles[bundle_id] = {"id": bundle_id, "name": field(row, npc_cols, "name"),
                                  "primary_faction_id": as_int(field(row, npc_cols, "primaryfaction")),
                                  "ignore_primary_assist": as_int(field(row, npc_cols, "ignore_primary_assist")), "entries": []}
    missing = bundle_ids - set(bundles)
    if missing:
        raise SystemExit(f"Missing NPC faction bundles: {sorted(missing)}")
    entry_cols = columns(archive, "npc_faction_entries")
    faction_ids = {bundle["primary_faction_id"] for bundle in bundles.values() if bundle["primary_faction_id"] > 0}
    for row in rows_for_table(archive, "npc_faction_entries"):
        bundle_id = as_int(field(row, entry_cols, "npc_faction_id"))
        if bundle_id not in bundles:
            continue
        entry = {"faction_id": as_int(field(row, entry_cols, "faction_id")), "value": as_int(field(row, entry_cols, "value")),
                 "npc_value": as_int(field(row, entry_cols, "npc_value")), "temp": as_int(field(row, entry_cols, "temp"))}
        bundles[bundle_id]["entries"].append(entry)
        if entry["faction_id"] > 0:
            faction_ids.add(entry["faction_id"])
    list_cols, base_cols, mod_cols = columns(archive, "faction_list"), columns(archive, "faction_base_data"), columns(archive, "faction_list_mod")
    factions: dict[int, dict] = {}
    for row in rows_for_table(archive, "faction_list"):
        faction_id = as_int(field(row, list_cols, "id"))
        if faction_id in faction_ids:
            factions[faction_id] = {"id": faction_id, "name": field(row, list_cols, "name"), "base": as_int(field(row, list_cols, "base")), "modifiers": []}
    missing = faction_ids - set(factions)
    if missing:
        raise SystemExit(f"Missing faction definitions: {sorted(missing)}")
    bounds = {}
    for row in rows_for_table(archive, "faction_base_data"):
        faction_id = as_int(field(row, base_cols, "client_faction_id"))
        if faction_id in factions:
            bounds[faction_id] = (as_int(field(row, base_cols, "min")), as_int(field(row, base_cols, "max")))
    for faction_id, faction in factions.items():
        lower, upper = bounds.get(faction_id, (-2000, 2000))
        faction["personal_min"] = min(0, lower - faction["base"])
        faction["personal_max"] = max(0, upper - faction["base"])
    for row in rows_for_table(archive, "faction_list_mod"):
        faction_id = as_int(field(row, mod_cols, "faction_id"))
        if faction_id not in factions:
            continue
        mod_name = field(row, mod_cols, "mod_name")
        match = re.fullmatch(r"([crd])(\d+)", mod_name)
        if not match:
            continue
        kind = {"c": "class", "r": "race", "d": "deity"}[match.group(1)]
        factions[faction_id]["modifiers"].append({"mod_name": mod_name, "kind": kind,
                                                    "identity_id": int(match.group(2)), "value": as_int(field(row, mod_cols, "mod"))})
    for bundle in bundles.values():
        bundle["entries"].sort(key=lambda entry: entry["faction_id"])
    for faction in factions.values():
        faction["modifiers"].sort(key=lambda mod: mod["mod_name"])
    result = {"source": {"archive": archive.name, "schema": "ProjectEQ content SQL", "target_era": "classic_p1999", "review_state": "current_unreviewed_peq", "threshold_basis": "current_eqemu_defaults", "npc_source": "data/halas_npcs_source.json"}, "thresholds": THRESHOLDS, "factions": {str(key): factions[key] for key in sorted(factions)}, "npc_faction_bundles": {str(key): bundles[key] for key in sorted(bundles)}}
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {len(factions)} faction definitions and {len(bundles)} NPC faction bundles.")


if __name__ == "__main__":
    main()
