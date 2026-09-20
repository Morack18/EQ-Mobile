#!/usr/bin/env python3
"""Apply and validate the P1999 correction overlay for Halas NPCs.

This tool deterministically merges a raw ProjectEQ source snapshot (e.g.
data/halas_npcs_source.json) with a reviewed P1999 correction overlay (e.g.
data/halas_npcs_overlay.json) to produce the runtime NPC snapshot (e.g.
data/halas_npcs.json).

Inputs are strictly read-only. The tool validates all overlay IDs, fields,
values, and cross-references against the source before applying them. It also
validates the derived dataset's integrity before writing, ensuring idempotency,
provenance preservation, and error rejection.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "data/halas_npcs_source.json"
DEFAULT_OVERLAY = ROOT / "data/halas_npcs_overlay.json"
DEFAULT_OUTPUT = ROOT / "data/halas_npcs.json"

NPC_TYPE_FIELDS = {
    "id": int,
    "name": str,
    "lastname": (str, type(None)),
    "level": int,
    "race": int,
    "class": int,
    "gender": int,
    "texture": int,
    "face": int,
    "size": (int, float),
    "hp": int,
    "mana": int,
    "hp_regen_rate": int,
    "hp_regen_per_second": int,
    "loottable_id": int,
    "merchant_id": int,
    "npc_spells_id": int,
    "npc_faction_id": int,
    "mindmg": int,
    "maxdmg": int,
    "aggroradius": int,
    "assistradius": int,
    "armor_class": int,
    "npc_aggro": int,
    "attack_speed": (int, float),
    "attack_delay": int,
    "run_speed": (int, float),
    "walk_speed": (int, float),
}

SPAWN_FIELDS = {
    "spawn2_id": int,
    "spawn_group_id": int,
    "position_eq": list,
    "heading_eq": (int, float),
    "respawn_seconds": int,
    "grid_id": int,
    "min_expansion": int,
    "max_expansion": int,
    "candidates": list,
}

OPTIONAL_SPAWN_FIELDS = {
    "unavailable_grid_id": int,
}

OVERLAY_TOP_LEVEL_FIELDS = {
    "schema_version",
    "zone",
    "target_era",
    "description",
    "review",
    "review_notes",
    "npc_types",
    "spawns",
    "grids",
}


class ValidationError(ValueError):
    pass


def fail(message: str) -> None:
    raise ValidationError(message)


def finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{label} must be a number, got {type(value).__name__}: {value!r}")
    if not math.isfinite(value):
        fail(f"{label} must be finite: {value!r}")
    return float(value)


def validate_position(pos: Any, label: str) -> list[float]:
    if not isinstance(pos, list) or len(pos) != 3:
        fail(f"{label} must be a 3-element coordinate list [x, y, elevation]")
    for axis, val in zip(("x", "y", "elevation"), pos):
        finite_number(val, f"{label}.{axis}")
    return [float(c) for c in pos]


def validate_heading(val: Any, label: str) -> float:
    num = finite_number(val, label)
    if num != -1.0 and not 0.0 <= num <= 512.0:
        fail(f"{label} must be -1.0 or within [0.0, 512.0], got {num}")
    return num


def validate_integer(val: Any, label: str, min_val: int | None = None, max_val: int | None = None) -> int:
    if isinstance(val, bool) or not isinstance(val, int):
        fail(f"{label} must be an integer, got {type(val).__name__}: {val!r}")
    if min_val is not None and val < min_val:
        fail(f"{label} must be >= {min_val}, got {val}")
    if max_val is not None and val > max_val:
        fail(f"{label} must be <= {max_val}, got {val}")
    return val


def validate_npc_type_fields(npc: dict[str, Any], label: str, require_all: bool = True) -> None:
    if not isinstance(npc, dict):
        fail(f"{label} must be an object")
    if require_all:
        missing = set(NPC_TYPE_FIELDS) - set(npc)
        if missing:
            fail(f"{label} is missing required fields: {sorted(missing)}")
    unknown = set(npc) - set(NPC_TYPE_FIELDS)
    if unknown:
        fail(f"{label} contains unknown fields: {sorted(unknown)}")
    for field, val in npc.items():
        field_label = f"{label}.{field}"
        expected_type = NPC_TYPE_FIELDS[field]
        if field == "id":
            validate_integer(val, field_label, min_val=1)
        elif field == "name":
            if not isinstance(val, str) or not val.strip():
                fail(f"{field_label} must be a non-empty string")
        elif field == "lastname":
            if val is not None and not isinstance(val, str):
                fail(f"{field_label} must be string or null")
        elif field == "level":
            validate_integer(val, field_label, min_val=1, max_val=100)
        elif field in ("race", "class", "gender", "texture", "face"):
            validate_integer(val, field_label, min_val=0)
        elif field == "size":
            num = finite_number(val, field_label)
            if num < 0.0:
                fail(f"{field_label} must be >= 0.0, got {num}")
        elif field == "hp":
            validate_integer(val, field_label, min_val=1)
        elif field in ("mindmg", "maxdmg"):
            validate_integer(val, field_label, min_val=0)
        elif field in ("attack_delay", "respawn_seconds"):
            validate_integer(val, field_label, min_val=0)
        elif field in ("run_speed", "walk_speed"):
            num = finite_number(val, field_label)
            if num < 0.0:
                fail(f"{field_label} must be >= 0.0, got {num}")
        elif field == "attack_speed":
            finite_number(val, field_label)
        elif isinstance(expected_type, tuple):
            if not isinstance(val, expected_type):
                fail(f"{field_label} must be one of {expected_type}, got {type(val).__name__}")
        else:
            if not isinstance(val, expected_type) or isinstance(val, bool):
                fail(f"{field_label} must be {expected_type.__name__}, got {type(val).__name__}")
    if "mindmg" in npc and "maxdmg" in npc:
        if npc["mindmg"] > npc["maxdmg"]:
            fail(f"{label}: mindmg ({npc['mindmg']}) cannot exceed maxdmg ({npc['maxdmg']})")


def validate_spawn_fields(spawn: dict[str, Any], label: str, require_all: bool = True) -> None:
    if not isinstance(spawn, dict):
        fail(f"{label} must be an object")
    if require_all:
        missing = set(SPAWN_FIELDS) - set(spawn)
        if missing:
            fail(f"{label} is missing required fields: {sorted(missing)}")
    allowed = set(SPAWN_FIELDS) | set(OPTIONAL_SPAWN_FIELDS)
    unknown = set(spawn) - allowed
    if unknown:
        fail(f"{label} contains unknown fields: {sorted(unknown)}")
    if "spawn2_id" in spawn:
        validate_integer(spawn["spawn2_id"], f"{label}.spawn2_id", min_val=1)
    if "position_eq" in spawn:
        validate_position(spawn["position_eq"], f"{label}.position_eq")
    if "heading_eq" in spawn:
        validate_heading(spawn["heading_eq"], f"{label}.heading_eq")
    if "respawn_seconds" in spawn:
        validate_integer(spawn["respawn_seconds"], f"{label}.respawn_seconds", min_val=0)
    if "grid_id" in spawn:
        validate_integer(spawn["grid_id"], f"{label}.grid_id", min_val=0)
    if "min_expansion" in spawn:
        validate_integer(spawn["min_expansion"], f"{label}.min_expansion")
    if "max_expansion" in spawn:
        validate_integer(spawn["max_expansion"], f"{label}.max_expansion")
    if "unavailable_grid_id" in spawn:
        validate_integer(spawn["unavailable_grid_id"], f"{label}.unavailable_grid_id", min_val=0)
    if "candidates" in spawn:
        candidates = spawn["candidates"]
        if not isinstance(candidates, list) or not candidates:
            fail(f"{label}.candidates must be a non-empty list")
        for idx, cand in enumerate(candidates):
            cand_label = f"{label}.candidates[{idx}]"
            if not isinstance(cand, dict) or set(cand) != {"npc_type_id", "chance"}:
                fail(f"{cand_label} must have exactly 'npc_type_id' and 'chance'")
            validate_integer(cand["npc_type_id"], f"{cand_label}.npc_type_id", min_val=1)
            validate_integer(cand["chance"], f"{cand_label}.chance", min_val=0)


def validate_grid_points(points: list[dict[str, Any]], grid_id: int, label: str) -> None:
    if not isinstance(points, list) or not points:
        fail(f"{label} (grid {grid_id}) must be a non-empty list of waypoints")
    seen_numbers: set[int] = set()
    prev_number = 0
    for idx, pt in enumerate(points):
        pt_label = f"{label}[{idx}]"
        if not isinstance(pt, dict) or set(pt) != {"number", "position_eq", "heading_eq", "pause_seconds"}:
            fail(f"{pt_label} must have exactly 'number', 'position_eq', 'heading_eq', 'pause_seconds'")
        num = validate_integer(pt["number"], f"{pt_label}.number", min_val=1)
        if num in seen_numbers:
            fail(f"{label} has duplicate waypoint number: {num}")
        if num <= prev_number:
            fail(f"{label} waypoint numbers must be strictly ascending: {prev_number} -> {num}")
        seen_numbers.add(num)
        prev_number = num
        validate_position(pt["position_eq"], f"{pt_label}.position_eq")
        validate_heading(pt["heading_eq"], f"{pt_label}.heading_eq")
        validate_integer(pt["pause_seconds"], f"{pt_label}.pause_seconds", min_val=0)


def validate_overlay(overlay: dict[str, Any], source_data: dict[str, Any]) -> None:
    if not isinstance(overlay, dict):
        fail("overlay root must be an object")
    unknown_top = set(overlay) - OVERLAY_TOP_LEVEL_FIELDS
    if unknown_top:
        fail(f"overlay contains unknown top-level keys: {sorted(unknown_top)}")
    if overlay.get("schema_version") != 1:
        fail(f"overlay schema_version must be 1, got {overlay.get('schema_version')!r}")
    if overlay.get("zone") != "halas":
        fail(f"overlay zone must be 'halas', got {overlay.get('zone')!r}")
    if overlay.get("target_era") != "classic_p1999":
        fail(f"overlay target_era must be 'classic_p1999', got {overlay.get('target_era')!r}")
    review = overlay.get("review", {})
    allowed_groups = {"roster", "identity", "appearance", "patrol", "combat_reference", "movement_reference", "faction_reference", "economy_reference"}
    if not isinstance(review, dict) or set(review) - allowed_groups:
        fail("overlay.review must contain only known authority groups")
    if review.get("combat_reference") == "confirmed_p1999":
        fail("overlay.review cannot claim confirmed_p1999 combat_reference without stat corrections")
    if not isinstance(overlay.get("review_notes", []), list):
        fail("overlay.review_notes must be a list")

    source_npc_ids = {npc["id"] for npc in source_data.get("npc_types", [])}
    source_spawn_ids = {spawn["spawn2_id"] for spawn in source_data.get("spawns", [])}
    source_grid_ids = {int(gid) for gid in source_data.get("grids", {})}

    # Validate npc_types section
    npc_section = overlay.get("npc_types", {})
    if not isinstance(npc_section, dict):
        fail("overlay.npc_types must be an object")
    unknown_npc_sec = set(npc_section) - {"overrides", "additions", "deletions"}
    if unknown_npc_sec:
        fail(f"overlay.npc_types contains unknown keys: {sorted(unknown_npc_sec)}")

    npc_deletions = set()
    for item in npc_section.get("deletions", []):
        npc_id = validate_integer(item, "npc_types deletion ID", min_val=1)
        if npc_id not in source_npc_ids:
            fail(f"npc_types deletion references non-existent NPC ID: {npc_id}")
        if npc_id in npc_deletions:
            fail(f"duplicate npc_types deletion ID: {npc_id}")
        npc_deletions.add(npc_id)

    npc_overrides = npc_section.get("overrides", {})
    if not isinstance(npc_overrides, dict):
        fail("overlay.npc_types.overrides must be an object")
    for id_key, fields in npc_overrides.items():
        try:
            npc_id = int(id_key)
        except (TypeError, ValueError):
            fail(f"npc_types override ID is not an integer: {id_key!r}")
        if npc_id not in source_npc_ids:
            fail(f"npc_types override references non-existent NPC ID: {npc_id}")
        if npc_id in npc_deletions:
            fail(f"npc_types ID {npc_id} cannot be in both overrides and deletions")
        if "id" in fields and fields["id"] != npc_id:
            fail(f"npc_types override cannot change ID {npc_id} to {fields['id']}")
        validate_npc_type_fields(fields, f"npc_types override {npc_id}", require_all=False)

    npc_additions = npc_section.get("additions", [])
    if not isinstance(npc_additions, list):
        fail("overlay.npc_types.additions must be a list")
    if npc_additions:
        fail("NPC additions require an explicit project-owned identity contract and are not supported yet")
    seen_add_npc_ids: set[int] = set()
    for idx, npc in enumerate(npc_additions):
        label = f"npc_types addition[{idx}]"
        validate_npc_type_fields(npc, label, require_all=True)
        npc_id = npc["id"]
        if npc_id in source_npc_ids and npc_id not in npc_deletions:
            fail(f"{label} ID {npc_id} collides with existing source NPC (and was not deleted)")
        if npc_id in seen_add_npc_ids:
            fail(f"{label} duplicate addition NPC ID {npc_id}")
        seen_add_npc_ids.add(npc_id)

    final_npc_ids = (source_npc_ids - npc_deletions) | seen_add_npc_ids

    # Validate grids section
    grid_section = overlay.get("grids", {})
    if not isinstance(grid_section, dict):
        fail("overlay.grids must be an object")
    unknown_grid_sec = set(grid_section) - {"replacements", "deletions"}
    if unknown_grid_sec:
        fail(f"overlay.grids contains unknown keys: {sorted(unknown_grid_sec)}")

    grid_deletions = set()
    for item in grid_section.get("deletions", []):
        grid_id = validate_integer(item, "grids deletion ID", min_val=1)
        if grid_id not in source_grid_ids:
            fail(f"grids deletion references non-existent grid ID: {grid_id}")
        if grid_id in grid_deletions:
            fail(f"duplicate grids deletion ID: {grid_id}")
        grid_deletions.add(grid_id)

    grid_replacements = grid_section.get("replacements", {})
    if not isinstance(grid_replacements, dict):
        fail("overlay.grids.replacements must be an object")
    replaced_grid_ids: set[int] = set()
    for id_key, waypoints in grid_replacements.items():
        try:
            grid_id = int(id_key)
        except (TypeError, ValueError):
            fail(f"grids replacement ID is not an integer: {id_key!r}")
        if grid_id in grid_deletions:
            fail(f"grid ID {grid_id} cannot be in both replacements and deletions")
        validate_grid_points(waypoints, grid_id, f"grids replacement {grid_id}")
        replaced_grid_ids.add(grid_id)

    final_grid_ids = (source_grid_ids - grid_deletions) | replaced_grid_ids

    # Validate spawns section
    spawn_section = overlay.get("spawns", {})
    if not isinstance(spawn_section, dict):
        fail("overlay.spawns must be an object")
    unknown_spawn_sec = set(spawn_section) - {"overrides", "additions", "deletions"}
    if unknown_spawn_sec:
        fail(f"overlay.spawns contains unknown keys: {sorted(unknown_spawn_sec)}")

    spawn_deletions = set()
    for item in spawn_section.get("deletions", []):
        spawn_id = validate_integer(item, "spawns deletion ID", min_val=1)
        if spawn_id not in source_spawn_ids:
            fail(f"spawns deletion references non-existent spawn2 ID: {spawn_id}")
        if spawn_id in spawn_deletions:
            fail(f"duplicate spawns deletion ID: {spawn_id}")
        spawn_deletions.add(spawn_id)

    spawn_overrides = spawn_section.get("overrides", {})
    if not isinstance(spawn_overrides, dict):
        fail("overlay.spawns.overrides must be an object")
    for id_key, fields in spawn_overrides.items():
        try:
            spawn_id = int(id_key)
        except (TypeError, ValueError):
            fail(f"spawns override ID is not an integer: {id_key!r}")
        if spawn_id not in source_spawn_ids:
            fail(f"spawns override references non-existent spawn2 ID: {spawn_id}")
        if spawn_id in spawn_deletions:
            fail(f"spawn2 ID {spawn_id} cannot be in both overrides and deletions")
        if "spawn2_id" in fields and fields["spawn2_id"] != spawn_id:
            fail(f"spawns override cannot change spawn2_id {spawn_id} to {fields['spawn2_id']}")
        if "candidates" in fields:
            fail("Spawn candidate overrides are not supported; SpawnGroup is the canonical candidate owner")
        validate_spawn_fields(fields, f"spawns override {spawn_id}", require_all=False)
        if "grid_id" in fields and fields["grid_id"] != 0 and fields["grid_id"] not in final_grid_ids:
            fail(f"spawns override {spawn_id} references missing grid ID: {fields['grid_id']}")
        if "candidates" in fields:
            for cand in fields["candidates"]:
                if cand["npc_type_id"] not in final_npc_ids:
                    fail(f"spawns override {spawn_id} references missing NPC type {cand['npc_type_id']}")

    spawn_additions = spawn_section.get("additions", [])
    if not isinstance(spawn_additions, list):
        fail("overlay.spawns.additions must be a list")
    if spawn_additions:
        fail("Spawn additions require an explicit project-owned identity contract and are not supported yet")
    seen_add_spawn_ids: set[int] = set()
    for idx, spawn in enumerate(spawn_additions):
        label = f"spawns addition[{idx}]"
        validate_spawn_fields(spawn, label, require_all=True)
        spawn_id = spawn["spawn2_id"]
        if spawn_id in source_spawn_ids and spawn_id not in spawn_deletions:
            fail(f"{label} ID {spawn_id} collides with existing source spawn2 (and was not deleted)")
        if spawn_id in seen_add_spawn_ids:
            fail(f"{label} duplicate addition spawn2 ID {spawn_id}")
        seen_add_spawn_ids.add(spawn_id)
        if spawn["grid_id"] != 0 and spawn["grid_id"] not in final_grid_ids:
            fail(f"{label} references missing grid ID: {spawn['grid_id']}")
        for cand in spawn["candidates"]:
            if cand["npc_type_id"] not in final_npc_ids:
                fail(f"{label} references missing NPC type {cand['npc_type_id']}")

    # Check for orphaned references in retained source spawns
    retained_source_spawns = [
        s for s in source_data.get("spawns", [])
        if s["spawn2_id"] not in spawn_deletions
    ]
    for spawn in retained_source_spawns:
        sid = spawn["spawn2_id"]
        # Determine candidates after potential override
        cands = spawn_overrides.get(str(sid), {}).get("candidates", spawn["candidates"])
        valid_cands = [c for c in cands if c["npc_type_id"] in final_npc_ids]
        if not valid_cands:
            fail(f"spawn {sid} has no remaining candidates after NPC deletions")
        gid = spawn_overrides.get(str(sid), {}).get("grid_id", spawn.get("grid_id", 0))
        if gid != 0 and gid not in final_grid_ids:
            fail(f"spawn {sid} references grid {gid} which was deleted")


def apply_overlay(
    source_data: dict[str, Any],
    overlay_data: dict[str, Any],
    source_path: str = "data/halas_npcs_source.json",
    overlay_path: str = "data/halas_npcs_overlay.json",
) -> dict[str, Any]:
    """Deterministically merge source data and overlay data to produce derived snapshot."""
    validate_overlay(overlay_data, source_data)

    # 1. NPC Types
    npc_types_map: dict[int, dict[str, Any]] = {
        int(npc["id"]): copy.deepcopy(npc) for npc in source_data.get("npc_types", [])
    }
    npc_section = overlay_data.get("npc_types", {})
    for npc_id in npc_section.get("deletions", []):
        npc_types_map.pop(int(npc_id), None)
    for npc in npc_section.get("additions", []):
        npc_types_map[int(npc["id"])] = copy.deepcopy(npc)
    for id_key, overrides in npc_section.get("overrides", {}).items():
        target = npc_types_map[int(id_key)]
        for k, v in overrides.items():
            target[k] = copy.deepcopy(v)

    # 2. Grids
    grids_map: dict[str, list[dict[str, Any]]] = {
        str(k): copy.deepcopy(v) for k, v in source_data.get("grids", {}).items()
    }
    grid_section = overlay_data.get("grids", {})
    for grid_id in grid_section.get("deletions", []):
        grids_map.pop(str(grid_id), None)
    for id_key, waypoints in grid_section.get("replacements", {}).items():
        grids_map[str(id_key)] = copy.deepcopy(waypoints)
        grids_map[str(id_key)].sort(key=lambda pt: int(pt["number"]))

    # 3. Spawns
    spawns_map: dict[int, dict[str, Any]] = {
        int(spawn["spawn2_id"]): copy.deepcopy(spawn) for spawn in source_data.get("spawns", [])
    }
    spawn_section = overlay_data.get("spawns", {})
    for spawn_id in spawn_section.get("deletions", []):
        spawns_map.pop(int(spawn_id), None)
    for spawn in spawn_section.get("additions", []):
        spawns_map[int(spawn["spawn2_id"])] = copy.deepcopy(spawn)
    for id_key, overrides in spawn_section.get("overrides", {}).items():
        target = spawns_map[int(id_key)]
        for k, v in overrides.items():
            target[k] = copy.deepcopy(v)

    # Filter any candidates referencing deleted NPC types in retained spawns
    # (validation already ensures at least one candidate remains)
    for spawn in spawns_map.values():
        spawn["candidates"] = [
            c for c in spawn["candidates"] if int(c["npc_type_id"]) in npc_types_map
        ]

    # Deterministic sorting
    sorted_npc_types = sorted(npc_types_map.values(), key=lambda n: int(n["id"]))
    sorted_spawns = sorted(spawns_map.values(), key=lambda s: int(s["spawn2_id"]))
    sorted_grids = {
        str(k): grids_map[str(k)] for k in sorted(grids_map.keys(), key=lambda x: int(x))
    }

    # Typed keys are a derived neutral-data contract. Raw PEQ snapshots keep
    # their source-shaped numeric fields so overlay application remains a
    # transparent correction step rather than an identity rewrite.
    for npc in sorted_npc_types:
        npc["key"] = f"peq:npc:{int(npc['id'])}"
        npc["class_ref"] = f"eqemu:class:{int(npc['class'])}"
        npc["race_ref"] = f"eqemu:race:{int(npc['race'])}"
        npc_spells_id = int(npc.get("npc_spells_id", 0))
        npc["npc_spell_list_ref"] = (
            f"peq:npc_spell_list:{npc_spells_id}" if npc_spells_id > 0 else None
        )
        npc_faction_id = int(npc.get("npc_faction_id", 0))
        merchant_id = int(npc.get("merchant_id", 0))
        loottable_id = int(npc.get("loottable_id", 0))
        npc["npc_faction_ref"] = f"peq:npc_faction:{npc_faction_id}" if npc_faction_id > 0 else None
        npc["merchant_ref"] = f"peq:merchant:{merchant_id}" if merchant_id > 0 else None
        npc["loot_table_ref"] = f"peq:loot_table:{loottable_id}" if loottable_id > 0 else None
    for spawn in sorted_spawns:
        spawn["key"] = f"peq:spawn:{int(spawn['spawn2_id'])}"
        spawn["spawn_group_ref"] = f"peq:spawn_group:{int(spawn['spawn_group_id'])}"
        for candidate in spawn["candidates"]:
            candidate["npc_ref"] = f"peq:npc:{int(candidate['npc_type_id'])}"
    derived_groups = copy.deepcopy(source_data.get("spawn_groups", {}))
    for group_id, group in derived_groups.items():
        group["key"] = f"peq:spawn_group:{int(group_id)}"
        for candidate in group.get("candidates", []):
            candidate["npc_ref"] = f"peq:npc:{int(candidate['npc_type_id'])}"

    # Derived provenance metadata
    raw_source_meta = source_data.get("source", {})
    derived_source = dict(raw_source_meta)
    derived_source["raw_source"] = source_path
    derived_source["p1999_overlay"] = overlay_path
    derived_source["p1999_overlay_applied"] = True
    derived_source["p1999_overlay_revision"] = int(overlay_data.get("schema_version", 1))
    derived_source["schema"] = "ProjectEQ content SQL with P1999 overlay"
    meta = copy.deepcopy(source_data.get("meta", {}))
    meta.update(
        {
            "overlay": {
                "dataset_id": "eqm:overlay:halas-npcs-p1999-v1",
                "schema_version": int(overlay_data.get("schema_version", 1)),
                "sha256": hashlib.sha256(
                    json.dumps(overlay_data, sort_keys=True).encode()
                ).hexdigest(),
                "review_state": "pending_reviewed_corrections",
            },
            "generator": {"tool": "tools/apply_halas_npc_overlay.py"},
        }
    )

    derived = {
        "schema_id": "eqm.halas.npcs.derived",
        "schema_version": 1,
        "dataset_id": "eqm:dataset:halas-npcs",
        "meta": meta,
        "grids": sorted_grids,
        "npc_types": sorted_npc_types,
        "source": derived_source,
        "review": copy.deepcopy(overlay_data.get("review", {})),
        "review_notes": copy.deepcopy(overlay_data.get("review_notes", [])),
        "spawns": sorted_spawns,
        "spawn_groups": derived_groups,
    }
    return derived


def serialize_derived(derived: dict[str, Any]) -> str:
    return json.dumps(derived, indent=2, sort_keys=True) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Apply and validate P1999 correction overlay for Halas NPCs."
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help=f"Raw ProjectEQ source JSON (default: {DEFAULT_SOURCE.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--overlay",
        type=Path,
        default=DEFAULT_OVERLAY,
        help=f"P1999 correction overlay JSON (default: {DEFAULT_OVERLAY.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Derived runtime NPC snapshot JSON (default: {DEFAULT_OUTPUT.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--verify-only",
        "--check",
        action="store_true",
        help="Verify inputs and check that existing output matches derived snapshot exactly without writing",
    )
    args = parser.parse_args()

    source_path = args.source.resolve()
    overlay_path = args.overlay.resolve()
    output_path = args.output.resolve()

    if not source_path.is_file():
        fail(f"Source file not found: {source_path}")
    if not overlay_path.is_file():
        fail(f"Overlay file not found: {overlay_path}")

    source_data = json.loads(source_path.read_text())
    overlay_data = json.loads(overlay_path.read_text())

    try:
        source_rel = str(source_path.relative_to(ROOT))
    except ValueError:
        source_rel = str(source_path)
    try:
        overlay_rel = str(overlay_path.relative_to(ROOT))
    except ValueError:
        overlay_rel = str(overlay_path)

    derived = apply_overlay(source_data, overlay_data, source_path=source_rel, overlay_path=overlay_rel)
    serialized = serialize_derived(derived)

    if args.verify_only:
        if not output_path.is_file():
            print(f"FAIL: output snapshot does not exist: {output_path}", file=sys.stderr)
            raise SystemExit(1)
        existing = output_path.read_text()
        if existing != serialized:
            print(f"FAIL: output snapshot {output_path} differs from derived overlay result", file=sys.stderr)
            raise SystemExit(1)
        print(
            f"PASS: verified {output_path.name} against {source_path.name} + {overlay_path.name} "
            f"({len(derived['spawns'])} spawns, {len(derived['npc_types'])} NPC types, {len(derived['grids'])} grids)."
        )
        return

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(serialized)
    print(
        f"APPLIED: {output_path.name} derived from {source_path.name} + {overlay_path.name} — "
        f"{len(derived['spawns'])} spawns, {len(derived['npc_types'])} NPC types, {len(derived['grids'])} grids."
    )


if __name__ == "__main__":
    try:
        main()
    except ValidationError as err:
        print(f"FAIL: {err}", file=sys.stderr)
        raise SystemExit(1)
