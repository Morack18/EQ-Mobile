#!/usr/bin/env python3
"""Validate generated Halas faction references and EQEmu-default thresholds."""
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / "data/halas_factions_source.json").read_text())
EXPECTED = {"ally": 1100, "warmly": 750, "kindly": 500, "amiably": 100, "indifferently": 0, "apprehensively": -100, "dubiously": -500, "threateningly": -750}


def main() -> None:
    assert DATA["source"]["target_era"] == "classic_p1999"
    assert DATA["source"]["review_state"] == "current_unreviewed_peq"
    assert DATA["thresholds"] == EXPECTED
    factions = DATA["factions"]
    bundles = DATA["npc_faction_bundles"]
    assert len(bundles) == 7
    for bundle in bundles.values():
        primary = bundle["primary_faction_id"]
        assert primary <= 0 or str(primary) in factions
    for faction in factions.values():
        assert faction["personal_min"] <= faction["personal_max"]
        seen = set()
        for modifier in faction["modifiers"]:
            assert modifier["mod_name"] not in seen
            assert modifier["kind"] in {"class", "race", "deity"}
            seen.add(modifier["mod_name"])
    assert factions["404"]["personal_min"] == 0
    print(f"PASS: Halas faction data — {len(factions)} definitions, {len(bundles)} NPC bundles.")


if __name__ == "__main__":
    main()
