class_name ZoneSpawnResolver
extends RefCounted

const SELECTION_MODE_COMPATIBILITY := (
    "legacy_spawn2_mod_weight"
)

var zone_key := ""
var last_error := ""


func _init(
    initial_zone_key: String = ""
) -> void:
    zone_key = initial_zone_key


func resolve_into_state(
    dataset: Dictionary,
    runtime_state: ZoneRuntimeState
) -> Dictionary:
    last_error = ""

    if runtime_state == null:
        return _fail_dictionary(
            "Zone spawn resolution requires ZoneRuntimeState"
        )

    if not zone_key.begins_with(
        "eqm:zone:"
    ):
        return _fail_dictionary(
            "Zone spawn resolver requires a stable zone key"
        )

    if runtime_state.zone_key.is_empty():
        runtime_state.zone_key = zone_key
    elif runtime_state.zone_key != zone_key:
        return _fail_dictionary(
            "Zone runtime state belongs to another zone"
        )

    var npc_types := _npc_types_by_ref(
        dataset
    )

    if not last_error.is_empty():
        return {}

    var spawn_groups := _spawn_groups_by_ref(
        dataset
    )

    if not last_error.is_empty():
        return {}

    var spawns_variant: Variant = dataset.get(
        "spawns",
        []
    )

    if not spawns_variant is Array:
        return _fail_dictionary(
            "NPC dataset has no spawn array"
        )

    var resolved: Dictionary = {}

    for spawn_variant in (
        spawns_variant as Array
    ):
        if not spawn_variant is Dictionary:
            return _fail_dictionary(
                "NPC dataset contains a non-dictionary spawn"
            )

        var spawn: Dictionary = spawn_variant
        var spawn2_id := int(
            spawn.get(
                "spawn2_id",
                0
            )
        )

        if spawn2_id <= 0:
            return _fail_dictionary(
                "NPC dataset contains a spawn without spawn2 identity"
            )

        var spawn_key := str(
            spawn.get(
                "key",
                spawn_key_for_id(
                    spawn2_id
                )
            )
        )

        if spawn_key.is_empty():
            return _fail_dictionary(
                "NPC spawn has no stable spawn key"
            )

        var spawn_group_ref := str(
            spawn.get(
                "spawn_group_ref",
                spawn_group_key_for_id(
                    int(
                        spawn.get(
                            "spawn_group_id",
                            0
                        )
                    )
                )
            )
        )

        var group_variant: Variant = (
            spawn_groups.get(
                spawn_group_ref,
                null
            )
        )

        if not group_variant is Dictionary:
            return _fail_dictionary(
                "Spawn %s has unresolved SpawnGroup %s"
                % [
                    spawn_key,
                    spawn_group_ref,
                ]
            )

        var group: Dictionary = group_variant

        runtime_state.ensure_spawn_point(
            spawn_key,
            spawn_group_ref,
            float(
                spawn.get(
                    "respawn_seconds",
                    -1.0
                )
            )
        )

        var existing_state := (
            runtime_state.spawn_state(
                spawn_key
            )
        )

        var selected_ref := str(
            existing_state.get(
                "selected_definition_ref",
                ""
            )
        )

        if selected_ref.is_empty():
            selected_ref = (
                _compatibility_selection(
                    spawn2_id,
                    group
                )
            )

            if selected_ref.is_empty():
                return _fail_dictionary(
                    "Spawn %s has no selectable NPC definition"
                    % spawn_key
                )

            if not runtime_state.select_spawn_definition(
                spawn_key,
                selected_ref
            ):
                return _fail_dictionary(
                    runtime_state.last_error
                )
        elif not _group_contains_definition(
            group,
            selected_ref
        ):
            return _fail_dictionary(
                "Stored spawn selection %s is no longer a candidate for %s"
                % [
                    selected_ref,
                    spawn_key,
                ]
            )

        _ensure_spawn_runtime_defaults(
            runtime_state,
            spawn_key,
            spawn
        )

        var npc_variant: Variant = (
            npc_types.get(
                selected_ref,
                null
            )
        )

        if not npc_variant is Dictionary:
            return _fail_dictionary(
                "Spawn %s selected unresolved NPC definition %s"
                % [
                    spawn_key,
                    selected_ref,
                ]
            )

        resolved[
            spawn_key
        ] = {
            "spawn_key":
                spawn_key,
            "spawn2_id":
                spawn2_id,
            "spawn_group_ref":
                spawn_group_ref,
            "selected_definition_ref":
                selected_ref,
            "respawn_seconds":
                float(
                    spawn.get(
                        "respawn_seconds",
                        -1.0
                    )
                ),
            "grid_id":
                int(
                    spawn.get(
                        "grid_id",
                        0
                    )
                ),
            "position_eq":
                _array_copy(
                    spawn.get(
                        "position_eq",
                        []
                    )
                ),
            "heading_eq":
                float(
                    spawn.get(
                        "heading_eq",
                        -1.0
                    )
                ),
            "selection_mode":
                SELECTION_MODE_COMPATIBILITY,
            "npc_definition":
                (
                    npc_variant as Dictionary
                ).duplicate(true),
        }

    return resolved


