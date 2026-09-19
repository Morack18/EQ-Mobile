class_name ZoneWorldSpace
extends RefCounted

var definition: Dictionary = {}
var contract: Dictionary = {}
var last_error := ""


func _init(
    zone_definition: Dictionary = {}
) -> void:
    configure(
        zone_definition
    )


func configure(
    zone_definition: Dictionary
) -> bool:
    definition = zone_definition.duplicate(
        true
    )

    var contract_variant: Variant = (
        definition.get(
            "world_space_contract",
            {}
        )
    )

    if not contract_variant is Dictionary:
        return _fail(
            "Zone definition has no world-space contract"
        )

    contract = (
        contract_variant as Dictionary
    ).duplicate(true)

    if not _axis_map_is_valid(
        contract.get(
            "server_axis_map",
            []
        )
    ):
        return _fail(
            "Zone server axis map is invalid"
        )

    if not _axis_map_is_valid(
        contract.get(
            "lantern_prop_axis_map",
            []
        )
    ):
        return _fail(
            "Zone object axis map is invalid"
        )

    var heading_units := float(
        contract.get(
            "server_heading_units_per_turn",
            0.0
        )
    )

    if heading_units <= 0.0:
        return _fail(
            "Zone server heading units per turn must be positive"
        )

    var prop_heading_sign := float(
        contract.get(
            "lantern_prop_heading_degrees_sign",
            0.0
        )
    )

    if is_zero_approx(
        prop_heading_sign
    ):
        return _fail(
            "Zone object heading sign must be non-zero"
        )

    last_error = ""
    return true


func is_valid() -> bool:
    return last_error.is_empty()


func server_position(
    source: Array
) -> Vector3:
    assert(
        is_valid(),
        last_error
    )

    return EqWorldSpace.map_position(
        source,
        _axis_map(
            "server_axis_map"
        )
    )


func server_heading_yaw(
    heading_eq: float
) -> float:
    assert(
        is_valid(),
        last_error
    )

    return EqWorldSpace.heading_to_godot_yaw(
        heading_eq,
        float(
            contract.get(
                "server_heading_units_per_turn",
                EqWorldSpace.EQ_HEADING_UNITS_PER_TURN
            )
        )
    )


func object_position(
    source: Array
) -> Vector3:
    assert(
        is_valid(),
        last_error
    )

    return EqWorldSpace.map_position(
        source,
        _axis_map(
            "lantern_prop_axis_map"
        )
    )


func object_heading_yaw(
    degrees_source: float
) -> float:
    assert(
        is_valid(),
        last_error
    )

    return deg_to_rad(
        degrees_source
        * float(
            contract.get(
                "lantern_prop_heading_degrees_sign",
                -1.0
            )
        )
    )


func _axis_map(
    key: String
) -> Array:
    var value: Variant = contract.get(
        key,
        []
    )

    assert(
        value is Array,
        "World-space axis map %s is not an array"
        % key
    )

    return (
        value as Array
    ).duplicate()


func _axis_map_is_valid(
    value: Variant
) -> bool:
    if not value is Array:
        return false

    var axis_map: Array = value

    if axis_map.size() != 3:
        return false

    var used: Dictionary = {}

    for component_variant in axis_map:
        var component := int(
            component_variant
        )
        var absolute_component := absi(
            component
        )

        if (
            component == 0
            or absolute_component > 3
            or used.has(
                absolute_component
            )
        ):
            return false

        used[
            absolute_component
        ] = true

    return used.size() == 3


func _fail(
    message: String
) -> bool:
    last_error = message
    return false
