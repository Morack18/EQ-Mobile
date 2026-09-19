class_name ZoneTransitionRequest
extends RefCounted

var source_zone_key := ""
var target_zone_key := ""
var target_entry_ref := ""
var target_position: Variant = null
var target_heading_eq := -1.0
var reason := "world_transition"


func configure(
    values: Dictionary
) -> void:
    source_zone_key = str(
        values.get(
            "source_zone_key",
            ""
        )
    )
    target_zone_key = str(
        values.get(
            "target_zone_key",
            ""
        )
    )
    target_entry_ref = str(
        values.get(
            "target_entry_ref",
            ""
        )
    )
    target_heading_eq = float(
        values.get(
            "target_heading_eq",
            -1.0
        )
    )
    reason = str(
        values.get(
            "reason",
            "world_transition"
        )
    )

    var position_variant: Variant = values.get(
        "target_position",
        null
    )

    if position_variant is Vector3:
        target_position = position_variant
    elif (
        position_variant is Array
        and position_variant.size() == 3
    ):
        target_position = Vector3(
            float(position_variant[0]),
            float(position_variant[1]),
            float(position_variant[2])
        )
    else:
        target_position = null


func is_valid() -> bool:
    if not source_zone_key.begins_with(
        "eqm:zone:"
    ):
        return false

    if not target_zone_key.begins_with(
        "eqm:zone:"
    ):
        return false

    return (
        not target_entry_ref.is_empty()
        or target_position is Vector3
    )


func to_dict() -> Dictionary:
    var result := {
        "source_zone_key":
            source_zone_key,
        "target_zone_key":
            target_zone_key,
        "target_entry_ref":
            target_entry_ref,
        "target_heading_eq":
            target_heading_eq,
        "reason":
            reason,
    }

    if target_position is Vector3:
        var position: Vector3 = target_position

        result[
            "target_position"
        ] = [
            position.x,
            position.y,
            position.z,
        ]

    return result


static func from_dict(
    payload: Dictionary
) -> ZoneTransitionRequest:
    var request := ZoneTransitionRequest.new()
    request.configure(
        payload
    )
    return request
