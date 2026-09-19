class_name ZoneDefinitionLoader
extends RefCounted

const DEFAULT_CATALOG_PATH := "res://data/zones/index.json"
const CATALOG_SCHEMA_ID := "eqm.zone_catalog"
const ZONE_SCHEMA_ID := "eqm.zone_definition"
const SUPPORTED_CATALOG_SCHEMA_VERSION := 1

var catalog_path := DEFAULT_CATALOG_PATH
var last_error := ""

var _catalog: Dictionary = {}


func _init(
    catalog_path_value: String = DEFAULT_CATALOG_PATH
) -> void:
    catalog_path = catalog_path_value


func load_catalog() -> bool:
    var document_variant: Variant = _read_json(
        catalog_path
    )

    if not document_variant is Dictionary:
        return false

    var document: Dictionary = document_variant
    var validation_error := validate_catalog(
        document
    )

    if not validation_error.is_empty():
        return _fail(
            validation_error
        )

    _catalog = document.duplicate(true)
    last_error = ""
    return true


func default_zone_key() -> String:
    return str(
        _catalog.get(
            "default_zone_key",
            ""
        )
    )


func zone_keys() -> Array[String]:
    var result: Array[String] = []

    var zones_variant: Variant = _catalog.get(
        "zones",
        {}
    )

    if not zones_variant is Dictionary:
        return result

    var zones: Dictionary = zones_variant

    for zone_key_variant in zones:
        result.append(
            str(zone_key_variant)
        )

    result.sort()
    return result


func zone_definition_path(
    zone_key: String = ""
) -> String:
    if _catalog.is_empty():
        if not load_catalog():
            return ""

    var resolved_key := zone_key

    if resolved_key.is_empty():
        resolved_key = default_zone_key()

    var zones_variant: Variant = _catalog.get(
        "zones",
        {}
    )

    if not zones_variant is Dictionary:
        _fail(
            "Zone catalog has no zones dictionary"
        )
        return ""

    var zones: Dictionary = zones_variant
    var entry_variant: Variant = zones.get(
        resolved_key,
        null
    )

    if not entry_variant is Dictionary:
        _fail(
            "Unknown zone key: %s"
            % resolved_key
        )
        return ""

    var entry: Dictionary = entry_variant
    var definition_path := str(
        entry.get(
            "definition",
            ""
        )
    )

    if definition_path.is_empty():
        _fail(
            "Zone catalog entry %s has no definition path"
            % resolved_key
        )
        return ""

    return definition_path


func load_zone(
    zone_key: String = ""
) -> Dictionary:
    if _catalog.is_empty():
        if not load_catalog():
            return {}

    var resolved_key := zone_key

    if resolved_key.is_empty():
        resolved_key = default_zone_key()

    var zones_variant: Variant = _catalog.get(
        "zones",
        {}
    )

    if not zones_variant is Dictionary:
        _fail(
            "Zone catalog has no zones dictionary"
        )
        return {}

    var zones: Dictionary = zones_variant
    var entry_variant: Variant = zones.get(
        resolved_key,
        null
    )

    if not entry_variant is Dictionary:
        _fail(
            "Unknown zone key: %s"
            % resolved_key
        )
        return {}

    var entry: Dictionary = entry_variant
    var definition_path := str(
        entry.get(
            "definition",
            ""
        )
    )

    if definition_path.is_empty():
        _fail(
            "Zone catalog entry %s has no definition path"
            % resolved_key
        )
        return {}

    var definition_variant: Variant = _read_json(
        definition_path
    )

    if not definition_variant is Dictionary:
        return {}

    var definition: Dictionary = definition_variant
    var validation_error := validate_definition(
        definition,
        resolved_key
    )

    if not validation_error.is_empty():
        _fail(
            validation_error
        )
        return {}

    last_error = ""
    return definition.duplicate(true)


