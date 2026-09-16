#!/usr/bin/env python3
"""Validate referential and numeric integrity of the Halas NPC source data."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/halas_npcs_source.json"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def finite_number(value: Any, label: str) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{label} must be a number")
    if not math.isfinite(value):
        fail(f"{label} must be finite")


def position(position: Any, label: str) -> None:
    if not isinstance(position, list) or len(position) != 3:
        fail(f"{label} must contain exactly three coordinates")
    for axis, value in zip(("x", "y", "elevation"), position):
        finite_number(value, f"{label}.{axis}")


def heading(value: Any, label: str) -> None:
    finite_number(value, label)
    # PEQ grid entries use -1 for an unspecified heading. All explicit EQ
    # headings use the 0–512 turn range.
    if value != -1.0 and not 0.0 <= value <= 512.0:
        fail(f"{label} must be -1 or in [0, 512]")


def main() -> None:
    content = json.loads(SOURCE.read_text())
    spawns = content["spawns"]
    npc_types = content["npc_types"]
    grids = content["grids"]

    npc_type_ids: set[int] = set()
    for npc_type in npc_types:
        npc_type_id = npc_type["id"]
        if npc_type_id in npc_type_ids:
            fail(f"duplicate npc type ID: {npc_type_id}")
        npc_type_ids.add(npc_type_id)

    spawn_ids: set[int] = set()
    referenced_grids: set[int] = set()
    candidate_count = 0
    for spawn in spawns:
        spawn_id = spawn["spawn2_id"]
        if spawn_id in spawn_ids:
            fail(f"duplicate spawn2 ID: {spawn_id}")
        spawn_ids.add(spawn_id)
        position(spawn["position_eq"], f"spawn {spawn_id} position_eq")
        heading(spawn["heading_eq"], f"spawn {spawn_id} heading_eq")
        grid_id = spawn["grid_id"]
        if grid_id != 0:
            referenced_grids.add(grid_id)
        for candidate in spawn["candidates"]:
            candidate_count += 1
            npc_type_id = candidate["npc_type_id"]
            if npc_type_id not in npc_type_ids:
                fail(f"spawn {spawn_id} references missing npc type {npc_type_id}")

    grid_ids: set[int] = set()
    point_count = 0
    for grid_id_text, points in grids.items():
        try:
            grid_id = int(grid_id_text)
        except (TypeError, ValueError):
            fail(f"invalid grid ID: {grid_id_text!r}")
        if grid_id in grid_ids:
            fail(f"duplicate grid ID: {grid_id}")
        grid_ids.add(grid_id)
        numbers: set[int] = set()
        previous_number: int | None = None
        for point in points:
            number = point["number"]
            if number in numbers:
                fail(f"duplicate point number {number} in grid {grid_id}")
            if previous_number is not None and number <= previous_number:
                fail(f"grid {grid_id} point numbers are not ascending")
            numbers.add(number)
            previous_number = number
            point_count += 1
            position(point["position_eq"], f"grid {grid_id} point {number} position_eq")
            heading(point["heading_eq"], f"grid {grid_id} point {number} heading_eq")

    missing_grids = referenced_grids - grid_ids
    if missing_grids:
        fail(f"spawns reference missing grids: {sorted(missing_grids)}")

    print(
        "PASS: Halas zone data — "
        f"{len(spawns)} spawns, {len(npc_types)} NPC types, "
        f"{len(grid_ids)} grids, {point_count} grid points, "
        f"{candidate_count} NPC candidates."
    )


if __name__ == "__main__":
    main()
