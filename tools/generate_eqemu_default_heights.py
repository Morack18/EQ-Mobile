#!/usr/bin/env python3
"""Generate the EQEmu race/gender default-height lookup from local source."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "resources/EQEmu-master/common/races.cpp"
DESTINATION = ROOT / "data/eqemu_default_heights.json"
FUNCTION = "GetRaceGenderDefaultHeight"


def array_values(source: str, name: str) -> list[float]:
    match = re.search(
        rf"static float {name}\[\] = \{{(.*?)\n\s*\}};",
        source,
        re.DOTALL,
    )
    if match is None:
        raise ValueError(f"{name} array not found")
    values = [float(value) for value in re.findall(r"(?<![\w.])(\d+(?:\.\d+)?)f", match.group(1))]
    if not values:
        raise ValueError(f"{name} array contains no float literals")
    return values


def main() -> None:
    source = SOURCE.read_text()
    function_start = source.find(f"float {FUNCTION}(")
    if function_start < 0:
        raise ValueError(f"{FUNCTION} not found")
    function_source = source[function_start:]
    female = array_values(function_source, "female_height")
    male = array_values(function_source, "male_height")
    if len(female) != len(male):
        raise ValueError("female_height and male_height lengths differ")

    result = {
        "source": {
            "path": "resources/EQEmu-master/common/races.cpp",
            "function": FUNCTION,
        },
        "heights": {
            race_id: {"male": male[race_id], "female": female[race_id]}
            for race_id in range(len(male))
        },
    }
    DESTINATION.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {len(male)} EQEmu race/gender default-height entries to {DESTINATION}")


if __name__ == "__main__":
    main()