func runtime_content_paths(
    definition: Dictionary
) -> Dictionary:
    var result: Dictionary = {}

    var refs_variant: Variant = definition.get(
        "content_refs",
        {}
    )

    if refs_variant is Dictionary:
        var refs: Dictionary = refs_variant

        _copy_content_ref(
            refs,
            result,
            "npc_population",
            "npcs"
        )
        _copy_content_ref(
            refs,
            result,
            "merchant_catalog",
            "merchants"
        )
        _copy_content_ref(
            refs,
            result,
            "faction_catalog",
            "factions"
        )
        _copy_content_ref(
            refs,
            result,
            "item_catalog",
            "peq_items"
        )
        _copy_content_ref(
            refs,
            result,
            "world_objects",
            "world_objects"
        )
        _copy_content_ref(
            refs,
            result,
            "transitions",
            "transitions"
        )

    # Transitional compatibility with the existing Phase 1-5 Halas schema.
    if (
        not result.has("npcs")
        and not str(
            definition.get(
                "npc_source",
                ""
            )
        ).is_empty()
    ):
        result["npcs"] = str(
            definition.get(
                "npc_source",
                ""
            )
        )

    return result


func validate_catalog(
    document: Dictionary
) -> String:
    if (
        str(document.get("schema_id", ""))
        != CATALOG_SCHEMA_ID
    ):
        return (
            "Zone catalog schema_id must be %s"
            % CATALOG_SCHEMA_ID
        )

    if (
        int(
            document.get(
                "schema_version",
                0
            )
        )
        != SUPPORTED_CATALOG_SCHEMA_VERSION
    ):
        return (
            "Unsupported zone catalog schema version"
        )

    var zones_variant: Variant = document.get(
        "zones",
        {}
    )

    if (
        not zones_variant is Dictionary
        or zones_variant.is_empty()
    ):
        return (
            "Zone catalog requires at least one zone"
        )

    var zones: Dictionary = zones_variant
    var default_key := str(
        document.get(
            "default_zone_key",
            ""
        )
    )

    if (
        default_key.is_empty()
        or not zones.has(default_key)
    ):
        return (
            "Zone catalog default_zone_key is missing or unresolved"
        )

    for zone_key_variant in zones:
        var zone_key := str(
            zone_key_variant
        )

        if not zone_key.begins_with(
            "eqm:zone:"
        ):
            return (
                "Malformed zone key in catalog: %s"
                % zone_key
            )

        var entry_variant: Variant = zones[
            zone_key_variant
        ]

        if not entry_variant is Dictionary:
            return (
                "Zone catalog entry %s must be an object"
                % zone_key
            )

        var entry: Dictionary = entry_variant

        if str(
            entry.get(
                "definition",
                ""
            )
        ).is_empty():
            return (
                "Zone catalog entry %s has no definition path"
                % zone_key
            )

    return ""


