class_name ZoneWorldSpace
extends RefCounted

var definition: Dictionary = {}
var contract: Dictionary = {}
var last_error := ""
var _object_transform_enabled := false


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

    var object_instances := str(
        definition.get(
            "object_instances",
            ""
        )
    )
    var object_model_directory := str(
        definition.get(
            "object_model_directory",
            ""
        )
    )

    if (
        object_instances.is_empty()
        != object_model_directory.is_empty()
    ):
        return _fail(
            "Zone static-object placement and model directory must be declared together"
        )

    _object_transform_enabled = (
        not object_instances.is_empty()
    )

    if _object_transform_enabled:
        if not _axis_map_is_valid(
            contract.get(
                "lantern_prop_axis_map",
                []
            )
        ):
            return _fail(
                "Zone object axis map is invalid"
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


func has_object_transform() -> bool:
    return (
        is_valid()
        and _object_transform_enabled
    )


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
    return EqWorldSpace.horizontal_direction_to_yaw(
        server_heading_direction(
            heading_eq
        )
    )


func server_heading_direction(
    heading_eq: float
) -> Vector3:
    assert(
        is_valid(),
        last_error
    )
    var source_direction := EqWorldSpace.server_heading_source_vector(
        heading_eq,
        float(
            contract.get(
                "server_heading_units_per_turn",
                EqWorldSpace.EQ_HEADING_UNITS_PER_TURN
            )
        )
    )
    var mapped := server_position([
        source_direction.x,
        source_direction.y,
        source_direction.z,
    ])
    assert(
        absf(mapped.y) <= 0.000001,
        "Server heading axis map must preserve a horizontal world direction"
    )
    return mapped.normalized()


func object_position(
    source: Array
) -> Vector3:
    assert(
        is_valid(),
        last_error
    )
    assert(
        has_object_transform(),
        "Zone has no static-object coordinate transform"
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
    assert(
        has_object_transform(),
        "Zone has no static-object coordinate transform"
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


func object_rotation_basis(
    source_degrees: Array
) -> Basis:
    assert(
        is_valid(),
        last_error
    )
    assert(
        has_object_transform(),
        "Zone has no static-object coordinate transform"
    )
    assert(
        source_degrees.size() == 3,
        "Object rotation requires [RotX, RotY, RotZ]"
    )

    # Lantern writes object rotations as RotX, RotY, RotZ and applies them
    # through Matrix4x4.CreateFromYawPitchRoll(
    #     yaw=RotY,
    #     pitch=RotX,
    #     roll=RotZ
    # ).
    #
    # Godot uses the same positive right-handed rotation sense around these
    # local axes. Composition is Y * X * Z.
    var source_basis := (
        Basis(
            Vector3.UP,
            deg_to_rad(
                float(
                    source_degrees[1]
                )
            )
        )
        * Basis(
            Vector3.RIGHT,
            deg_to_rad(
                float(
                    source_degrees[0]
                )
            )
        )
        * Basis(
            Vector3.BACK,
            deg_to_rad(
                float(
                    source_degrees[2]
                )
            )
        )
    )

    var coordinate_basis := (
        _axis_map_basis(
            _axis_map(
                "lantern_prop_axis_map"
            )
        )
    )

    # Change the complete rotation from Lantern placement coordinates into
    # this zone's Godot coordinate frame. This remains valid for a reflected
    # frame such as Halas' X mirror.
    return (
        coordinate_basis
        * source_basis
        * coordinate_basis.inverse()
    )


func _axis_map_basis(
    axis_map: Array
) -> Basis:
    return Basis(
        EqWorldSpace.map_position(
            [
                1.0,
                0.0,
                0.0,
            ],
            axis_map
        ),
        EqWorldSpace.map_position(
            [
                0.0,
                1.0,
                0.0,
            ],
            axis_map
        ),
        EqWorldSpace.map_position(
            [
                0.0,
                0.0,
                1.0,
            ],
            axis_map
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
