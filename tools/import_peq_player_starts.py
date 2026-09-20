#!/usr/bin/env python3
"""Import the complete PEQ start_zones baseline catalog.

Usage: python3 tools/import_peq_player_starts.py PEQ_ARCHIVE OUTPUT
"""
from __future__ import annotations
import hashlib
import json
import sys
from pathlib import Path

from peq_sql import as_float, as_int, rows_for_table, table_columns


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive, output = Path(sys.argv[1]), Path(sys.argv[2])
    columns = table_columns(archive, "start_zones")
    rows = []
    for raw in rows_for_table(archive, "start_zones"):
        row = {name: raw[index] for name, index in columns.items()}
        for name in ["player_choice", "player_class", "player_deity", "player_race", "start_zone", "zone_id", "bind_id", "select_rank", "min_expansion", "max_expansion"]:
            row[name] = as_int(row[name])
        for name in ["x", "y", "z", "heading", "bind_x", "bind_y", "bind_z"]:
            row[name] = as_float(row[name])
        rows.append(row)
    rows.sort(key=lambda r: (r["player_choice"], r["player_race"], r["player_class"], r["player_deity"], r["select_rank"], r["start_zone"]))
    value = {
        "schema_id": "eqm.player_start_source_catalog", "schema_version": 1,
        "dataset_id": "peq:player_start:catalog",
        "meta": {"era_profile": "original_classic_pre_kunark", "design_target": "classic_p1999", "review_state": "peq_baseline_not_automatically_p1999_exact", "evidence": [{"label": "confirmed_source_behavior", "claim": "Complete ProjectEQ start_zones snapshot retained as provenance baseline."}], "sources": [{"archive": archive.name, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "table": "start_zones"}], "generator": {"tool": "tools/import_peq_player_starts.py"}},
        "start_zones": rows,
    }
    output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
