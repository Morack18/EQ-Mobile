class_name ZoneStateStore
extends RefCounted

const SCHEMA_VERSION := 1

var _zone_snapshots: Dictionary = {}
var last_error := ""


func capture_zone(
    zone_state: ZoneRuntimeState
) -> bool:
    if zone_state == null:
        return _fail(
            "Cannot capture a null ZoneRuntimeState"
        )

    var zone_key := zone_state.zone_key

    if zone_key.is_empty():
        return _fail(
            "Cannot capture zone state without a zone key"
        )

    var snapshot := zone_state.snapshot()

    if not _snapshot_matches_zone(
        zone_key,
        snapshot
    ):
        return false

    _zone_snapshots[
        zone_key
    ] = snapshot.duplicate(true)

    last_error = ""
    return true


func has_zone(
    zone_key: String
) -> bool:
    return (
        not zone_key.is_empty()
        and _zone_snapshots.has(
            zone_key
        )
    )


func zone_snapshot(
    zone_key: String
) -> Dictionary:
    var value: Variant = (
        _zone_snapshots.get(
            zone_key,
            null
        )
    )

    if not value is Dictionary:
        return {}

    return (
        value as Dictionary
    ).duplicate(true)


func restore_zone(
    zone_key: String,
    destination: ZoneRuntimeState
) -> bool:
    if zone_key.is_empty():
        return _fail(
            "Zone restore requires a zone key"
        )

    if destination == null:
        return _fail(
            "Zone restore requires a destination ZoneRuntimeState"
        )

    var snapshot := zone_snapshot(
        zone_key
    )

    if snapshot.is_empty():
        return _fail(
            "No stored runtime state exists for zone %s"
            % zone_key
        )

    if not destination.restore(
        snapshot,
        zone_key
    ):
        return _fail(
            "Stored runtime state for %s could not be restored: %s"
            % [
                zone_key,
                destination.last_error,
            ]
        )

    last_error = ""
    return true


func erase_zone(
    zone_key: String
) -> bool:
    if not _zone_snapshots.has(
        zone_key
    ):
        return false

    _zone_snapshots.erase(
        zone_key
    )
    last_error = ""
    return true


func clear() -> void:
    _zone_snapshots.clear()
    last_error = ""


func zone_keys() -> Array[String]:
    var result: Array[String] = []

    for zone_key_variant in _zone_snapshots:
        result.append(
            str(
                zone_key_variant
            )
        )

    result.sort()
    return result


func snapshot() -> Dictionary:
    return {
        "schema_version":
            SCHEMA_VERSION,
        "zones":
            _zone_snapshots.duplicate(true),
    }


func restore(
    snapshot_value: Variant
) -> bool:
    if not snapshot_value is Dictionary:
        return _fail(
            "Zone-state store snapshot must be a dictionary"
        )

    var snapshot: Dictionary = (
        snapshot_value as Dictionary
    )

    if int(
        snapshot.get(
            "schema_version",
            0
        )
    ) != SCHEMA_VERSION:
        return _fail(
            "Unsupported zone-state store schema version"
        )

    var zones_variant: Variant = (
        snapshot.get(
            "zones",
            {}
        )
    )

    if not zones_variant is Dictionary:
        return _fail(
            "Zone-state store zones payload must be a dictionary"
        )

    var candidate_snapshots: Dictionary = {}

    for zone_key_variant in (
        zones_variant as Dictionary
    ):
        var zone_key := str(
            zone_key_variant
        )
        var zone_snapshot_variant: Variant = (
            (zones_variant as Dictionary)[
                zone_key_variant
            ]
        )

        if not zone_snapshot_variant is Dictionary:
            return _fail(
                "Stored zone %s does not contain a dictionary snapshot"
                % zone_key
            )

        var zone_snapshot: Dictionary = (
            zone_snapshot_variant
            as Dictionary
        )

        if not _snapshot_matches_zone(
            zone_key,
            zone_snapshot
        ):
            return false

        # Validate through the canonical ZoneRuntimeState parser so the
        # store never accepts a shape that the runtime itself cannot load.
        var probe := ZoneRuntimeState.new()

        if not probe.restore(
            zone_snapshot,
            zone_key
        ):
            return _fail(
                "Stored zone %s is invalid: %s"
                % [
                    zone_key,
                    probe.last_error,
                ]
            )

        candidate_snapshots[
            zone_key
        ] = zone_snapshot.duplicate(true)

    # Replace only after the complete payload validates. A malformed zone
    # therefore cannot partially overwrite an already-valid state store.
    _zone_snapshots = candidate_snapshots
    last_error = ""
    return true


func _snapshot_matches_zone(
    zone_key: String,
    snapshot: Dictionary
) -> bool:
    if zone_key.is_empty():
        return _fail(
            "Stored zone key cannot be empty"
        )

    if str(
        snapshot.get(
            "zone_key",
            ""
        )
    ) != zone_key:
        return _fail(
            "Stored zone snapshot key does not match %s"
            % zone_key
        )

    if int(
        snapshot.get(
            "schema_version",
            0
        )
    ) != ZoneRuntimeState.SCHEMA_VERSION:
        return _fail(
            "Stored zone %s has an unsupported runtime-state schema"
            % zone_key
        )

    return true


func _fail(
    message: String
) -> bool:
    last_error = message
    return false
