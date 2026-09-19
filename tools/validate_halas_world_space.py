#!/usr/bin/env python3
"""Check that Halas declares the Phase 1 coordinate contract explicitly."""
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
zone = json.loads((ROOT / "data" / "halas.json").read_text())
expected = {
    "unit": "one Godot world unit equals one native EQ world unit after geometry_scale",
    "server_axis_map": [-2, 3, 1],
    "server_position": "[x,y,elevation] -> [-y,elevation,x]",
    "server_heading": "0..512 -> Godot yaw pi/2 - heading*tau/512",
    "server_heading_units_per_turn": 512.0,
    "lantern_prop_position": "[x,y,z] -> [-x,y,z]",
    "lantern_prop_axis_map": [-1, 2, 3],
    "lantern_prop_heading": "degrees -> negative Godot yaw",
    "lantern_prop_heading_degrees_sign": -1.0,
}
assert zone.get("world_space_contract") == expected, "Halas world-space contract differs from the documented calibration"
assert zone.get("geometry_scale") == 10.0, "Halas geometry compensation must remain explicit"
print("PASS: Halas world-space contract is explicit and calibrated.")
