#!/usr/bin/env python3
"""Generate Phase 2 semantic registries and the Halas spell reference closure.

Usage:
  python3 tools/import_phase2_identity.py PEQ_ARCHIVE [OUTPUT_DIRECTORY]

This imports identities and relationships only.  It does not enable class,
race, skill, spell, or quest gameplay.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

from import_peq_halas import as_int, rows_for_table, table_columns

ROOT = Path(__file__).resolve().parents[1]
SQL_MEMBER = "peq-dump/create_tables_content.sql"
CLASSIC = 0


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def meta(dataset_id: str, tool: str, sources: list[dict], filters: dict,
         review_state: str = "current_unreviewed_peq") -> dict:
    return {
        "schema_id": "eqm.identity_registry",
        "schema_version": 1,
        "dataset_id": dataset_id,
        "meta": {
            "era_profile": "original_classic_pre_kunark",
            "design_target": "classic_p1999",
            "review_state": review_state,
            "evidence": [{"label": "confirmed_source_behavior", "claim": "Source identity and relationship registry"}],
            "sources": sources,
            "generator": {"tool": tool},
            "filters": filters,
            "overlay": None,
        },
    }


def constants(path: Path, namespace: str, ctype: str) -> dict[str, int]:
    expression = re.compile(rf"constexpr\s+{ctype}\s+(\w+)\s*=\s*(\d+);")
    return {name: int(value) for name, value in expression.findall(path.read_text())}


def display_names_from_switch(path: Path, scope: str) -> dict[str, str]:
    """Read simple stacked switch cases, retaining each source symbol's name."""
    names, pending = {}, []
    for line in path.read_text().splitlines():
        case = re.search(rf"case {re.escape(scope)}::(\w+):", line)
        if case:
            pending.append(case.group(1))
        returned = re.search(r'return "([^"]*)";', line)
        if returned and pending:
            for symbol in pending:
                names.setdefault(symbol, returned.group(1))
            pending = []
    return names


def classic_player_ids(archive: Path) -> tuple[set[int], set[int]]:
    columns = table_columns(archive, "char_create_combinations")
    races, classes = set(), set()
    for row in rows_for_table(archive, "char_create_combinations"):
        if as_int(row[columns["expansions_req"]]) == CLASSIC:
            races.add(as_int(row[columns["race"]]))
            classes.add(as_int(row[columns["class"]]))
    return races, classes


def available_entry(row: list[str], columns: dict[str, int]) -> bool:
    return (
        as_int(row[columns["min_expansion"]]) in (-1, CLASSIC)
        and as_int(row[columns["max_expansion"]]) in (-1, CLASSIC)
        and row[columns["content_flags"]] == "NULL"
        and row[columns["content_flags_disabled"]] == "NULL"
    )


def display_symbol(symbol: str) -> str:
    if symbol.endswith("GM"):
        return display_symbol(symbol[:-2]) + " Guildmaster"
    return re.sub(r"(?<!^)([A-Z])", r" \1", symbol)


