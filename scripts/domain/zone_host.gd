class_name ZoneHost
extends RefCounted

var active_zone_key := ""
var active_definition: Dictionary = {}
var active_runtime_state: ZoneRuntimeState
var state_store: ZoneStateStore
var spawn_resolver: ZoneSpawnResolver
var resolved_spawns: Dictionary = {}
var last_error := ""


func _init(
    store: ZoneStateStore = null
) -> void:
    state_store = (
        store
        if store != null
        else ZoneStateStore.new()
    )


func prepare_load(
    loader: ZoneDefinitionLoader,
    zone_key: String = "",
    capture_current: bool = true
) -> bool:
    if loader == null:
        return _fail(
            "ZoneHost requires a ZoneDefinitionLoader"
        )

    var definition := loader.load_zone(
        zone_key
    )

    if definition.is_empty():
        return _fail(
            "Unable to load zone definition: %s"
            % loader.last_error
        )

    return prepare_definition(
        definition,
        capture_current
    )


func prepare_definition(
    definition: Dictionary,
    capture_current: bool = true
) -> bool:
    var zone_key := str(
        definition.get(
            "key",
            ""
        )
    )

    if (
        zone_key.is_empty()
        or not zone_key.begins_with(
            "eqm:zone:"
        )
    ):
        return _fail(
            "ZoneHost requires a stable eqm:zone: key"
        )

    if (
        capture_current
        and active_runtime_state != null
    ):
        if not capture_active_zone():
            return false

    active_zone_key = zone_key
    active_definition = definition.duplicate(
        true
    )
    active_runtime_state = ZoneRuntimeState.new(
        active_zone_key
    )
    spawn_resolver = ZoneSpawnResolver.new(
        active_zone_key
    )
    resolved_spawns = {}

    if state_store.has_zone(
        active_zone_key
    ):
        if not state_store.restore_zone(
            active_zone_key,
            active_runtime_state
        ):
            return _fail(
                "Unable to restore stored state for %s: %s"
                % [
                    active_zone_key,
                    state_store.last_error,
                ]
            )

    last_error = ""
    return true


func restore_active_from_store() -> bool:
    if active_runtime_state == null:
        return _fail(
            "ZoneHost has no prepared active zone"
        )

    if not state_store.has_zone(
        active_zone_key
    ):
        last_error = ""
        return true

    if not state_store.restore_zone(
        active_zone_key,
        active_runtime_state
    ):
        return _fail(
            "Unable to restore stored state for %s: %s"
            % [
                active_zone_key,
                state_store.last_error,
            ]
        )

    last_error = ""
    return true


func resolve_spawns(
    npc_dataset: Dictionary
) -> bool:
    if active_runtime_state == null:
        return _fail(
            "ZoneHost must prepare a zone before resolving spawns"
        )

    if spawn_resolver == null:
        return _fail(
            "ZoneHost has no SpawnResolver for the active zone"
        )

    resolved_spawns = (
        spawn_resolver.resolve_into_state(
            npc_dataset,
            active_runtime_state
        )
    )

    if not spawn_resolver.last_error.is_empty():
        return _fail(
            spawn_resolver.last_error
        )

    last_error = ""
    return true


func capture_active_zone() -> bool:
    if active_runtime_state == null:
        last_error = ""
        return true

    if not state_store.capture_zone(
        active_runtime_state
    ):
        return _fail(
            "Unable to capture active zone %s: %s"
            % [
                active_zone_key,
                state_store.last_error,
            ]
        )

    last_error = ""
    return true


func unload_active_zone(
    capture_state: bool = true
) -> bool:
    if (
        capture_state
        and active_runtime_state != null
    ):
        if not capture_active_zone():
            return false

    active_zone_key = ""
    active_definition = {}
    active_runtime_state = null
    spawn_resolver = null
    resolved_spawns = {}
    last_error = ""
    return true


func is_prepared() -> bool:
    return (
        not active_zone_key.is_empty()
        and not active_definition.is_empty()
        and active_runtime_state != null
        and spawn_resolver != null
    )


func _fail(
    message: String
) -> bool:
    last_error = message
    return false
