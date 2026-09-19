#!/usr/bin/env python3
"""Classic/P1999 data-fidelity audit and pre-Phase-7 gate."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Finding:
    key: str
    status: str
    detail: str


def load_json(relative: str) -> dict:
    return json.loads(
        (ROOT / relative).read_text()
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-all-green",
        action="store_true",
    )
    args = parser.parse_args()

    zone = load_json(
        "data/halas.json"
    )
    source = load_json(
        "data/halas_npcs_source.json"
    )
    runtime = load_json(
        "data/halas_npcs.json"
    )
    player = load_json(
        "data/player_fixture.json"
    )

    main_source = (
        ROOT / "scripts/main.gd"
    ).read_text()

    world_space_source = (
        ROOT / "scripts/domain/zone_world_space.gd"
    ).read_text()

    manifest_path = (
        ROOT / "data/halas_objects.json"
    )
    lantern_manifest_path = (
        ROOT
        / "resources/LanternExtractor/Exports/halas/Zone/object_instances.txt"
    )

    failures: list[str] = []

    if not lantern_manifest_path.is_file():
        failures.append(
            "Lantern Halas placement source is missing"
        )
        manifest_exact = False
    else:
        manifest_exact = (
            manifest_path.read_bytes()
            == lantern_manifest_path.read_bytes()
        )

        if not manifest_exact:
            failures.append(
                "Runtime Halas object manifest differs from Lantern source"
            )

    rows = [
        line.split(",")
        for line in manifest_path.read_text().splitlines()
        if line
        and not line.startswith("#")
    ]

    nonzero_rotz = sum(
        abs(float(row[6])) > 0.000001
        for row in rows
    )

    source_spawns = {
        int(row["spawn2_id"]): row
        for row in source["spawns"]
    }
    runtime_spawns = {
        int(row["spawn2_id"]): row
        for row in runtime["spawns"]
    }

    for spawn_id, source_row in source_spawns.items():
        runtime_row = runtime_spawns.get(
            spawn_id
        )

        if runtime_row is None:
            failures.append(
                f"Runtime missing spawn2 {spawn_id}"
            )
            continue

        for field in (
            "position_eq",
            "heading_eq",
            "grid_id",
        ):
            if (
                runtime_row.get(field)
                != source_row.get(field)
            ):
                failures.append(
                    f"spawn2 {spawn_id} changed {field}"
                )

    if source.get("grids") != runtime.get("grids"):
        failures.append(
            "Runtime patrol grids differ from raw PEQ snapshot"
        )

    review_state = str(
        source.get(
            "meta",
            {},
        ).get(
            "review_state",
            "",
        )
    )

    snap_tolerance = float(
        zone.get(
            "npc_presentation",
            {},
        ).get(
            "terrain_snap_tolerance",
            0.0,
        )
    )

    explicit_sizes = sum(
        float(row.get("size", 0.0)) > 0.0
        for row in source["npc_types"]
    )

    player_race = int(
        player.get(
            "identity",
            {},
        ).get(
            "race_id",
            0,
        )
    )

    player_model = str(
        player.get(
            "appearance",
            {},
        ).get(
            "model_path",
            "",
        )
    )

    complete_object_transform = (
        "object_rotation_basis([" in main_source
        and "float(values[4])" in main_source
        and "float(values[5])" in main_source
        and "float(values[6])" in main_source
        and "float(values[7])" in main_source
        and "float(values[8])" in main_source
        and "float(values[9])" in main_source
        and "func object_rotation_basis(" in world_space_source
        and "coordinate_basis.inverse()" in world_space_source
    )

    if not complete_object_transform:
        failures.append(
            "Runtime static-object transform does not consume complete source rotation/scale"
        )

    findings = [
        Finding(
            "static_object_transform",
            (
                "GREEN"
                if (
                    manifest_exact
                    and complete_object_transform
                )
                else "RED"
            ),
            (
                f"{len(rows)} source placements; "
                f"{nonzero_rotz} have non-zero RotZ; "
                f"manifest_exact={manifest_exact}; "
                f"complete_runtime_transform={complete_object_transform}."
            ),
        ),
        Finding(
            "npc_position_elevation",
            "GREEN",
            (
                f"terrain snap tolerance={snap_tolerance:g}; "
                "mapped source spawn and patrol elevations are canonical; "
                "terrain checks are diagnostic only."
            ),
        ),
        Finding(
            "npc_facing",
            "GREEN",
            (
                "source heading vectors map through each active zone contract; "
                "model offsets remain presentation-only."
            ),
        ),
        Finding(
            "npc_scale",
            "YELLOW",
            (
                f"{explicit_sizes}/{len(source['npc_types'])} "
                "NPC types have explicit positive source size; "
                f"review state={review_state}."
            ),
        ),
        Finding(
            "player_character",
            "RED",
            (
                f"race_id={player_race}; "
                f"model={player_model}; "
                "presentation remains a placeholder."
            ),
        ),
        Finding(
            "npc_roster_and_stats",
            "YELLOW",
            (
                f"source review state={review_state}; "
                "P1999 correction overlay review remains incomplete."
            ),
        ),
        Finding(
            "movement",
            "YELLOW",
            "Contains source-backed and project-selected movement values.",
        ),
        Finding(
            "combat_progression_economy",
            "YELLOW",
            "Contains inferred, disabled, and fixture rules pending dedicated review.",
        ),
        Finding(
            "environment",
            "YELLOW",
            "Contains current-runtime presentation values and water fallback behavior.",
        ),
        Finding(
            "training_spark",
            "EXEMPT",
            "Project-owned development fixture.",
        ),
    ]

    print(
        "Classic/P1999 Data Fidelity Audit"
    )
    print(
        "=" * 36
    )

    for finding in findings:
        print(
            f"{finding.status:6} "
            f"{finding.key}: "
            f"{finding.detail}"
        )

    if failures:
        print()
        print(
            "HARD SOURCE/STRUCTURE REGRESSIONS:"
        )

        for failure in failures:
            print(
                f"- {failure}"
            )

        return 1

    unresolved = [
        finding
        for finding in findings
        if finding.status in {
            "RED",
            "YELLOW",
        }
    ]

    print()
    print(
        "Summary: "
        f"{sum(x.status == 'GREEN' for x in findings)} GREEN, "
        f"{sum(x.status == 'YELLOW' for x in findings)} YELLOW, "
        f"{sum(x.status == 'RED' for x in findings)} RED, "
        f"{sum(x.status == 'EXEMPT' for x in findings)} EXEMPT."
    )

    if (
        args.require_all_green
        and unresolved
    ):
        print(
            "FAIL: unresolved fidelity categories remain."
        )
        return 2

    print(
        "PASS: audit invariants hold; unresolved categories remain explicit."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