func validate_definition(
    definition: Dictionary,
    expected_key: String = ""
) -> String:
    if (
        str(definition.get("schema_id", ""))
        != ZONE_SCHEMA_ID
    ):
        return (
            "Zone definition schema_id must be %s"
            % ZONE_SCHEMA_ID
        )

    if (
        int(
            definition.get(
                "schema_version",
                0
            )
        )
        <= 0
    ):
        return (
            "Zone definition schema_version must be positive"
        )

    var zone_key := str(
        definition.get(
            "key",
            ""
        )
    )

    if not zone_key.begins_with(
        "eqm:zone:"
    ):
        return (
            "Zone definition has malformed key: %s"
            % zone_key
        )

    if (
        not expected_key.is_empty()
        and zone_key != expected_key
    ):
        return (
            "Loaded zone key %s does not match catalog key %s"
            % [
                zone_key,
                expected_key,
            ]
        )

    if str(
        definition.get(
            "id",
            ""
        )
    ).is_empty():
        return (
            "Zone definition id is missing"
        )

    if str(
        definition.get(
            "geometry_scene",
            ""
        )
    ).is_empty():
        return (
            "Zone definition geometry_scene is missing"
        )

    var world_contract_variant: Variant = (
        definition.get(
            "world_space_contract",
            {}
        )
    )

    if not world_contract_variant is Dictionary:
        return (
            "Zone definition world_space_contract is missing"
        )

    var world_contract: Dictionary = (
        world_contract_variant
    )

    if not _valid_axis_map(
        world_contract.get(
            "server_axis_map",
            []
        )
    ):
        return (
            "Zone server_axis_map must be a signed permutation of 1, 2, 3"
        )

    if not _valid_axis_map(
        world_contract.get(
            "lantern_prop_axis_map",
            []
        )
    ):
        return (
            "Zone lantern_prop_axis_map must be a signed permutation of 1, 2, 3"
        )

    var bounds_variant: Variant = definition.get(
        "bounds",
        {}
    )

    if not bounds_variant is Dictionary:
        return (
            "Zone definition bounds are missing"
        )

    if not _valid_bounds(
        bounds_variant
    ):
        return (
            "Zone bounds require positive half_extent or min/max Vector3 arrays"
        )

    var safe_point_variant: Variant = (
        definition.get(
            "safe_point",
            {}
        )
    )

    var has_safe_point := false

    if safe_point_variant is Dictionary:
        has_safe_point = _valid_vector3_array(
            safe_point_variant.get(
                "position",
                []
            )
        )

    if (
        not has_safe_point
        and not _valid_vector3_array(
            definition.get(
                "player_spawn",
                []
            )
        )
    ):
        return (
            "Zone definition requires a player safe point"
        )

    var refs_variant: Variant = definition.get(
        "content_refs",
        {}
    )

    if not refs_variant is Dictionary:
        return (
            "Zone definition content_refs are missing"
        )

    var refs: Dictionary = refs_variant

    for required_ref in [
        "npc_population",
        "world_objects",
        "transitions",
    ]:
        if str(
            refs.get(
                required_ref,
                ""
            )
        ).is_empty():
            return (
                "Zone content ref is missing: %s"
                % required_ref
            )

    if not definition.get(
        "environment",
        {}
    ) is Dictionary:
        return (
            "Zone definition environment settings are missing"
        )

    return ""


func _copy_content_ref(
    refs: Dictionary,
    destination: Dictionary,
    source_key: String,
    destination_key: String
) -> void:
    var path := str(
        refs.get(
            source_key,
            ""
        )
    )

    if not path.is_empty():
        destination[
            destination_key
        ] = path


func _valid_axis_map(
    value: Variant
) -> bool:
    if (
        not value is Array
        or value.size() != 3
    ):
        return false

    var used: Dictionary = {}

    for component_variant in value:
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


func _valid_bounds(
    bounds: Dictionary
) -> bool:
    if bounds.has(
        "half_extent"
    ):
        return float(
            bounds.get(
                "half_extent",
                0.0
            )
        ) > 0.0

    return (
        _valid_vector3_array(
            bounds.get(
                "min",
                []
            )
        )
        and _valid_vector3_array(
            bounds.get(
                "max",
                []
            )
        )
    )


func _valid_vector3_array(
    value: Variant
) -> bool:
    return (
        value is Array
        and value.size() == 3
    )


func _read_json(
    path: String
) -> Variant:
    var file := FileAccess.open(
        path,
        FileAccess.READ
    )

    if file == null:
        _fail(
            "Unable to read zone content: %s"
            % path
        )
        return null

    var parsed: Variant = JSON.parse_string(
        file.get_as_text()
    )

    file.close()

    if not parsed is Dictionary:
        _fail(
            "Zone content is not a JSON object: %s"
            % path
        )
        return null

    return parsed


func _fail(
    message: String
) -> bool:
    last_error = message
    push_error(message)
    return false
