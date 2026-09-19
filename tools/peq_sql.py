#!/usr/bin/env python3
"""Shared ProjectEQ SQL-dump parsing and classic-era availability helpers.

This module owns source-format mechanics only. It contains no zone-specific
roster, overlay, presentation, or gameplay policy.
"""

from __future__ import annotations

import csv
import io
import re
import zipfile
from pathlib import Path


SQL_MEMBER = "peq-dump/create_tables_content.sql"
CLASSIC_EXPANSION = 0


def rows_for_table(
    archive: Path,
    table: str,
):
    """Stream simple mysqldump INSERT rows for one table."""
    marker = (
        f"INSERT INTO `{table}` VALUES"
        .encode()
    )
    reading = False

    with (
        zipfile.ZipFile(archive) as bundle,
        bundle.open(SQL_MEMBER) as raw,
    ):
        for raw_line in raw:
            line = (
                raw_line.decode("latin-1")
                .rstrip("\r\n")
            )

            if line == marker.decode():
                reading = True
                continue

            if not reading:
                continue

            if not line.startswith("("):
                reading = False
                continue

            payload = line[1:-2]

            yield next(
                csv.reader(
                    io.StringIO(payload),
                    delimiter=",",
                    quotechar="'",
                    escapechar="\\",
                    doublequote=False,
                )
            )

            if line.endswith(";"):
                reading = False


def as_float(
    value: str,
) -> float:
    return (
        float(value)
        if value != "NULL"
        else 0.0
    )


def as_int(
    value: str,
) -> int:
    return (
        int(float(value))
        if value != "NULL"
        else 0
    )


def is_available_in_classic(
    row: list[str],
) -> bool:
    """Return whether a spawn2 row is available in original EverQuest."""
    min_expansion = as_int(
        row[15]
    )
    max_expansion = as_int(
        row[16]
    )
    has_event_flags = (
        row[17] != "NULL"
        or row[18] != "NULL"
    )

    return (
        min_expansion
        in (
            -1,
            CLASSIC_EXPANSION,
        )
        and max_expansion
        in (
            -1,
            CLASSIC_EXPANSION,
        )
        and not has_event_flags
    )


def table_columns(
    archive: Path,
    table: str,
) -> dict[str, int]:
    """Read one PEQ table's declared column order."""
    marker = (
        f"CREATE TABLE `{table}` ("
    )
    names: list[str] = []
    reading = False

    with (
        zipfile.ZipFile(archive) as bundle,
        bundle.open(SQL_MEMBER) as raw,
    ):
        for raw_line in raw:
            line = (
                raw_line.decode("latin-1")
                .rstrip("\r\n")
            )

            if line == marker:
                reading = True
            elif (
                reading
                and line.startswith(")")
            ):
                break
            elif reading:
                match = re.match(
                    r"\s*`([^`]+)`",
                    line,
                )

                if match:
                    names.append(
                        match.group(1)
                    )

    if not names:
        raise SystemExit(
            f"Could not read schema for {table}"
        )

    return {
        name: index
        for index, name
        in enumerate(names)
    }


def spawnentry_available_in_classic(
    row: list[str],
    columns: dict[str, int],
) -> bool:
    """Return whether a spawnentry candidate is classic and ungated."""
    return (
        as_int(
            row[
                columns[
                    "min_expansion"
                ]
            ]
        )
        in (
            -1,
            CLASSIC_EXPANSION,
        )
        and as_int(
            row[
                columns[
                    "max_expansion"
                ]
            ]
        )
        in (
            -1,
            CLASSIC_EXPANSION,
        )
        and row[
            columns[
                "content_flags"
            ]
        ] == "NULL"
        and row[
            columns[
                "content_flags_disabled"
            ]
        ] == "NULL"
    )
