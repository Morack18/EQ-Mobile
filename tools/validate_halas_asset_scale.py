#!/usr/bin/env python3
"""Validate Halas runtime asset scale/provenance against local EQ references.

This is deliberately read-only. It verifies that the runtime zone, props, and
placement-scale data remain exact copies of Lantern's exports, and that the
zone's one exporter-introduced 0.1 root scale is exactly cancelled by the
declared runtime compensation. NPC body scale is checked at runtime from the
source npc_types.size value (or the documented EQEmu default fallback), as
the character GLBs are intentionally normalized per rig.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ZONE = ROOT / "resources/LanternExtractor/Exports/halas/Zone"
RUNTIME_ZONE = ROOT / "assets/imported/halas"
SOURCE_PROPS = SOURCE_ZONE.parent / "Objects"
RUNTIME_PROPS = RUNTIME_ZONE / "objects"


def glb_json(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, _length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2:
        raise ValueError(f"{path}: not a glTF 2 binary")
    chunk_length, chunk_type = struct.unpack_from("<I4s", data, 12)
    if chunk_type != b"JSON":
        raise ValueError(f"{path}: first chunk is not JSON")
    return json.loads(data[20 : 20 + chunk_length])


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    source_zone_glb = SOURCE_ZONE / "halas.glb"
    runtime_zone_glb = RUNTIME_ZONE / "halas.glb"
    if source_zone_glb.read_bytes() != runtime_zone_glb.read_bytes():
        fail("runtime Halas GLB differs from the Lantern reference export")

    source_manifest = SOURCE_ZONE / "object_instances.txt"
    runtime_manifest = ROOT / "data/halas_objects.json"
    if source_manifest.read_bytes() != runtime_manifest.read_bytes():
        fail("runtime object manifest differs from Lantern's placement source")

    runtime_props = sorted(RUNTIME_PROPS.glob("*.glb"))
    if not runtime_props:
        fail("no runtime Halas prop GLBs found")
    for runtime_prop in runtime_props:
        source_prop = SOURCE_PROPS / runtime_prop.name
        if not source_prop.is_file():
            fail(f"missing Lantern source prop: {runtime_prop.name}")
        if runtime_prop.read_bytes() != source_prop.read_bytes():
            fail(f"runtime prop differs from Lantern source: {runtime_prop.name}")

    zone = json.loads((ROOT / "data/halas.json").read_text())
    root_matrix = glb_json(runtime_zone_glb)["nodes"][0]["matrix"]
    root_scale = abs(float(root_matrix[0]))
    compensation = float(zone["geometry_scale"])
    if abs(root_scale * compensation - 1.0) > 0.000001:
        fail(
            "geometry_scale does not cancel the Halas GLB root scale "
            f"({root_scale} * {compensation})"
        )

    records = 0
    for line in runtime_manifest.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(",")
        if len(fields) != 11:
            fail(f"invalid placement record {records + 1}: expected 11 fields")
        if not (RUNTIME_PROPS / f"{fields[0]}.glb").is_file():
            fail(f"placement references absent runtime prop: {fields[0]}")
        # Keep all three source components; no uniform-scale assumption is valid
        # for future zone exports even though Halas happens to use uniform rows.
        [float(component) for component in fields[7:10]]
        records += 1

    npc_data = json.loads((ROOT / "data/halas_npcs_source.json").read_text())
    explicit_sizes = sum(float(npc["size"]) > 0.0 for npc in npc_data["npc_types"])
    print(
        "PASS: Halas scale provenance — "
        f"zone root {root_scale:g} × runtime {compensation:g} = 1; "
        f"{len(runtime_props)} exact prop GLBs; {records} exact placements; "
        f"{explicit_sizes}/{len(npc_data['npc_types'])} NPC source sizes explicit."
    )


if __name__ == "__main__":
    main()
