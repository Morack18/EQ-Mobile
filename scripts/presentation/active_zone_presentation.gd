class_name ActiveZonePresentation
extends Node3D

var zone_key := ""


func _init(
    zone_key_value: String = ""
) -> void:
    name = "ActiveZonePresentation"

    if not zone_key_value.is_empty():
        configure(
            zone_key_value
        )


func configure(
    zone_key_value: String
) -> bool:
    if (
        zone_key_value.is_empty()
        or not zone_key_value.begins_with(
            "eqm:zone:"
        )
    ):
        return false

    zone_key = zone_key_value
    set_meta(
        "zone_key",
        zone_key
    )
    return true
