class_name ZoneRuntimeState
extends RefCounted

const SCHEMA_VERSION := 1

const SPAWN_EMPTY := "empty"
const SPAWN_OCCUPIED := "occupied"
const SPAWN_RESPAWNING := "respawning"

var zone_key := ""
var spawn_points: Dictionary = {}
var world_objects: Dictionary = {}
var last_error := ""


func _init(
    zone_key_value: String = ""
) -> void:
    if not zone_key_value.is_empty():
        configure(
            zone_key_value
        )


func configure(
    zone_key_value: String
) -> void:
    assert(
        zone_key_value.begins_with(
            "eqm:zone:"
        ),
        "Zone runtime state requires a stable zone key"
    )

    zone_key = zone_key_value
    spawn_points.clear()
    world_objects.clear()
    last_error = ""


func ensure_spawn_point(
    spawn_key: String,
    spawn_group_ref: String = "",
    respawn_seconds: float = -1.0
) -> Dictionary:
    assert(
        not spawn_key.is_empty(),
        "Spawn runtime state requires a stable spawn key"
    )

    if not spawn_points.has(
        spawn_key
    ):
        spawn_points[
            spawn_key
        ] = {
            "spawn_key": spawn_key,
            "spawn_group_ref":
                spawn_group_ref,
            "selected_definition_ref": "",
            "occupant_entity_id": "",
            "state": SPAWN_EMPTY,
            "respawn_seconds":
                respawn_seconds,
            "respawn_remaining": -1.0,
            "runtime": {},
        }

    return (
        spawn_points[
            spawn_key
        ] as Dictionary
    ).duplicate(true)


func select_spawn_definition(
    spawn_key: String,
    selected_definition_ref: String
) -> bool:
    if spawn_key.is_empty():
        return _fail(
            "Spawn selection requires a stable spawn key"
        )

    if selected_definition_ref.is_empty():
        return _fail(
            "Spawn selection requires a definition reference"
        )

    var state_variant: Variant = spawn_points.get(
        spawn_key,
        null
    )

    if not state_variant is Dictionary:
        return _fail(
            "Spawn selection references an unknown spawn point: %s"
            % spawn_key
        )

    var state: Dictionary = (
        state_variant as Dictionary
    ).duplicate(true)

    state[
        "selected_definition_ref"
    ] = selected_definition_ref

    spawn_points[
        spawn_key
    ] = state

    last_error = ""
    return true


func occupy_spawn(
    spawn_key: String,
    occupant_entity_id: String,
    selected_definition_ref: String
) -> void:
    ensure_spawn_point(
        spawn_key
    )

    assert(
        not occupant_entity_id.is_empty(),
        "Occupied spawn requires an entity ID"
    )
    assert(
        not selected_definition_ref.is_empty(),
        "Occupied spawn requires a selected definition"
    )

    var state: Dictionary = spawn_points[
        spawn_key
    ]

    state[
        "selected_definition_ref"
    ] = selected_definition_ref
    state[
        "occupant_entity_id"
    ] = occupant_entity_id
    state[
        "state"
    ] = SPAWN_OCCUPIED
    state[
        "respawn_remaining"
    ] = -1.0

    spawn_points[
        spawn_key
    ] = state


func begin_respawn(
    spawn_key: String,
    selected_definition_ref: String,
    remaining_seconds: float
) -> void:
    ensure_spawn_point(
        spawn_key
    )

    var state: Dictionary = spawn_points[
        spawn_key
    ]

    state[
        "selected_definition_ref"
    ] = selected_definition_ref
    state[
        "occupant_entity_id"
    ] = ""
    state[
        "state"
    ] = SPAWN_RESPAWNING
    state[
        "respawn_remaining"
    ] = maxf(
        0.0,
        remaining_seconds
    )

    spawn_points[
        spawn_key
    ] = state


func clear_spawn(
    spawn_key: String,
    preserve_selection: bool = true
) -> void:
    ensure_spawn_point(
        spawn_key
    )

    var state: Dictionary = spawn_points[
        spawn_key
    ]

    state[
        "occupant_entity_id"
    ] = ""
    state[
        "state"
    ] = SPAWN_EMPTY
    state[
        "respawn_remaining"
    ] = -1.0

    if not preserve_selection:
        state[
            "selected_definition_ref"
        ] = ""

    spawn_points[
        spawn_key
    ] = state


func set_spawn_runtime(
    spawn_key: String,
    runtime_state: Dictionary
) -> void:
    ensure_spawn_point(
        spawn_key
    )

    var state: Dictionary = spawn_points[
        spawn_key
    ]

    state[
        "runtime"
    ] = runtime_state.duplicate(true)

    spawn_points[
        spawn_key
    ] = state


func spawn_state(
    spawn_key: String
) -> Dictionary:
    var state_variant: Variant = spawn_points.get(
        spawn_key,
        {}
    )

    if not state_variant is Dictionary:
        return {}

    return (
        state_variant as Dictionary
    ).duplicate(true)


func set_world_object_state(
    object_key: String,
    state_value: Dictionary
) -> void:
    assert(
        not object_key.is_empty(),
        "World object state requires a stable key"
    )

    world_objects[
        object_key
    ] = state_value.duplicate(true)


func world_object_state(
    object_key: String
) -> Dictionary:
    var state_variant: Variant = world_objects.get(
        object_key,
        {}
    )

    if not state_variant is Dictionary:
        return {}

    return (
        state_variant as Dictionary
    ).duplicate(true)


func snapshot() -> Dictionary:
    return {
        "schema_version": SCHEMA_VERSION,
        "zone_key": zone_key,
        "spawn_points":
            spawn_points.duplicate(true),
        "world_objects":
            world_objects.duplicate(true),
    }


func restore(
    payload: Dictionary,
    expected_zone_key: String = ""
) -> bool:
    if (
        int(
            payload.get(
                "schema_version",
                0
            )
        )
        != SCHEMA_VERSION
    ):
        return _fail(
            "Unsupported zone runtime-state schema version"
        )

    var payload_zone_key := str(
        payload.get(
            "zone_key",
            ""
        )
    )

    if not payload_zone_key.begins_with(
        "eqm:zone:"
    ):
        return _fail(
            "Zone runtime state has no stable zone key"
        )

    if (
        not expected_zone_key.is_empty()
        and payload_zone_key
            != expected_zone_key
    ):
        return _fail(
            "Zone runtime state belongs to another zone"
        )

    var spawn_variant: Variant = payload.get(
        "spawn_points",
        {}
    )
    var objects_variant: Variant = payload.get(
        "world_objects",
        {}
    )

    if (
        not spawn_variant is Dictionary
        or not objects_variant is Dictionary
    ):
        return _fail(
            "Zone runtime state payload is malformed"
        )

    zone_key = payload_zone_key
    spawn_points = (
        spawn_variant as Dictionary
    ).duplicate(true)
    world_objects = (
        objects_variant as Dictionary
    ).duplicate(true)

    last_error = ""
    return true


func _fail(
    message: String
) -> bool:
    last_error = message
    return false
