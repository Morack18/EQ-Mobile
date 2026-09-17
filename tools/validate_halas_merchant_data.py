#!/usr/bin/env python3
"""Validate the classic merchant snapshot referenced by the Halas NPC roster.

The snapshot deliberately contains listings only, not item names or prices: those
belong to the future neutral item-definition import.  This gate keeps the
merchant IDs, listing order, and access fields safe to consume when that system
arrives.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
NPC_SOURCE = ROOT / "data/halas_npcs_source.json"
MERCHANT_SOURCE = ROOT / "data/halas_merchants_source.json"
LISTING_FIELDS = {
    "slot",
    "item_id",
    "item_name",
    "base_price",
    "faction_required",
    "level_required",
    "min_status",
    "max_status",
    "alt_currency_cost",
    "classes_required",
    "probability",
}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        fail(f"{label} must be an integer")
    return value


def main() -> None:
    npc_content = json.loads(NPC_SOURCE.read_text())
    merchant_content = json.loads(MERCHANT_SOURCE.read_text())
    source = merchant_content.get("source")
    merchants = merchant_content.get("merchants")
    if not isinstance(source, dict) or source.get("target_era") != "classic_p1999":
        fail("merchant source must declare target_era classic_p1999")
    if source.get("npc_source") != "data/halas_npcs_source.json":
        fail("merchant source must identify the Halas NPC snapshot")
    if not isinstance(merchants, dict):
        fail("merchants must be an object keyed by merchant ID")

    expected_ids = {
        integer(npc_type.get("merchant_id"), "npc merchant_id")
        for npc_type in npc_content.get("npc_types", [])
        if integer(npc_type.get("merchant_id"), "npc merchant_id") > 0
    }
    actual_ids: set[int] = set()
    listing_count = 0
    for merchant_id_text, listings in merchants.items():
        try:
            merchant_id = int(merchant_id_text)
        except (TypeError, ValueError):
            fail(f"merchant ID {merchant_id_text!r} is not an integer")
        if merchant_id <= 0:
            fail(f"merchant ID {merchant_id} must be positive")
        if merchant_id in actual_ids:
            fail(f"duplicate merchant ID {merchant_id}")
        actual_ids.add(merchant_id)
        if not isinstance(listings, list) or not listings:
            fail(f"merchant {merchant_id} has no listings")
        previous_slot = 0
        slots: set[int] = set()
        for index, listing in enumerate(listings):
            label = f"merchant {merchant_id} listing {index}"
            if not isinstance(listing, dict) or set(listing) != LISTING_FIELDS:
                fail(f"{label} must contain exactly the supported listing fields")
            numeric_fields = LISTING_FIELDS - {"item_name"}
            values = {field: integer(listing[field], f"{label}.{field}") for field in numeric_fields}
            slot = values["slot"]
            if slot <= 0 or slot in slots or slot <= previous_slot:
                fail(f"{label}.slot must be positive, unique, and ascending")
            if values["item_id"] <= 0:
                fail(f"{label}.item_id must be positive")
            if not isinstance(listing["item_name"], str) or not listing["item_name"].strip():
                fail(f"{label}.item_name must be a non-empty string")
            if values["base_price"] < 0:
                fail(f"{label}.base_price must be non-negative")
            if values["level_required"] < 0 or values["alt_currency_cost"] < 0 or values["classes_required"] < 0:
                fail(f"{label} has a negative level, currency cost, or class mask")
            if not 0 <= values["min_status"] <= values["max_status"] <= 255:
                fail(f"{label} has an invalid status range")
            if not 0 <= values["probability"] <= 100:
                fail(f"{label}.probability must be in [0, 100]")
            slots.add(slot)
            previous_slot = slot
            listing_count += 1

    if actual_ids != expected_ids:
        fail(
            "merchant IDs do not match the NPC roster: "
            f"missing={sorted(expected_ids - actual_ids)}, extra={sorted(actual_ids - expected_ids)}"
        )
    print(f"PASS: Halas merchant data — {len(actual_ids)} merchants, {listing_count} classic listings.")


if __name__ == "__main__":
    main()
