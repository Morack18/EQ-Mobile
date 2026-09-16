#!/usr/bin/env python3
"""Extract classic ProjectEQ merchant listings used by Halas NPCs.

Usage:
    python3 tools/import_peq_halas_merchants.py ARCHIVE OUTPUT
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from import_peq_halas import as_int, rows_for_table


CLASSIC_EXPANSION = 0


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
    for listings in merchants.values():
        listings.sort(key=lambda listing: listing["slot"])

    result = {
        "source": {
            "archive": archive.name,
            "table": "merchantlist",
            "npc_source": str(npc_source),
            "target_era": "classic_p1999",
            "filter": "classic expansion range; no content flags",
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
