#!/usr/bin/env python3
"""Validate the original Training Spark combat/loot fixture data."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ZONE_PATH = ROOT / "data/halas.json"
ITEM_PATH = ROOT / "data/items.json"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def positive_number(value: Any, label: str) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        fail(f"{label} must be a positive finite number")


def main() -> None:
    zone = json.loads(ZONE_PATH.read_text())
    items_document = json.loads(ITEM_PATH.read_text())
    if zone.get("enable_training_npc") is not True:
        fail("enable_training_npc must be true for the playable vertical slice")
    positive_number(zone.get("player_respawn_seconds"), "player_respawn_seconds")
    items = items_document.get("items")
    if not isinstance(items, dict) or not items:
        fail("items.json must contain a non-empty items object")
    if items_document.get("source", {}).get("kind") != "original_development_fixture":
        fail("items.json must declare original_development_fixture provenance")
    archetype = zone.get("npc_archetypes", {}).get("training_spark")
    if not isinstance(archetype, dict):
        fail("missing training_spark archetype")
    for field in ("max_health", "damage", "move_speed", "aggro_range", "attack_range", "attack_cooldown"):
        positive_number(archetype.get(field), f"training_spark.{field}")
    rewards = archetype.get("loot")
    if not isinstance(rewards, list) or not rewards:
        fail("training_spark.loot must be a non-empty list")
    for index, reward in enumerate(rewards):
        if not isinstance(reward, dict) or set(reward) != {"item_id", "quantity"}:
            fail(f"loot entry {index} must contain only item_id and quantity")
        item_id = reward["item_id"]
        if not isinstance(item_id, str) or item_id not in items:
            fail(f"loot entry {index} references an undefined item")
        if not isinstance(reward["quantity"], int) or isinstance(reward["quantity"], bool) or reward["quantity"] <= 0:
            fail(f"loot entry {index}.quantity must be a positive integer")
    print(f"PASS: Training Spark fixture — {len(rewards)} rewards, {len(items)} original item definitions.")


if __name__ == "__main__":
    main()
