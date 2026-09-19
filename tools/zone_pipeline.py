#!/usr/bin/env python3
"""Local, config-driven acceptance checks for imported EQ Mobile zones.

This deliberately uses no network services, AI APIs, or project-specific
engine state.  It validates the files a new zone needs before its runtime code
is wired in, and verifies that an exported Godot PCK actually contains them.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import shutil
import struct
import sys
from pathlib import Path
from typing import Any

from peq_sql import (
    CLASSIC_EXPANSION,
    as_float,
    as_int,
    is_available_in_classic,
    rows_for_table,
    spawnentry_available_in_classic,
    table_columns,
)


ROOT = Path(__file__).resolve().parents[1]


class PipelineError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise PipelineError(message)


def project_path(value: str, label: str) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(ROOT.resolve())
    except ValueError:
        fail(f"{label} must stay inside the project: {value}")
    return path


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        fail(f"missing {label}: {path.relative_to(ROOT)}")
    except json.JSONDecodeError as error:
        fail(f"invalid {label} JSON ({path.relative_to(ROOT)}:{error.lineno}): {error.msg}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object: {path.relative_to(ROOT)}")
    return value


def load_config(value: str) -> tuple[Path, dict[str, Any]]:
    path = project_path(value, "config")
    config = read_json(path, "zone pipeline config")
    if config.get("schema_version") != 1:
        fail("config.schema_version must be 1")
    if not isinstance(config.get("zone_id"), str) or not config["zone_id"]:
        fail("config.zone_id must be a non-empty string")
    runtime = config.get("runtime")
    if not isinstance(runtime, dict):
        fail("config.runtime must be an object")
    for key in ("zone_definition", "geometry"):
        if not isinstance(runtime.get(key), str) or not runtime[key]:
            fail(f"config.runtime.{key} must be a non-empty project-relative path")

    placement = runtime.get("placement_manifest", "")
    props = runtime.get("prop_directory", "")

    if placement is None:
        placement = ""
    if props is None:
        props = ""

    if not isinstance(placement, str) or not isinstance(props, str):
        fail("config.runtime placement_manifest and prop_directory must be strings when supplied")

    if bool(placement) != bool(props):
        fail("config.runtime placement_manifest and prop_directory must be supplied together")

    return path, config


def glb_document(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 20:
        fail(f"geometry GLB is truncated: {path.relative_to(ROOT)}")
    magic, version, _length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2:
        fail(f"geometry is not a glTF 2 binary: {path.relative_to(ROOT)}")
    chunk_length, chunk_type = struct.unpack_from("<I4s", data, 12)
    if chunk_type != b"JSON":
        fail(f"geometry has no leading JSON chunk: {path.relative_to(ROOT)}")
    try:
        document = json.loads(data[20 : 20 + chunk_length])
    except json.JSONDecodeError as error:
        fail(f"geometry GLB has invalid JSON ({path.relative_to(ROOT)}): {error.msg}")
    if not isinstance(document, dict):
        fail(f"geometry GLB document must be an object: {path.relative_to(ROOT)}")
    return document


def glb_root_scale(path: Path) -> float:
    document = glb_document(path)
    scenes = document.get("scenes", [])
    nodes = document.get("nodes", [])
    if not scenes or not scenes[0].get("nodes"):
        fail(f"geometry has no scene root: {path.relative_to(ROOT)}")
    root = nodes[scenes[0]["nodes"][0]]
    if "matrix" in root:
        matrix = root["matrix"]
        if len(matrix) != 16:
            fail(f"geometry root matrix has invalid length: {path.relative_to(ROOT)}")
        return abs(float(matrix[0]))
    scale = root.get("scale", [1.0, 1.0, 1.0])
    return abs(float(scale[0]))


def external_glb_files(path: Path) -> list[Path]:
    """Return local image sidecars referenced by a GLB, rejecting path escapes."""
    files: list[Path] = []
    for image in glb_document(path).get("images", []):
        if not isinstance(image, dict) or not isinstance(image.get("uri"), str):
            continue
        uri = image["uri"]
        if uri.startswith("data:") or "://" in uri:
            continue
        candidate = (path.parent / uri).resolve()
        try:
            candidate.relative_to(path.parent.resolve())
        except ValueError:
            fail(f"GLB image URI escapes its source directory: {path.relative_to(ROOT)} -> {uri}")
        if not candidate.is_file():
            fail(f"GLB references missing image: {candidate}")
        files.append(candidate)
    return files


def placement_rows(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    try:
        with path.open(newline="") as handle:
            for line_number, row in enumerate(csv.reader(handle), start=1):
                if not row or not row[0] or row[0].startswith("#"):
                    continue
                if len(row) != 11:
                    fail(f"placement manifest line {line_number}: expected 11 columns, got {len(row)}")
                try:
                    for value in row[1:]:
                        parsed = float(value)
                        if not math.isfinite(parsed):
                            raise ValueError
                except ValueError:
                    fail(f"placement manifest line {line_number}: non-finite numeric field")
                rows.append(row)
    except FileNotFoundError:
        fail(f"missing placement manifest: {path.relative_to(ROOT)}")
    return rows


def imported_scene_path(glb_path: Path) -> str:
    """Return the Godot scene produced for a GLB, without assuming its hash."""
    import_path = Path(str(glb_path) + ".import")
    if not import_path.is_file():
        fail(f"GLB has not been imported by Godot yet: {glb_path.relative_to(ROOT)}")
    match = re.search(r'^path="res://(.+\.scn)"$', import_path.read_text(), re.MULTILINE)
    if match is None:
        fail(f"GLB import metadata has no PackedScene destination: {import_path.relative_to(ROOT)}")
    return match.group(1)


def validate(config_path: Path, config: dict[str, Any]) -> dict[str, Any]:
    runtime: dict[str, str] = config["runtime"]
    zone_path = project_path(runtime["zone_definition"], "runtime.zone_definition")
    geometry_path = project_path(runtime["geometry"], "runtime.geometry")
    zone = read_json(zone_path, "zone definition")

    if not geometry_path.exists():
        fail(f"missing geometry: {geometry_path.relative_to(ROOT)}")

    if zone.get("geometry_scene") != "res://" + runtime["geometry"]:
        fail("zone definition geometry_scene does not match runtime.geometry")

    compensation = zone.get("geometry_scale")
    if not isinstance(compensation, (int, float)) or isinstance(compensation, bool):
        fail("zone definition geometry_scale must be numeric")

    root_scale = glb_root_scale(geometry_path)
    if not math.isclose(
        root_scale * float(compensation),
        1.0,
        abs_tol=0.000001,
    ):
        fail(
            f"geometry root scale {root_scale:g} × compensation "
            f"{compensation:g} does not equal 1"
        )

    placement_value = runtime.get("placement_manifest", "")
    props_value = runtime.get("prop_directory", "")
    has_static_props = bool(placement_value)

    rows: list[list[str]] = []
    models: list[str] = []
    props_path: Path | None = None

    if has_static_props:
        manifest_path = project_path(
            placement_value,
            "runtime.placement_manifest",
        )
        props_path = project_path(
            props_value,
            "runtime.prop_directory",
        )

        if not props_path.exists():
            fail(
                f"missing prop directory: "
                f"{props_path.relative_to(ROOT)}"
            )

        if zone.get("object_instances") != "res://" + placement_value:
            fail(
                "zone definition object_instances does not match "
                "runtime.placement_manifest"
            )

        if zone.get("object_model_directory") != "res://" + props_value:
            fail(
                "zone definition object_model_directory does not match "
                "runtime.prop_directory"
            )

        rows = placement_rows(manifest_path)
        models = sorted({row[0] for row in rows})

        missing = [
            name
            for name in models
            if not (props_path / f"{name}.glb").is_file()
        ]

        if missing:
            fail(
                "placement models absent from runtime prop directory: "
                + ", ".join(missing)
            )
    else:
        if zone.get("object_instances", "") not in ("", None):
            fail(
                "zone definition declares object_instances but "
                "pipeline has no static-prop configuration"
            )
        if zone.get("object_model_directory", "") not in ("", None):
            fail(
                "zone definition declares object_model_directory but "
                "pipeline has no static-prop configuration"
            )

    sources = config.get("sources", {})
    if sources:
        if not isinstance(sources, dict):
            fail("config.sources must be an object when supplied")

        for runtime_key, source_key in (
            ("geometry", "geometry"),
            ("placement_manifest", "placement_manifest"),
        ):
            source_value = sources.get(source_key)

            if source_value is None:
                continue

            runtime_value = runtime.get(runtime_key, "")
            if not runtime_value:
                fail(
                    f"sources.{source_key} is configured without "
                    f"runtime.{runtime_key}"
                )

            source_path = project_path(
                source_value,
                f"sources.{source_key}",
            )
            runtime_path = project_path(
                runtime_value,
                f"runtime.{runtime_key}",
            )

            if not source_path.is_file():
                fail(
                    f"missing source {source_key}: "
                    f"{source_path.relative_to(ROOT)}"
                )

            if source_path.read_bytes() != runtime_path.read_bytes():
                fail(f"runtime {runtime_key} differs from configured source")

    package_paths = [runtime["zone_definition"]]

    geometry_relative = str(geometry_path.relative_to(ROOT))
    package_paths.extend(
        [
            geometry_relative + ".import",
            imported_scene_path(geometry_path),
        ]
    )

    if has_static_props:
        package_paths.append(placement_value)

        assert props_path is not None

        for model in models:
            glb_path = props_path / f"{model}.glb"
            relative_glb = str(glb_path.relative_to(ROOT))
            package_paths.extend(
                [
                    relative_glb + ".import",
                    imported_scene_path(glb_path),
                ]
            )

    result = {
        "zone_id": config["zone_id"],
        "placements": len(rows),
        "models": len(models),
        "root_scale": root_scale,
        "geometry_scale": float(compensation),
        "package_paths": package_paths,
    }

    print(
        "PASS: %(zone_id)s — %(placements)d placements, "
        "%(models)d prop models, root scale %(root_scale)g × "
        "%(geometry_scale)g = 1."
        % result
    )
    return result


def copy_asset_and_sidecars(source: Path, destination: Path, copied: set[Path]) -> None:
    """Copy a GLB and only the local image files it declares."""
    for item in [source] + external_glb_files(source):
        target = destination if item == source else destination.parent / item.relative_to(source.parent)
        if target in copied:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)
        copied.add(target)


def stage_assets(config: dict[str, Any], overwrite: bool) -> None:
    """Stage one extracted zone into its declared runtime paths."""
    staging = config.get("staging")
    if not isinstance(staging, dict):
        fail("stage-assets requires a config.staging object")

    geometry_source_value = staging.get("geometry_source")
    if (
        not isinstance(geometry_source_value, str)
        or not geometry_source_value
    ):
        fail(
            "config.staging.geometry_source must be a non-empty "
            "project-relative path"
        )

    runtime: dict[str, str] = config["runtime"]
    geometry_source = project_path(
        geometry_source_value,
        "staging.geometry_source",
    )
    geometry_destination = project_path(
        runtime["geometry"],
        "runtime.geometry",
    )

    if (
        not geometry_source.is_file()
        or geometry_source.suffix.lower() != ".glb"
    ):
        fail("staging.geometry_source must be a .glb file")

    placement_value = runtime.get("placement_manifest", "")
    props_value = runtime.get("prop_directory", "")
    has_static_props = bool(placement_value)

    rows: list[list[str]] = []
    source_models: list[Path] = []
    manifest_destination: Path | None = None
    destination_props: Path | None = None
    placement_source: Path | None = None

    if has_static_props:
        placement_source_value = staging.get("placement_source")
        source_props_value = staging.get("prop_source_directory")

        if (
            not isinstance(placement_source_value, str)
            or not placement_source_value
            or not isinstance(source_props_value, str)
            or not source_props_value
        ):
            fail(
                "static-prop staging requires placement_source and "
                "prop_source_directory"
            )

        placement_source = project_path(
            placement_source_value,
            "staging.placement_source",
        )
        source_props = project_path(
            source_props_value,
            "staging.prop_source_directory",
        )
        manifest_destination = project_path(
            placement_value,
            "runtime.placement_manifest",
        )
        destination_props = project_path(
            props_value,
            "runtime.prop_directory",
        )

        if (
            not placement_source.is_file()
            or not source_props.is_dir()
        ):
            fail(
                "staging placement source must be a file and "
                "prop source must be a directory"
            )

        rows = placement_rows(placement_source)
        model_names = sorted({row[0] for row in rows})
        source_models = [
            source_props / f"{model}.glb"
            for model in model_names
        ]

        missing = [
            path.name
            for path in source_models
            if not path.is_file()
        ]

        if missing:
            fail(
                "placement models missing from source prop directory: "
                + ", ".join(missing)
            )

    outputs = [geometry_destination]

    if has_static_props:
        assert manifest_destination is not None
        assert destination_props is not None
        outputs.append(manifest_destination)
        outputs.extend(
            destination_props / path.name
            for path in source_models
        )

    existing = [
        path
        for path in outputs
        if path.exists()
    ]

    if existing and not overwrite:
        fail(
            "refusing to overwrite runtime files; rerun with --overwrite: "
            + ", ".join(
                str(path.relative_to(ROOT))
                for path in existing[:5]
            )
        )

    copied: set[Path] = set()
    copy_asset_and_sidecars(
        geometry_source,
        geometry_destination,
        copied,
    )

    if has_static_props:
        assert placement_source is not None
        assert manifest_destination is not None
        assert destination_props is not None

        manifest_destination.parent.mkdir(
            parents=True,
            exist_ok=True,
        )
        shutil.copy2(
            placement_source,
            manifest_destination,
        )

        for source_model in source_models:
            copy_asset_and_sidecars(
                source_model,
                destination_props / source_model.name,
                copied,
            )

    print(
        f"STAGED: {config['zone_id']} — geometry, "
        f"{len(rows)} placements, {len(source_models)} prop GLBs."
    )


def import_npcs(config: dict[str, Any], archive_value: str, overwrite: bool) -> None:
    """Import classic NPC spawns, types, and patrols from a ProjectEQ SQL ZIP."""
    peq = config.get("peq")
    if not isinstance(peq, dict):
        fail("import-npcs requires a config.peq object")
    short_name = peq.get("zone_short_name")
    output_value = peq.get("npc_output")
    if not isinstance(short_name, str) or not short_name:
        fail("config.peq.zone_short_name must be a non-empty string")
    if not isinstance(output_value, str) or not output_value:
        fail("config.peq.npc_output must be a non-empty project-relative path")
    archive = Path(archive_value)
    if not archive.is_file():
        fail(f"ProjectEQ archive not found: {archive}")
    destination = project_path(output_value, "peq.npc_output")
    if destination.exists() and not overwrite:
        fail(f"refusing to overwrite NPC source; rerun with --overwrite: {destination.relative_to(ROOT)}")
    zone_id: int | None = None
    zone_table_id: int | None = None
    for row in rows_for_table(archive, "zone"):
        if row[3] == short_name and as_int(row[2]) == 0:
            zone_table_id, zone_id = as_int(row[0]), as_int(row[1])
            break
    if zone_id is None:
        fail(f"{short_name!r} base zone was not found in the ProjectEQ zone table")
    spawns: list[dict[str, Any]] = []
    excluded = 0
    for row in rows_for_table(archive, "spawn2"):
        if row[2] != short_name or as_int(row[3]) != 0:
            continue
        if not is_available_in_classic(row):
            excluded += 1
            continue
        spawns.append({"spawn2_id": as_int(row[0]), "spawn_group_id": as_int(row[1]), "position_eq": [as_float(row[4]), as_float(row[5]), as_float(row[6])], "heading_eq": as_float(row[7]), "respawn_seconds": as_int(row[8]), "grid_id": as_int(row[10]), "min_expansion": as_int(row[15]), "max_expansion": as_int(row[16])})
    group_ids = {spawn["spawn_group_id"] for spawn in spawns}
    candidates: dict[int, list[dict[str, int]]] = {group: [] for group in group_ids}
    npc_ids: set[int] = set()
    spawnentry_columns = table_columns(
        archive,
        "spawnentry",
    )
    for row in rows_for_table(archive, "spawnentry"):
        group_id = as_int(row[0])
        if group_id not in candidates:
            continue
        if not spawnentry_available_in_classic(
            row,
            spawnentry_columns,
        ):
            continue
        npc_id = as_int(row[1])
        npc_ids.add(npc_id)
        candidates[group_id].append({
            "npc_type_id": npc_id,
            "chance": as_int(row[2]),
        })
    npc_types: dict[int, dict[str, Any]] = {}
    for row in rows_for_table(archive, "npc_types"):
        npc_id = as_int(row[0])
        if npc_id not in npc_ids:
            continue
        npc_types[npc_id] = {"id": npc_id, "name": row[1], "lastname": None if row[2] == "NULL" else row[2], "level": as_int(row[3]), "race": as_int(row[4]), "class": as_int(row[5]), "gender": as_int(row[9]), "texture": as_int(row[10]), "face": as_int(row[33]), "size": as_float(row[13]), "hp": as_int(row[7]), "mana": as_int(row[8]), "hp_regen_rate": as_int(row[14]), "hp_regen_per_second": as_int(row[15]), "loottable_id": as_int(row[17]), "merchant_id": as_int(row[18]), "npc_spells_id": as_int(row[21]), "npc_faction_id": as_int(row[23]), "mindmg": as_int(row[26]), "maxdmg": as_int(row[27]), "aggroradius": as_int(row[31]), "assistradius": as_int(row[32]), "armor_class": as_int(row[64]), "npc_aggro": as_int(row[65]), "attack_speed": as_float(row[67]), "attack_delay": as_int(row[68]), "run_speed": as_float(row[53]), "walk_speed": as_float(row[104])}
    valid_spawns: list[dict[str, Any]] = []
    incomplete = 0
    for spawn in spawns:
        group_id = int(spawn["spawn_group_id"])
        candidates[group_id] = [candidate for candidate in candidates[group_id] if candidate["npc_type_id"] in npc_types]
        if candidates[group_id]:
            spawn["candidates"] = candidates[group_id]
            del spawn["spawn_group_id"]
            valid_spawns.append(spawn)
        else:
            incomplete += 1
    grid_ids = {int(spawn["grid_id"]) for spawn in valid_spawns if int(spawn["grid_id"]) != 0}
    grids: dict[int, list[dict[str, Any]]] = {}
    for row in rows_for_table(archive, "grid_entries"):
        grid_id = as_int(row[0])
        if as_int(row[1]) == zone_id and grid_id in grid_ids:
            grids.setdefault(grid_id, []).append({"number": as_int(row[2]), "position_eq": [as_float(row[3]), as_float(row[4]), as_float(row[5])], "heading_eq": as_float(row[6]), "pause_seconds": as_int(row[7])})
    for points in grids.values():
        points.sort(key=lambda point: int(point["number"]))
    unavailable_grids = 0
    for spawn in valid_spawns:
        grid_id = int(spawn["grid_id"])
        if grid_id and grid_id not in grids:
            spawn["unavailable_grid_id"] = grid_id
            spawn["grid_id"] = 0
            unavailable_grids += 1
    result = {"source": {"archive": archive.name, "zone": short_name, "zone_id": zone_id, "zone_table_id": zone_table_id, "schema": "ProjectEQ content SQL", "target_era": "classic_p1999", "expansion_id": CLASSIC_EXPANSION, "spawn_filter": "zone version 0; expansion range includes classic; no content flags or disabled-content flags", "p1999_overlay": "pending reviewed P1999-specific corrections"}, "spawns": valid_spawns, "npc_types": list(npc_types.values()), "grids": grids}
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"IMPORTED: {short_name} — {len(valid_spawns)} classic spawns, {len(npc_types)} NPC types, {len(grids)} grids ({excluded} excluded, {incomplete} incomplete, {unavailable_grids} unavailable grids).")


def package_check(config: dict[str, Any], pck: str | None) -> None:
    if pck is None:
        print("No PCK supplied. Create one without an APK, then rerun:")
        print(f"  godot --headless --path . --export-pack eqmobile /tmp/{config['zone_id']}-package-check.pck")
        print(f"  python3 tools/zone_pipeline.py package-check --config <config> --pck /tmp/{config['zone_id']}-package-check.pck")
        return
    path = Path(pck)
    if not path.is_file():
        fail(f"PCK not found: {path}")
    result = validate(Path(""), config)
    blob = path.read_bytes()
    missing = [entry for entry in result["package_paths"] if entry.encode() not in blob]
    if missing:
        fail("PCK is missing required runtime entries: " + ", ".join(missing))
    print(f"PASS: {config['zone_id']} package check — {len(result['package_paths'])} required runtime entries found in {path}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate and package-check a config-driven EQ Mobile zone.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("validate", "package-check", "stage-assets", "import-npcs"):
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("--config", required=True, help="Project-relative zone pipeline JSON config")
        if command == "package-check":
            command_parser.add_argument("--pck", help="Godot PCK to inspect; omit to print the export command")
        if command == "stage-assets":
            command_parser.add_argument("--overwrite", action="store_true", help="Replace existing declared runtime files")
        if command == "import-npcs":
            command_parser.add_argument("--archive", required=True, help="ProjectEQ content SQL ZIP")
            command_parser.add_argument("--overwrite", action="store_true", help="Replace the configured NPC source JSON")
    args = parser.parse_args()
    try:
        config_path, config = load_config(args.config)
        if args.command == "validate":
            validate(config_path, config)
        elif args.command == "package-check":
            package_check(config, args.pck)
        elif args.command == "import-npcs":
            import_npcs(config, args.archive, args.overwrite)
        else:
            stage_assets(config, args.overwrite)
    except PipelineError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