func _ensure_spawn_runtime_defaults(
    runtime_state: ZoneRuntimeState,
    spawn_key: String,
    spawn: Dictionary
) -> void:
    var state := runtime_state.spawn_state(
        spawn_key
    )

    var runtime_variant: Variant = state.get(
        "runtime",
        {}
    )

    var runtime: Dictionary = (
        (
            runtime_variant as Dictionary
        ).duplicate(true)
        if runtime_variant is Dictionary
        else {}
    )

    if not runtime.has(
        "grid_id"
    ):
        runtime[
            "grid_id"
        ] = int(
            spawn.get(
                "grid_id",
                0
            )
        )

    if not runtime.has(
        "patrol_index"
    ):
        runtime[
            "patrol_index"
        ] = 0

    if not runtime.has(
        "pause_remaining"
    ):
        runtime[
            "pause_remaining"
        ] = 0.0

    runtime_state.set_spawn_runtime(
        spawn_key,
        runtime
    )


func _npc_types_by_ref(
    dataset: Dictionary
) -> Dictionary:
    var values_variant: Variant = dataset.get(
        "npc_types",
        []
    )

    if not values_variant is Array:
        return _fail_dictionary(
            "NPC dataset has no npc_types array"
        )

    var result: Dictionary = {}

    for npc_variant in (
        values_variant as Array
    ):
        if not npc_variant is Dictionary:
            return _fail_dictionary(
                "NPC dataset contains a non-dictionary npc_type"
            )

        var npc: Dictionary = npc_variant
        var npc_id := int(
            npc.get(
                "id",
                0
            )
        )
        var npc_ref := str(
            npc.get(
                "key",
                npc_key_for_id(
                    npc_id
                )
            )
        )

        if (
            npc_ref.is_empty()
            or result.has(
                npc_ref
            )
        ):
            return _fail_dictionary(
                "NPC dataset contains duplicate or empty NPC identity: %s"
                % npc_ref
            )

        result[
            npc_ref
        ] = npc

    return result


func _spawn_groups_by_ref(
    dataset: Dictionary
) -> Dictionary:
    var groups_variant: Variant = dataset.get(
        "spawn_groups",
        {}
    )

    if not groups_variant is Dictionary:
        return _fail_dictionary(
            "NPC dataset has no spawn_groups dictionary"
        )

    var result: Dictionary = {}

    for group_id_variant in (
        groups_variant as Dictionary
    ):
        var group_variant: Variant = (
            (groups_variant as Dictionary)[
                group_id_variant
            ]
        )

        if not group_variant is Dictionary:
            return _fail_dictionary(
                "NPC dataset contains a non-dictionary SpawnGroup"
            )

        var group: Dictionary = group_variant
        var group_id := int(
            group.get(
                "id",
                group_id_variant
            )
        )
        var group_ref := str(
            group.get(
                "key",
                spawn_group_key_for_id(
                    group_id
                )
            )
        )

        if (
            group_ref.is_empty()
            or result.has(
                group_ref
            )
        ):
            return _fail_dictionary(
                "NPC dataset contains duplicate or empty SpawnGroup identity: %s"
                % group_ref
            )

        result[
            group_ref
        ] = group

    return result


func _compatibility_selection(
    spawn2_id: int,
    group: Dictionary
) -> String:
    var candidates_variant: Variant = (
        group.get(
            "candidates",
            []
        )
    )

    if not candidates_variant is Array:
        return ""

    var candidates: Array = (
        candidates_variant as Array
    )

    if candidates.is_empty():
        return ""

    var total_weight := 0

    for candidate_variant in candidates:
        if not candidate_variant is Dictionary:
            continue

        total_weight += maxi(
            0,
            int(
                (
                    candidate_variant
                    as Dictionary
                ).get(
                    "chance",
                    0
                )
            )
        )

    if total_weight <= 0:
        return ""

    # Migration compatibility only:
    #
    # HalasNpcPopulation historically selected its visible roster with
    # spawn2_id % total_weight. Preserve that exact roster while ownership
    # moves into the generic zone runtime. A later reviewed slice can replace
    # first-selection behavior with canonical SimulationRng without silently
    # changing already-persisted selections.
    var roll := (
        spawn2_id
        % total_weight
    )

    for candidate_variant in candidates:
        if not candidate_variant is Dictionary:
            continue

        var candidate: Dictionary = (
            candidate_variant as Dictionary
        )

        roll -= maxi(
            0,
            int(
                candidate.get(
                    "chance",
                    0
                )
            )
        )

        if roll < 0:
            return _candidate_ref(
                candidate
            )

    var first_variant: Variant = candidates[0]

    if not first_variant is Dictionary:
        return ""

    return _candidate_ref(
        first_variant as Dictionary
    )


func _group_contains_definition(
    group: Dictionary,
    definition_ref: String
) -> bool:
    var candidates_variant: Variant = (
        group.get(
            "candidates",
            []
        )
    )

    if not candidates_variant is Array:
        return false

    for candidate_variant in (
        candidates_variant as Array
    ):
        if not candidate_variant is Dictionary:
            continue

        if _candidate_ref(
            candidate_variant as Dictionary
        ) == definition_ref:
            return true

    return false


func _candidate_ref(
    candidate: Dictionary
) -> String:
    return str(
        candidate.get(
            "npc_ref",
            npc_key_for_id(
                int(
                    candidate.get(
                        "npc_type_id",
                        0
                    )
                )
            )
        )
    )


func _array_copy(
    value: Variant
) -> Array:
    if not value is Array:
        return []

    return (
        value as Array
    ).duplicate(true)


static func spawn_key_for_id(
    spawn2_id: int
) -> String:
    return "peq:spawn:%d" % spawn2_id


static func spawn_group_key_for_id(
    spawn_group_id: int
) -> String:
    return (
        "peq:spawn_group:%d"
        % spawn_group_id
    )


static func npc_key_for_id(
    npc_type_id: int
) -> String:
    return "peq:npc:%d" % npc_type_id


func _fail_dictionary(
    message: String
) -> Dictionary:
    last_error = message
    return {}