def main() -> None:
    if not 2 <= len(sys.argv) <= 3:
        raise SystemExit(__doc__)
    archive = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve() if len(sys.argv) == 3 else ROOT / "data"
    if not archive.is_file():
        raise SystemExit(f"Archive not found: {archive}")
    output.mkdir(parents=True, exist_ok=True)
    classes_h, classes_cpp = ROOT / "resources/EQEmu-master/common/classes.h", ROOT / "resources/EQEmu-master/common/classes.cpp"
    races_h, races_cpp = ROOT / "resources/EQEmu-master/common/races.h", ROOT / "resources/EQEmu-master/common/races.cpp"
    skills_h, skills_cpp = ROOT / "resources/EQEmu-master/common/skills.h", ROOT / "resources/EQEmu-master/common/skills.cpp"
    eqemu_sources = lambda files: [{"namespace": "eqemu", "artifact": str(p.relative_to(ROOT)), "sha256": digest(p)} for p in files]
    peq_source = {"namespace": "peq", "artifact": archive.name, "sha256": digest(archive), "member": SQL_MEMBER}
    player_races, player_classes = classic_player_ids(archive)

    class_symbols = {name: ident for name, ident in constants(classes_h, "Class", "uint8").items() if ident > 0 and name not in {"PLAYER_CLASS_COUNT"}}
    player_class_names = {
        symbol: name
        for symbol, name in re.findall(r'\{Class::(\w+),\s*"([^"]+)"\}', classes_h.read_text())
    }
    service_class_names = display_names_from_switch(classes_cpp, "Class")
    class_data = meta("eqm:dataset:eqemu-classes", "tools/import_phase2_identity.py", eqemu_sources([classes_h, classes_cpp]) + [peq_source], {"all_nonzero_eqemu_class_constants": True, "classic_player_evidence": "char_create_combinations.expansions_req=0"})
    class_data["classes"] = {str(ident): {"key": f"eqemu:class:{ident}", "source_id": ident, "source_symbol": symbol, "name": (player_class_names.get(symbol, display_symbol(symbol)) if ident <= 16 else service_class_names.get(symbol, display_symbol(symbol))), "player_class": ident <= 16, **({"availability": {"original_classic_pre_kunark": "current_peq_supported"}} if ident in player_classes else {})} for symbol, ident in sorted(class_symbols.items(), key=lambda item: item[1])}
    write(output / "eqemu_classes.json", class_data)

    race_symbols = {name: ident for name, ident in constants(races_h, "Race", "uint16").items()}
    race_names = display_names_from_switch(races_cpp, "Race")
    halas_npcs = json.loads((ROOT / "data/halas_npcs.json").read_text())["npc_types"]
    race_ids = player_races | {int(npc["race"]) for npc in halas_npcs}
    missing_races = race_ids - set(race_symbols.values())
    if missing_races:
        raise SystemExit(f"Halas races absent from EQEmu registry: {sorted(missing_races)}")
    races_by_id = {}
    for symbol, ident in sorted(race_symbols.items(), key=lambda item: item[1]):
        if ident in race_ids and ident not in races_by_id:
            races_by_id[ident] = {"key": f"eqemu:race:{ident}", "source_id": ident, "source_symbol": symbol, "name": race_names.get(symbol, re.sub(r"(?<!^)([A-Z])", r" \1", symbol)), "player_race": ident in player_races, **({"availability": {"original_classic_pre_kunark": "current_peq_supported"}} if ident in player_races else {})}
    race_data = meta("eqm:dataset:eqemu-races-halas", "tools/import_phase2_identity.py", eqemu_sources([races_h, races_cpp]) + [peq_source], {"classic_player_races": "char_create_combinations.expansions_req=0", "npc_closure": "data/halas_npcs.json"})
    race_data["races"] = {str(ident): races_by_id[ident] for ident in sorted(races_by_id)}
    write(output / "eqemu_races.json", race_data)

    # Enum declarations may omit an explicit value; recover their sequence and aliases.
    enum = re.search(r"enum SkillType : int \{(.*?)SkillCount", skills_h.read_text(), re.S).group(1)
    skills, current = {}, -1
    for symbol, assignment in re.findall(r"\b(Skill\w+)\s*(?:=\s*(Skill\w+|\d+))?\s*,", enum):
        if not assignment:
            current += 1
        elif assignment.isdigit():
            current = int(assignment)
        else:
            current = skills[assignment]["source_id"]
        if symbol not in skills:
            skills[symbol] = {"source_id": current}
    skill_names = {symbol: name for symbol, name in re.findall(r'\{\s*(Skill\w+),\s*"([^"]+)"\s*\}', skills_cpp.read_text())}
    by_id = {}
    for symbol, record in skills.items():
        ident = record["source_id"]
        if symbol in skill_names:
            if ident not in by_id:
                by_id[ident] = {"key": f"eqemu:skill:{ident}", "source_id": ident, "source_symbol": symbol, "name": skill_names[symbol], "aliases": [], "era_hint": "sof_plus" if ident in (75, 76) else "rof2_plus" if ident == 77 else None}
            elif symbol != by_id[ident]["source_symbol"]:
                by_id[ident]["aliases"].append(symbol)
    # EQEmu intentionally omits the Iksar-only Tail Rake synonym from its
    # display-name map; it is still a named enum alias of Dragon Punch.
    if "SkillTailRake" in skills:
        tail_rake_id = skills["SkillTailRake"]["source_id"]
        if tail_rake_id in by_id and "SkillTailRake" not in by_id[tail_rake_id]["aliases"]:
            by_id[tail_rake_id]["aliases"].append("SkillTailRake")
    skill_data = meta("eqm:dataset:eqemu-skills", "tools/import_phase2_identity.py", eqemu_sources([skills_h, skills_cpp]), {"active_get_skill_type_map": True})
    skill_data["skills"] = {str(ident): by_id[ident] for ident in sorted(by_id)}
    write(output / "eqemu_skills.json", skill_data)

    npc_ids = {int(n["npc_spells_id"]) for n in halas_npcs if int(n["npc_spells_id"]) > 0}
    npc_cols, entry_cols, spell_cols = (table_columns(archive, name) for name in ("npc_spells", "npc_spells_entries", "spells_new"))
    all_lists = {as_int(row[npc_cols["id"]]): row for row in rows_for_table(archive, "npc_spells")}
    closure = set(npc_ids)
    while True:
        parents = {as_int(all_lists[ident][npc_cols["parent_list"]]) for ident in closure if as_int(all_lists[ident][npc_cols["parent_list"]]) > 0}
        if not parents - set(all_lists):
            pass
        missing = parents - set(all_lists)
        if missing:
            raise SystemExit(f"Missing NPC spell-list parents: {sorted(missing)}")
        expanded = closure | parents
        if expanded == closure:
            break
        closure = expanded
    for start in closure:
        seen, cursor = set(), start
        while cursor:
            if cursor in seen:
                raise SystemExit(f"NPC spell-list parent cycle at {start}")
            seen.add(cursor)
            cursor = as_int(all_lists[cursor][npc_cols["parent_list"]])
    entries = {ident: [] for ident in closure}
    for row in rows_for_table(archive, "npc_spells_entries"):
        list_id = as_int(row[entry_cols["npc_spells_id"]])
        if list_id in entries and available_entry(row, entry_cols):
            entries[list_id].append(row)
    spell_ids = {as_int(row[entry_cols["spellid"]]) for records in entries.values() for row in records if as_int(row[entry_cols["spellid"]]) > 0}
    lists = {}
    for ident in sorted(closure):
        row = all_lists[ident]
        proc_ids = [as_int(row[npc_cols[name]]) for name in ("attack_proc", "range_proc", "defensive_proc") if as_int(row[npc_cols[name]]) > 0]
        spell_ids.update(proc_ids)
        lists[str(ident)] = {"key": f"peq:npc_spell_list:{ident}", "source_id": ident, "name": None if row[npc_cols["name"]] == "NULL" else row[npc_cols["name"]], "parent_ref": f"peq:npc_spell_list:{as_int(row[npc_cols['parent_list']])}" if as_int(row[npc_cols["parent_list"]]) > 0 else None, "entries": [{"spell_ref": f"peq:spell:{as_int(entry[entry_cols['spellid']])}", "type_raw": as_int(entry[entry_cols["type"]]), "min_level": as_int(entry[entry_cols["minlevel"]]), "max_level": as_int(entry[entry_cols["maxlevel"]]), "mana_cost_override": as_int(entry[entry_cols["manacost"]]), "recast_delay_override": as_int(entry[entry_cols["recast_delay"]]), "priority": as_int(entry[entry_cols["priority"]])} for entry in entries[ident]], "proc_spell_refs": [f"peq:spell:{value}" for value in proc_ids], "activation": "inactive"}
    spell_rows = {as_int(row[spell_cols["id"]]): row for row in rows_for_table(archive, "spells_new") if as_int(row[spell_cols["id"]]) in spell_ids}
    missing = spell_ids - set(spell_rows)
    if missing:
        raise SystemExit(f"Referenced spells missing from spells_new: {sorted(missing)}")
    spells = {}
    for ident, row in sorted(spell_rows.items()):
        raw_skill = as_int(row[spell_cols["skill"]])
        spells[str(ident)] = {"key": f"peq:spell:{ident}", "source_id": ident, "name": row[spell_cols["name"]], "casting_skill_id_raw": raw_skill, "casting_skill_ref": f"eqemu:skill:{raw_skill}" if raw_skill in by_id else None, "class_levels_raw": {f"eqemu:class:{class_id}": as_int(row[spell_cols[f"classes{class_id}"]]) for class_id in range(1, 17)}, "source_raw": {name: as_int(row[spell_cols[name]]) for name in ("range", "cast_time", "recovery_time", "recast_time", "mana", "targettype", "spellgroup", "rank")}, "review_state": "current_unreviewed_peq"}
    spell_data = meta("eqm:dataset:halas-spell-closure", "tools/import_phase2_identity.py", [peq_source], {"npc_spell_list_closure": "data/halas_npcs.json", "npc_spells_entries": "classic expansion/content-flag eligible", "spells_new": "relationship closure only"})
    spell_data["npc_spell_lists"], spell_data["spells"] = lists, spells
    write(output / "halas_spells_source.json", spell_data)

    contract = ROOT / "docs/identity-contract.md"
    quest_data = meta("eqm:dataset:quests", "tools/import_phase2_identity.py", [{"namespace": "eqm", "artifact": "docs/identity-contract.md", "sha256": digest(contract)}], {"classic_quest_import": "deferred pending reviewed script evidence"}, "pending_reviewed_quest_evidence")
    quest_data["quests"] = {}
    write(output / "quests.json", quest_data)
    print(f"Wrote {len(class_data['classes'])} classes, {len(race_data['races'])} races, {len(skill_data['skills'])} skills, {len(lists)} spell lists, {len(spells)} spells, and an empty quest registry.")


if __name__ == "__main__":
    main()
