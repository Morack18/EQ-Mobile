#!/usr/bin/env python3
"""Generate neutral ItemDefinition and LootTable snapshots used by Halas.

The importer deliberately follows references outward from the current Halas NPC
snapshot and merchant snapshot. It does not claim to be a full PEQ item export,
and it never flattens loot drops into an NPC's runtime row.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from import_peq_halas import CLASSIC_EXPANSION, SQL_MEMBER, as_float, as_int, rows_for_table, table_columns


ROOT = Path(__file__).resolve().parents[1]


def available_in_classic(row: list[str], columns: dict[str, int]) -> bool:
    """Return true for rows available to the default pre-Kunark profile."""
    return (
        as_int(row[columns["min_expansion"]]) in (-1, CLASSIC_EXPANSION)
        and as_int(row[columns["max_expansion"]]) in (-1, CLASSIC_EXPANSION)
        and row[columns["content_flags"]] == "NULL"
        and row[columns["content_flags_disabled"]] == "NULL"
    )


def required(row: list[str], columns: dict[str, int], name: str) -> str:
    if name not in columns:
        raise SystemExit(f"PEQ {name} column is unavailable")
    return row[columns[name]]


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("Usage: import_peq_halas_items_loot.py ARCHIVE ITEMS_OUTPUT LOOT_OUTPUT")
    archive = Path(sys.argv[1])
    items_output, loot_output = Path(sys.argv[2]), Path(sys.argv[3])
    if not archive.is_file():
        raise SystemExit(f"Archive not found: {archive}")

    raw_npcs = json.loads((ROOT / "data/halas_npcs_source.json").read_text())
    merchants = json.loads((ROOT / "data/halas_merchants_source.json").read_text())
    table_ids = {int(npc["loottable_id"]) for npc in raw_npcs["npc_types"] if int(npc["loottable_id"]) > 0}

    table_columns_by_name = {name: table_columns(archive, name) for name in ["loottable", "loottable_entries", "lootdrop", "lootdrop_entries", "items"]}
    tables: dict[int, dict] = {}
    for row in rows_for_table(archive, "loottable"):
        columns = table_columns_by_name["loottable"]
        table_id = as_int(required(row, columns, "id"))
        if table_id in table_ids and available_in_classic(row, columns):
            tables[table_id] = {
                "id": table_id,
                "key": f"peq:loot_table:{table_id}",
                "name": required(row, columns, "name"),
                "cash": {"min_copper": as_int(required(row, columns, "mincash")), "max_copper": as_int(required(row, columns, "maxcash")), "average_coin": as_int(required(row, columns, "avgcoin"))},
                "entries": [],
            }
    missing_tables = table_ids - tables.keys()
    if missing_tables:
        raise SystemExit(f"Halas NPCs reference unavailable classic loot tables: {sorted(missing_tables)}")

    drop_ids: set[int] = set()
    for row in rows_for_table(archive, "loottable_entries"):
        columns = table_columns_by_name["loottable_entries"]
        table_id = as_int(required(row, columns, "loottable_id"))
        if table_id not in tables:
            continue
        drop_id = as_int(required(row, columns, "lootdrop_id"))
        tables[table_id]["entries"].append({
            "loot_drop_ref": f"peq:loot_drop:{drop_id}",
            "multiplier": as_int(required(row, columns, "multiplier")),
            "drop_limit": as_int(required(row, columns, "droplimit")),
            "min_drop": as_int(required(row, columns, "mindrop")),
            "probability_percent": as_float(required(row, columns, "probability")),
        })
        drop_ids.add(drop_id)

    drops: dict[int, dict] = {}
    for row in rows_for_table(archive, "lootdrop"):
        columns = table_columns_by_name["lootdrop"]
        drop_id = as_int(required(row, columns, "id"))
        if drop_id in drop_ids and available_in_classic(row, columns):
            drops[drop_id] = {"id": drop_id, "key": f"peq:loot_drop:{drop_id}", "name": required(row, columns, "name"), "entries": []}
    missing_drops = drop_ids - drops.keys()
    if missing_drops:
        raise SystemExit(f"Halas loot tables reference unavailable classic loot drops: {sorted(missing_drops)}")

    item_ids = {int(listing["item_id"]) for listings in merchants["merchants"].values() for listing in listings}
    for row in rows_for_table(archive, "lootdrop_entries"):
        columns = table_columns_by_name["lootdrop_entries"]
        drop_id = as_int(required(row, columns, "lootdrop_id"))
        if drop_id not in drops or not available_in_classic(row, columns):
            continue
        item_id = as_int(required(row, columns, "item_id"))
        drops[drop_id]["entries"].append({
            "item_ref": f"peq:item:{item_id}",
            "charges": as_int(required(row, columns, "item_charges")),
            "equip": bool(as_int(required(row, columns, "equip_item"))),
            "chance": as_float(required(row, columns, "chance")),
            "disabled_chance": as_float(required(row, columns, "disabled_chance")),
            "multiplier": as_int(required(row, columns, "multiplier")),
            "npc_level_range": [as_int(required(row, columns, "npc_min_level")), as_int(required(row, columns, "npc_max_level"))],
        })
        item_ids.add(item_id)

    items: dict[int, dict] = {}
    for row in rows_for_table(archive, "items"):
        columns = table_columns_by_name["items"]
        item_id = as_int(required(row, columns, "id"))
        if item_id not in item_ids:
            continue
        items[item_id] = {
            "id": item_id,
            "key": f"peq:item:{item_id}",
            "name": required(row, columns, "Name"),
            "item_class": as_int(required(row, columns, "itemclass")),
            "item_type": as_int(required(row, columns, "itemtype")),
            "price_copper": as_int(required(row, columns, "price")),
            "sell_rate": as_float(required(row, columns, "sellrate")),
            "stackable": bool(as_int(required(row, columns, "stackable"))),
            "stack_size": as_int(required(row, columns, "stacksize")),
            "max_charges": as_int(required(row, columns, "maxcharges")),
            "weight_tenths": as_int(required(row, columns, "weight")),
            "size": as_int(required(row, columns, "size")),
            "equip_slots_mask": as_int(required(row, columns, "slots")),
            "classes_mask": as_int(required(row, columns, "classes")),
            "races_mask": as_int(required(row, columns, "races")),
            "required_level": as_int(required(row, columns, "reqlevel")),
            "lore_group": as_int(required(row, columns, "loregroup")),
            "container": {"slots": as_int(required(row, columns, "bagslots")), "size": as_int(required(row, columns, "bagsize")), "type": as_int(required(row, columns, "bagtype")), "weight_reduction": as_int(required(row, columns, "bagwr"))} if as_int(required(row, columns, "bagslots")) > 0 else None,
        }
    missing_items = item_ids - items.keys()
    if missing_items:
        raise SystemExit(f"Halas merchant/loot references missing item definitions: {sorted(missing_items)}")

    archive_sha256 = hashlib.sha256(archive.read_bytes()).hexdigest()
    provenance = {
        "era_profile": "original_classic_pre_kunark",
        "design_target": "classic_p1999",
        "review_state": "current_unreviewed_peq",
        "evidence": [{"label": "confirmed_source_behavior", "claim": "PEQ item and reusable loot table relationships"}],
        "sources": [{"namespace": "peq", "artifact": archive.name, "sha256": archive_sha256, "member": SQL_MEMBER, "tables": ["items", "loottable", "loottable_entries", "lootdrop", "lootdrop_entries"]}],
        "generator": {"tool": "tools/import_peq_halas_items_loot.py"},
        "filters": {"referenced_by": ["data/halas_npcs_source.json", "data/halas_merchants_source.json"], "expansion_id": CLASSIC_EXPANSION, "content_flags": "excluded"},
        "overlay": None,
    }
    items_data = {"schema_id": "eqm.halas.items.raw", "schema_version": 1, "dataset_id": "eqm:dataset:halas-items-raw", "meta": provenance, "items": {str(item_id): items[item_id] for item_id in sorted(items)}}
    loot_data = {"schema_id": "eqm.halas.loot.raw", "schema_version": 1, "dataset_id": "eqm:dataset:halas-loot-raw", "meta": provenance, "loot_tables": {str(table_id): tables[table_id] for table_id in sorted(tables)}, "loot_drops": {str(drop_id): drops[drop_id] for drop_id in sorted(drops)}}
    items_output.write_text(json.dumps(items_data, indent=2, sort_keys=True) + "\n")
    loot_output.write_text(json.dumps(loot_data, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {len(items)} item definitions, {len(tables)} loot tables, and {len(drops)} loot drops.")


if __name__ == "__main__":
    main()
