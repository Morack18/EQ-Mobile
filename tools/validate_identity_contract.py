#!/usr/bin/env python3
"""Phase 2 checks for currently live typed identities and source references."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEY = re.compile(r"^(eqm|peq|eqemu|client|fixture):[a-z_]+:[a-z0-9:_-]+$")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    zone = json.loads((ROOT / "data/halas.json").read_text())
    items = json.loads((ROOT / "data/items.json").read_text())["items"]
    classes = json.loads((ROOT / "data/player_classes.json").read_text())
    derived_npcs = json.loads((ROOT / "data/halas_npcs.json").read_text())
    require(zone.get("schema_id") == "eqm.zone_definition" and zone.get("schema_version") == 1, "zone definition schema metadata missing")
    require(zone.get("key") == "eqm:zone:halas" and KEY.fullmatch(zone["key"]) is not None, "zone key is invalid")
    require(zone.get("source_refs", {}).get("client_geometry") == "client:zone_geometry:halas", "zone geometry source ref missing")
    era = zone.get("era_metadata", {})
    require(era.get("era_profile") == "original_classic_pre_kunark", "zone must select canonical era profile")
    require(era.get("design_target") == "classic_p1999", "zone design target missing")
    for item_key, definition in items.items():
        require(KEY.fullmatch(item_key) is not None and item_key.startswith("fixture:item:"), f"invalid fixture item key {item_key}")
        require(definition.get("key") == item_key, f"item definition key mismatch for {item_key}")
    require("1" in classes.get("classes", {}), "Warrior source class definition missing")
    require(classes["classes"]["1"].get("identity_key") == "eqemu:class:1", "Warrior must expose typed class identity")
    npc_keys = {npc["key"] for npc in derived_npcs["npc_types"]}
    for npc in derived_npcs["npc_types"]:
        require(npc["key"] == f"peq:npc:{npc['id']}", f"NPC typed key mismatch for {npc['id']}")
    spawn_group_keys = {group["key"] for group in derived_npcs["spawn_groups"].values()}
    for spawn in derived_npcs["spawns"]:
        require(spawn["key"] == f"peq:spawn:{spawn['spawn2_id']}", f"spawn typed key mismatch for {spawn['spawn2_id']}")
        require(spawn["spawn_group_ref"] in spawn_group_keys, "spawn group reference is unresolved")
        for candidate in spawn["candidates"]:
            require(candidate["npc_ref"] in npc_keys, "candidate NPC reference is unresolved")
    print("PASS: Phase 2 live identity contract — zone, fixture item, and player class identities are valid.")


if __name__ == "__main__":
    main()
