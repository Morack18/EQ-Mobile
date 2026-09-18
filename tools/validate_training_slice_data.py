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
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value <= 0
    ):
        fail(f"{label} must be a positive finite number")


def nonnegative_number(value: Any, label: str) -> None:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value < 0
    ):
        fail(f"{label} must be a non-negative finite number")


def require_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def main() -> None:
    zone = json.loads(ZONE_PATH.read_text())
    items_document = json.loads(ITEM_PATH.read_text())

    if zone.get("enable_training_npc") is not True:
        fail(
            "enable_training_npc must be true for the playable vertical slice"
        )

    positive_number(
        zone.get("player_respawn_seconds"),
        "player_respawn_seconds",
    )

    progression = require_dict(
        zone.get("progression"),
        "progression",
    )

    if progression.get("formula_version") != 1:
        fail("progression must declare formula_version 1")

    if (
        not isinstance(progression.get("max_level"), int)
        or isinstance(progression.get("max_level"), bool)
        or progression["max_level"] < 1
    ):
        fail("progression.max_level must be a positive integer")

    items = items_document.get("items")

    if not isinstance(items, dict) or not items:
        fail("items.json must contain a non-empty items object")

    if (
        items_document.get("source", {}).get("kind")
        != "original_development_fixture"
    ):
        fail(
            "items.json must declare "
            "original_development_fixture provenance"
        )

    for item_key, item in items.items():
        if (
            not item_key.startswith("fixture:")
            or not isinstance(item, dict)
        ):
            fail(
                "fixture item keys must be namespaced "
                "and definitions must be objects"
            )

        if (
            not isinstance(item.get("name"), str)
            or not item["name"].strip()
        ):
            fail(f"item {item_key} must have a name")

        if (
            not isinstance(item.get("stackable"), bool)
            or not isinstance(item.get("stack_size"), int)
            or isinstance(item.get("stack_size"), bool)
            or item["stack_size"] < 1
        ):
            fail(
                f"item {item_key} must declare a valid stack policy"
            )

    archetypes = require_dict(
        zone.get("npc_archetypes"),
        "npc_archetypes",
    )

    archetype = archetypes.get("training_spark")

    if not isinstance(archetype, dict):
        fail("missing training_spark archetype")

    if archetype.get("key") != "fixture:npc:training_spark":
        fail(
            "training_spark.key must be "
            "fixture:npc:training_spark"
        )

    if archetype.get("evidence") != "temporary_fixture_default":
        fail(
            "training_spark must retain "
            "temporary_fixture_default provenance"
        )

    if (
        not isinstance(archetype.get("name"), str)
        or not archetype["name"].strip()
    ):
        fail("training_spark.name must be non-empty")

    positive_number(
        archetype.get("max_health"),
        "training_spark.max_health",
    )

    positive_number(
        archetype.get("combat_size"),
        "training_spark.combat_size",
    )

    nonnegative_number(
        archetype.get("death_delay_seconds"),
        "training_spark.death_delay_seconds",
    )

    behavior = require_dict(
        archetype.get("behavior"),
        "training_spark.behavior",
    )

    positive_number(
        behavior.get("move_speed"),
        "training_spark.behavior.move_speed",
    )

    positive_number(
        behavior.get("aggro_range"),
        "training_spark.behavior.aggro_range",
    )

    combat = require_dict(
        archetype.get("combat"),
        "training_spark.combat",
    )

    combat_id = combat.get("id")

    if (
        not isinstance(combat_id, str)
        or not combat_id.startswith("fixture:")
    ):
        fail(
            "training_spark.combat.id must be a namespaced "
            "fixture identifier"
        )

    positive_number(
        combat.get("damage_min"),
        "training_spark.combat.damage_min",
    )

    positive_number(
        combat.get("damage_max"),
        "training_spark.combat.damage_max",
    )

    if combat["damage_max"] < combat["damage_min"]:
        fail(
            "training_spark.combat.damage_max "
            "must be >= damage_min"
        )

    positive_number(
        combat.get("range"),
        "training_spark.combat.range",
    )

    positive_number(
        combat.get("cooldown_seconds"),
        "training_spark.combat.cooldown_seconds",
    )

    cooldown_group = combat.get("cooldown_group")

    if (
        not isinstance(cooldown_group, str)
        or not cooldown_group.strip()
    ):
        fail(
            "training_spark.combat.cooldown_group "
            "must be non-empty"
        )

    for flag in ("requires_facing", "requires_los"):
        if not isinstance(combat.get(flag), bool):
            fail(
                f"training_spark.combat.{flag} must be boolean"
            )

    rewards = require_dict(
        archetype.get("rewards"),
        "training_spark.rewards",
    )

    xp_reward = rewards.get("xp")

    if (
        not isinstance(xp_reward, int)
        or isinstance(xp_reward, bool)
        or xp_reward <= 0
    ):
        fail(
            "training_spark.rewards.xp must be "
            "a positive fixture-tuning integer"
        )

    reward_items = rewards.get("items")

    if not isinstance(reward_items, list) or not reward_items:
        fail(
            "training_spark.rewards.items "
            "must be a non-empty list"
        )

    for index, reward in enumerate(reward_items):
        if not isinstance(reward, dict):
            fail(
                f"reward entry {index} must be an object"
            )

        if set(reward) != {"item_key", "quantity"}:
            fail(
                f"reward entry {index} must contain only "
                "item_key and quantity"
            )

        item_key = reward["item_key"]

        if (
            not isinstance(item_key, str)
            or item_key not in items
        ):
            fail(
                f"reward entry {index} references "
                "an undefined fixture item"
            )

        quantity = reward["quantity"]

        if (
            not isinstance(quantity, int)
            or isinstance(quantity, bool)
            or quantity <= 0
        ):
            fail(
                f"reward entry {index}.quantity "
                "must be a positive integer"
            )

    spawns = zone.get("spawns")

    if not isinstance(spawns, list) or not spawns:
        fail(
            "Halas zone must contain the Training Spark spawn"
        )

    training_spawn = next(
        (
            spawn
            for spawn in spawns
            if isinstance(spawn, dict)
            and spawn.get("id") == "training_spark"
        ),
        None,
    )

    if training_spawn is None:
        fail("missing training_spark spawn")

    if (
        training_spawn.get("key")
        != "fixture:spawn:training_spark"
    ):
        fail(
            "training_spark spawn key must be "
            "fixture:spawn:training_spark"
        )

    if (
        training_spawn.get("definition_ref")
        != archetype["key"]
    ):
        fail(
            "training_spark spawn definition_ref "
            "must reference its fixture NPC definition"
        )

    if training_spawn.get("archetype") != "training_spark":
        fail(
            "training_spark spawn archetype reference is invalid"
        )

    positive_number(
        training_spawn.get("respawn_seconds"),
        "training_spark spawn respawn_seconds",
    )

    position = training_spawn.get("position")

    if (
        not isinstance(position, list)
        or len(position) != 3
        or any(
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            for value in position
        )
    ):
        fail(
            "training_spark spawn position must contain "
            "three finite numbers"
        )

    print(
        "PASS: Training Spark fixture — "
        f"{len(reward_items)} rewards, "
        f"{len(items)} original item definitions; "
        "nested behavior/combat/reward schema is valid."
    )


if __name__ == "__main__":
    main()
