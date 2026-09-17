#!/usr/bin/env python3
"""Regression test: merchant classic filtering must follow schema column names."""

from __future__ import annotations

import tempfile
import zipfile
from pathlib import Path

from import_peq_halas_merchants import (
    SQL_MEMBER,
    available_in_classic,
    table_columns,
)


SCHEMA_COLUMNS = [
    "merchantid",
    "slot",
    "item",
    "content_flags_disabled",
    "faction_required",
    "level_required",
    "min_status",
    "min_expansion",
    "max_status",
    "alt_currency_cost",
    "classes_required",
    "probability",
    "unused_a",
    "unused_b",
    "unused_c",
    "unused_d",
    "content_flags",
    "unused_e",
    "max_expansion",
]


def build_archive(path: Path) -> None:
    schema = ["CREATE TABLE `merchantlist` ("]
    schema.extend(f"  `{name}` int DEFAULT NULL," for name in SCHEMA_COLUMNS[:-1])
    schema.append(f"  `{SCHEMA_COLUMNS[-1]}` int DEFAULT NULL")
    schema.append(");")

    with zipfile.ZipFile(path, "w") as bundle:
        bundle.writestr(SQL_MEMBER, "\n".join(schema) + "\n")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="eqm-merchant-schema-test-") as temp_dir:
        archive = Path(temp_dir) / "schema-test.zip"
        build_archive(archive)

        columns = table_columns(archive, "merchantlist")

        expected = {
            name: index for index, name in enumerate(SCHEMA_COLUMNS)
        }
        assert columns == expected, (
            f"schema mapping mismatch: expected={expected}, actual={columns}"
        )

        # Deliberately place the availability columns somewhere other than
        # their historic fixed offsets. Old offset-based code would read
        # unrelated values below and incorrectly reject this row.
        row = ["0"] * len(SCHEMA_COLUMNS)

        row[columns["min_expansion"]] = "-1"
        row[columns["max_expansion"]] = "-1"
        row[columns["content_flags"]] = "NULL"
        row[columns["content_flags_disabled"]] = "NULL"

        # Poison the former hard-coded positions 13..16.
        row[13] = "1"
        row[14] = "1"
        row[15] = "1"

        # Index 16 is content_flags in this deliberately reordered schema,
        # so restore its correct source value after poisoning nearby offsets.
        row[columns["content_flags"]] = "NULL"

        assert available_in_classic(row, columns), (
            "classic merchant row was rejected after schema column reordering"
        )

        row[columns["min_expansion"]] = "1"
        assert not available_in_classic(row, columns), (
            "future-expansion merchant row was incorrectly accepted"
        )

        row[columns["min_expansion"]] = "-1"
        row[columns["content_flags"]] = "seasonal_event"
        assert not available_in_classic(row, columns), (
            "content-flagged merchant row was incorrectly accepted"
        )

    print(
        "PASS: merchant importer resolves classic-availability fields "
        "from schema column names."
    )


if __name__ == "__main__":
    main()
