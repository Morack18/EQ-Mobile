#!/usr/bin/env python3
"""Structural checks for the source-shaped, fixture-tuned player combat data."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "data" / "player_classes.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    data = json.loads(DATA_PATH.read_text())
    require(data.get("schema_version") == 1, "expected schema version 1")
    warrior = data.get("classes", {}).get("1")
    require(isinstance(warrior, dict), "canonical Warrior class_id 1 is required")
    profile = warrior.get("attack_profile", {})
    require(profile.get("delay_tenths") == 35, "unarmed profile must use 35 EQ delay tenths")
    require(profile.get("damage_profile") == "training_fixture", "damage must stay behind fixture resolver")
    require(profile.get("requires_los") is True and profile.get("requires_facing") is True, "melee needs LOS and facing gates")
    ability = data.get("abilities", {}).get("training_strike")
    require(isinstance(ability, dict), "Training Strike ability is required")
    require(ability.get("kind") == "melee_skill", "Training Strike must remain a melee skill")
    require(ability.get("allowed_class_ids") == [1], "Training Strike must be Warrior-only for this slice")
    require(ability.get("required_level") == 1, "Training Strike must start at level 1")
    require(ability.get("cooldown_group") == "combat_ability", "ability needs a persistent shared cooldown group")
    require(ability.get("cooldown_seconds") == 5.0, "Training Strike must use its five-second fixture cooldown")
    require(ability.get("resource_type") == "none" and ability.get("resource_cost") == 0, "ability must not invent a resource system")
    print("PASS: player combat data — Warrior autoattack profile and Training Strike cooldown are valid.")


if __name__ == "__main__":
    main()
