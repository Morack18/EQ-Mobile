class_name ZonePresentationHost
extends Node3D

var active_zone_root: ActiveZonePresentation


func begin_zone(
    zone_key: String
) -> ActiveZonePresentation:
    if (
        zone_key.is_empty()
        or not zone_key.begins_with(
            "eqm:zone:"
        )
    ):
        return null

    if (
        active_zone_root != null
        and is_instance_valid(
            active_zone_root
        )
    ):
        if (
            active_zone_root.zone_key
            == zone_key
        ):
            return active_zone_root

        clear_zone()

    active_zone_root = (
        ActiveZonePresentation.new(
            zone_key
        )
    )

    if (
        active_zone_root.zone_key
        != zone_key
    ):
        active_zone_root = null
        return null

    add_child(
        active_zone_root
    )

    return active_zone_root


func clear_zone() -> void:
    if (
        active_zone_root == null
        or not is_instance_valid(
            active_zone_root
        )
    ):
        active_zone_root = null
        return

    if (
        active_zone_root.get_parent()
        == self
    ):
        remove_child(
            active_zone_root
        )

    active_zone_root.queue_free()
    active_zone_root = null


func has_active_zone() -> bool:
    return (
        active_zone_root != null
        and is_instance_valid(
            active_zone_root
        )
    )
