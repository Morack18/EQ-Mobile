#!/usr/bin/env python3
"""Extract classic ProjectEQ merchant listings used by Halas NPCs.

Usage:
    python3 tools/import_peq_halas_merchants.py ARCHIVE OUTPUT
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

from import_peq_halas import as_int, rows_for_table


CLASSIC_EXPANSION = 0
SQL_MEMBER = "peq-dump/create_tables_content.sql"


def table_columns(archive: Path, table: str) -> dict[str, int]:
    """Read column order from the archived schema instead of guessing it."""
    marker = f"CREATE TABLE `{table}` ("
    columns: list[str] = []
    reading = False
    with zipfile.ZipFile(archive) as bundle, bundle.open(SQL_MEMBER) as raw:
        for raw_line in raw:
            line = raw_line.decode("latin-1").rstrip("\r\n")
            if line == marker:
                reading = True
                continue
            if not reading:
                continue
            if line.startswith(")"):
                break
            match = re.match(r"\s*`([^`]+)`", line)
            if match:
                columns.append(match.group(1))
    if not columns:
        raise SystemExit(f"Could not read {table} schema from {archive}")
    return {name: index for index, name in enumerate(columns)}


def available_in_classic(row: list[str]) -> bool:
    min_expansion = as_int(row[13])
    max_expansion = as_int(row[14])
    return (
        min_expansion in (-1, CLASSIC_EXPANSION)
        and max_expansion in (-1, CLASSIC_EXPANSION)
        and row[15] == "NULL"
        and row[16] == "NULL"
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    if not archive.is_file():
        raise SystemExit(f"Archive not found: {archive}")

    npc_source = Path("data/halas_npcs_source.json")
    npc_data = json.loads(npc_source.read_text())
    merchant_ids = {
        int(npc_type["merchant_id"])
        for npc_type in npc_data["npc_types"]
        if int(npc_type["merchant_id"]) > 0
    }
    merchants: dict[int, list[dict]] = {merchant_id: [] for merchant_id in merchant_ids}
    excluded = 0
    for row in rows_for_table(archive, "merchantlist"):
        merchant_id = as_int(row[0])
        if merchant_id not in merchants:
            continue
        if not available_in_classic(row):
            excluded += 1
            continue
        merchants[merchant_id].append({
            "slot": as_int(row[1]),
            "item_id": as_int(row[2]),
            "faction_required": as_int(row[3]),
            "level_required": as_int(row[4]),
            "min_status": as_int(row[5]),
            "max_status": as_int(row[6]),
            "alt_currency_cost": as_int(row[7]),
            "classes_required": as_int(row[8]),
            "probability": as_int(row[9]),
        })

    # Item names and base prices are available locally. They are source display
    # data, not a claim about final purchase prices (which can vary by faction,
    # charisma, and server rules).
    item_ids = {listing["item_id"] for listings in merchants.values() for listing in listings}
    item_columns = table_columns(archive, "items")
    if "id" not in item_columns or "Name" not in item_columns or "price" not in item_columns:
        raise SystemExit("items schema is missing id, Name, or price")
    item_details: dict[int, dict[str, object]] = {}
    for row in rows_for_table(archive, "items"):
        item_id = as_int(row[item_columns["id"]])
        if item_id not in item_ids:
            continue
        item_details[item_id] = {
            "item_name": row[item_columns["Name"]],
            "base_price": as_int(row[item_columns["price"]]),
        }
    missing_items = item_ids - set(item_details)
    if missing_items:
        raise SystemExit(f"Merchant listings reference missing items: {sorted(missing_items)}")
    for merchant_id, listings in merchants.items():
        for listing in listings:
            listing.update(item_details[listing["item_id"]])
            listing["item_ref"] = f"peq:item:{listing['item_id']}"
            listing["merchant_ref"] = f"peq:merchant:{merchant_id}"
    for listings in merchants.values():
        listings.sort(key=lambda listing: listing["slot"])

    result = {
        "schema_id": "eqm.halas.merchants.raw",
        "schema_version": 1,
        "dataset_id": "eqm:dataset:halas-merchants-raw",
        "meta": {
            "era_profile": "original_classic_pre_kunark",
            "design_target": "classic_p1999",
            "review_state": "current_unreviewed_peq",
            "evidence": [{"label": "confirmed_source_behavior", "claim": "PEQ merchant listings and item display fields"}],
            "sources": [{"namespace": "peq", "artifact": archive.name, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "member": SQL_MEMBER, "tables": ["merchantlist", "items"]}],
            "generator": {"tool": "tools/import_peq_halas_merchants.py"},
            "filters": {"referenced_by": "data/halas_npcs_source.json", "expansion_id": 0, "content_flags": "excluded"},
            "overlay": None,
        },
        "source": {
            "archive": archive.name,
            "table": "merchantlist",
            "npc_source": str(npc_source),
            "target_era": "classic_p1999",
            "filter": "classic expansion range; no content flags",
            "item_enrichment": "items.id -> items.Name, items.price (base price only)",
        },
        "merchants": merchants,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    listing_count = sum(len(listings) for listings in merchants.values())
    print(
        f"Wrote {listing_count} classic listings for {len(merchants)} Halas "
        f"merchant IDs ({excluded} non-classic/event listings excluded)."
    )


if __name__ == "__main__":
    main()
