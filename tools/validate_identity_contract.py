#!/usr/bin/env python3
"""Phase 2 checks for generated metadata, identity, and live cross-references."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEY = re.compile(r"^(eqm|peq|eqemu|client|fixture):[a-z_]+:[a-z0-9:_-]+$")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def validate_generated_envelope(data: dict, schema_id: str, dataset_id: str, label: str) -> None:
    require(data.get("schema_id") == schema_id, f"{label} schema_id is missing or wrong")
    require(data.get("schema_version") == 1, f"{label} schema_version is missing or unsupported")
    require(data.get("dataset_id") == dataset_id, f"{label} dataset_id is missing or wrong")
    meta = data.get("meta")
    require(isinstance(meta, dict), f"{label} metadata envelope is missing")
    require(meta.get("era_profile") == "original_classic_pre_kunark", f"{label} era profile is wrong")
    require(meta.get("design_target") == "classic_p1999", f"{label} design target is wrong")
    require(isinstance(meta.get("review_state"), str) and meta["review_state"], f"{label} review state is missing")
    require(isinstance(meta.get("evidence"), list) and meta["evidence"], f"{label} evidence is missing")
    require(isinstance(meta.get("sources"), list) and meta["sources"], f"{label} source provenance is missing")
    source = meta["sources"][0]
    require(isinstance(source.get("sha256"), str) and len(source["sha256"]) == 64, f"{label} source digest is missing")
    require(isinstance(meta.get("generator", {}).get("tool"), str), f"{label} generator is missing")
    require("filters" in meta and "overlay" in meta, f"{label} filters or overlay metadata is missing")


def main() -> None:
    zone = json.loads((ROOT / "data/halas.json").read_text())
    items = json.loads((ROOT / "data/items.json").read_text())["items"]
    classes = json.loads((ROOT / "data/player_classes.json").read_text())
    raw_npcs = json.loads((ROOT / "data/halas_npcs_source.json").read_text())
    derived_npcs = json.loads((ROOT / "data/halas_npcs.json").read_text())
    factions = json.loads((ROOT / "data/halas_factions_source.json").read_text())
    merchants = json.loads((ROOT / "data/halas_merchants_source.json").read_text())
    peq_items = json.loads((ROOT / "data/halas_items_source.json").read_text())
    loot = json.loads((ROOT / "data/halas_loot_source.json").read_text())
    class_registry = json.loads((ROOT / "data/eqemu_classes.json").read_text())
    race_registry = json.loads((ROOT / "data/eqemu_races.json").read_text())
    skill_registry = json.loads((ROOT / "data/eqemu_skills.json").read_text())
    spell_registry = json.loads((ROOT / "data/halas_spells_source.json").read_text())
    quests = json.loads((ROOT / "data/quests.json").read_text())
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
    validate_generated_envelope(raw_npcs, "eqm.halas.npcs.raw", "eqm:dataset:halas-npcs-raw", "raw NPC snapshot")
    validate_generated_envelope(derived_npcs, "eqm.halas.npcs.derived", "eqm:dataset:halas-npcs", "derived NPC snapshot")
    validate_generated_envelope(factions, "eqm.halas.factions.raw", "eqm:dataset:halas-factions-raw", "faction snapshot")
    validate_generated_envelope(merchants, "eqm.halas.merchants.raw", "eqm:dataset:halas-merchants-raw", "merchant snapshot")
    validate_generated_envelope(peq_items, "eqm.halas.items.raw", "eqm:dataset:halas-items-raw", "item snapshot")
    validate_generated_envelope(loot, "eqm.halas.loot.raw", "eqm:dataset:halas-loot-raw", "loot snapshot")
    for registry, dataset_id, label in (
        (class_registry, "eqm:dataset:eqemu-classes", "class registry"),
        (race_registry, "eqm:dataset:eqemu-races-halas", "race registry"),
        (skill_registry, "eqm:dataset:eqemu-skills", "skill registry"),
        (spell_registry, "eqm:dataset:halas-spell-closure", "spell registry"),
        (quests, "eqm:dataset:quests", "quest registry"),
    ):
        validate_generated_envelope(registry, "eqm.identity_registry", dataset_id, label)
    npc_keys = {npc["key"] for npc in derived_npcs["npc_types"]}
    class_keys = {definition["key"] for definition in class_registry["classes"].values()}
    race_keys = {definition["key"] for definition in race_registry["races"].values()}
    skill_keys = {definition["key"] for definition in skill_registry["skills"].values()}
    spell_keys = {definition["key"] for definition in spell_registry["spells"].values()}
    spell_list_keys = {definition["key"] for definition in spell_registry["npc_spell_lists"].values()}
    for source_id, definition in class_registry["classes"].items():
        require(definition["key"] == f"eqemu:class:{source_id}" and int(source_id) == definition["source_id"], f"class identity mismatch for {source_id}")
        require(definition["player_class"] == (1 <= definition["source_id"] <= 16), f"class player classification mismatch for {source_id}")
    for source_id, definition in race_registry["races"].items():
        require(definition["key"] == f"eqemu:race:{source_id}" and int(source_id) == definition["source_id"], f"race identity mismatch for {source_id}")
        require(isinstance(definition.get("source_symbol"), str) and definition["source_symbol"], f"race source symbol missing for {source_id}")
    seen_skill_ids = set()
    for source_id, definition in skill_registry["skills"].items():
        require(definition["key"] == f"eqemu:skill:{source_id}" and int(source_id) == definition["source_id"], f"skill identity mismatch for {source_id}")
        require(definition["source_id"] not in seen_skill_ids, f"duplicate skill identity {source_id}")
        seen_skill_ids.add(definition["source_id"])
    require("21" in skill_registry["skills"] and "SkillTailRake" in skill_registry["skills"]["21"]["aliases"], "Tail Rake must remain an alias of skill 21")
    for npc in derived_npcs["npc_types"]:
        require(npc["key"] == f"peq:npc:{npc['id']}", f"NPC typed key mismatch for {npc['id']}")
        require(npc["class_ref"] == f"eqemu:class:{npc['class']}", f"NPC class ref mismatch for {npc['id']}")
        require(npc["race_ref"] == f"eqemu:race:{npc['race']}", f"NPC race ref mismatch for {npc['id']}")
        require(npc["class_ref"] in class_keys, f"NPC class ref unresolved for {npc['id']}")
        require(npc["race_ref"] in race_keys, f"NPC race ref unresolved for {npc['id']}")
        raw_spell_list = int(npc["npc_spells_id"])
        expected_list = f"peq:npc_spell_list:{raw_spell_list}" if raw_spell_list > 0 else None
        require(npc.get("npc_spell_list_ref") == expected_list, f"NPC spell-list ref mismatch for {npc['id']}")
        if expected_list is not None:
            require(expected_list in spell_list_keys, f"NPC spell-list ref unresolved for {npc['id']}")
    spawn_group_keys = {group["key"] for group in derived_npcs["spawn_groups"].values()}
    for spawn in derived_npcs["spawns"]:
        require(spawn["key"] == f"peq:spawn:{spawn['spawn2_id']}", f"spawn typed key mismatch for {spawn['spawn2_id']}")
        require(spawn["spawn_group_ref"] in spawn_group_keys, "spawn group reference is unresolved")
        for candidate in spawn["candidates"]:
            require(candidate["npc_ref"] in npc_keys, "candidate NPC reference is unresolved")
    faction_keys = {definition["key"] for definition in factions["factions"].values()}
    bundle_keys = {definition["key"] for definition in factions["npc_faction_bundles"].values()}
    for faction_id, definition in factions["factions"].items():
        require(definition["key"] == f"peq:faction:{faction_id}", f"faction key mismatch for {faction_id}")
    for bundle_id, bundle in factions["npc_faction_bundles"].items():
        require(bundle["key"] == f"peq:npc_faction:{bundle_id}", f"NPC faction key mismatch for {bundle_id}")
        if int(bundle["primary_faction_id"]) > 0:
            require(bundle["primary_faction_ref"] in faction_keys, f"NPC faction {bundle_id} primary faction is unresolved")
        for entry in bundle["entries"]:
            if int(entry["faction_id"]) > 0:
                require(entry["faction_ref"] in faction_keys, f"NPC faction {bundle_id} entry is unresolved")
    peq_item_keys = {definition["key"] for definition in peq_items["items"].values()}
    for item_id, definition in peq_items["items"].items():
        require(definition["key"] == f"peq:item:{item_id}", f"item key mismatch for {item_id}")
    merchant_keys = set()
    for merchant_id, listings in merchants["merchants"].items():
        for listing in listings:
            require(listing["merchant_ref"] == f"peq:merchant:{merchant_id}", f"merchant key mismatch for {merchant_id}")
            require(listing["item_ref"] == f"peq:item:{listing['item_id']}", f"merchant item ref mismatch for {merchant_id}")
            require(listing["item_ref"] in peq_item_keys, f"merchant item ref unresolved for {merchant_id}")
            merchant_keys.add(listing["merchant_ref"])
    loot_drop_keys = {definition["key"] for definition in loot["loot_drops"].values()}
    loot_table_keys = {definition["key"] for definition in loot["loot_tables"].values()}
    for table_id, table in loot["loot_tables"].items():
        require(table["key"] == f"peq:loot_table:{table_id}", f"loot table key mismatch for {table_id}")
        for entry in table["entries"]:
            require(entry["loot_drop_ref"] in loot_drop_keys, f"loot table {table_id} drop ref unresolved")
    for drop_id, drop in loot["loot_drops"].items():
        require(drop["key"] == f"peq:loot_drop:{drop_id}", f"loot drop key mismatch for {drop_id}")
        for entry in drop["entries"]:
            require(entry["item_ref"] in peq_item_keys, f"loot drop {drop_id} item ref unresolved")
    for npc in derived_npcs["npc_types"]:
        if int(npc["npc_faction_id"]) > 0:
            require(npc["npc_faction_ref"] in bundle_keys, f"NPC faction ref unresolved for {npc['id']}")
        if int(npc["merchant_id"]) > 0:
            require(npc["merchant_ref"] in merchant_keys, f"NPC merchant ref unresolved for {npc['id']}")
        if int(npc["loottable_id"]) > 0:
            require(npc["loot_table_ref"] == f"peq:loot_table:{npc['loottable_id']}", f"NPC loot ref mismatch for {npc['id']}")
            require(npc["loot_table_ref"] in loot_table_keys, f"NPC loot ref unresolved for {npc['id']}")
    for source_id, spell in spell_registry["spells"].items():
        require(spell["key"] == f"peq:spell:{source_id}" and int(source_id) == spell["source_id"], f"spell identity mismatch for {source_id}")
        skill_ref = spell.get("casting_skill_ref")
        if skill_ref is not None:
            require(skill_ref in skill_keys, f"spell {source_id} has unresolved casting skill")
        if spell["casting_skill_id_raw"] == 98:
            require(skill_ref is None, "spell raw skill sentinel 98 must not fabricate a skill reference")
    parents = {}
    for source_id, spell_list in spell_registry["npc_spell_lists"].items():
        require(spell_list["key"] == f"peq:npc_spell_list:{source_id}" and int(source_id) == spell_list["source_id"], f"spell-list identity mismatch for {source_id}")
        parent = spell_list.get("parent_ref")
        if parent is not None:
            require(parent in spell_list_keys, f"spell-list parent unresolved for {source_id}")
            parents[spell_list["key"]] = parent
        for entry in spell_list["entries"]:
            require(entry["spell_ref"] in spell_keys, f"spell-list entry unresolved for {source_id}")
        for proc_ref in spell_list["proc_spell_refs"]:
            require(proc_ref in spell_keys, f"spell-list proc unresolved for {source_id}")
    for start in spell_list_keys:
        seen, current = set(), start
        while current in parents:
            require(current not in seen, f"spell-list parent cycle at {start}")
            seen.add(current)
            current = parents[current]
    require(quests["quests"] == {}, "unreviewed Phase 2 quest registry must remain empty")
    print("PASS: Phase 2 metadata envelopes and NPC, faction, merchant, item, and loot references are valid.")


if __name__ == "__main__":
    main()
