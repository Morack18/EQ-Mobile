#!/usr/bin/env python3
"""Guard Halas server-coordinate conversion against published P1999 /loc data.

P1999 displays locations as (Y, X); ProjectEQ spawn2 stores them as (X, Y, Z).
These independent, named checks prevent an accidental axis swap or mirror when
regenerating the Halas source snapshot.
"""

from __future__ import annotations

import json
from pathlib import Path


PUBLISHED_P1999_LOCATIONS = {
    "Dargon": (354, 356),
    "Toralia": (340, 480),
    "Bolace": (326, 482),
    "Tukanta": (356, 423),
    "Corak": (309, 424),
    "Oli_McMarrin": (13, -17),
    "Mils_McMarrin": (13, 17),
}


def server_to_halas_world(server_position: list[float]) -> tuple[float, float, float]:
    """Map PEQ spawn2 (X, Y, elevation) into the calibrated Halas frame."""
    x, y, elevation = server_position
    return (-y, elevation, x)


def main() -> None:
    source = Path("data/halas_npcs_source.json")
    content = json.loads(source.read_text())
    npc_names = {npc["id"]: npc["name"] for npc in content["npc_types"]}
    positions = {
        npc_names[spawn["candidates"][0]["npc_type_id"]]: spawn["position_eq"]
        for spawn in content["spawns"]
    }
    for name, p1999_location in PUBLISHED_P1999_LOCATIONS.items():
        server_x, server_y, elevation = positions[name]
        assert (server_y, server_x) == p1999_location, (
            f"{name}: server ({server_x}, {server_y}) does not map to "
            f"P1999 /loc {p1999_location}"
        )
        assert server_to_halas_world(positions[name]) == (
            -server_y,
            elevation,
            server_x,
        )
    print(
        f"Validated {len(PUBLISHED_P1999_LOCATIONS)} P1999 Halas locations "
        "and the Halas runtime transform."
    )


if __name__ == "__main__":
    main()
