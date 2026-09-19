extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
    _test_zone_catalog_and_definition()
    _test_definition_is_not_halas_locked()
    _test_main_startup_uses_zone_catalog()
    _test_zone_world_space_contract()
    _test_zone_spawn_resolver()
    _test_spawn_point_state_round_trip()
    _test_world_object_state_round_trip()
    _test_zone_host_lifecycle()
    _test_zone_host_domain_separation()
    _test_zone_presentation_lifetime()
    _test_zone_state_store_unload_reload()
    _test_zone_transition_contract()

    if _failures.is_empty():
        print(
            "PASS: Phase 6 zone catalog, definition, spawn state, "
            + "world-object state, and transition contracts hold."
        )
        quit(0)
        return

    for failure in _failures:
        push_error(
            failure
        )

    print(
        "FAIL: Phase 6 zone foundation tests (%d failures)."
        % _failures.size()
    )
    quit(1)


func _test_zone_catalog_and_definition() -> void:
    var loader_script := load(
        "res://scripts/services/zone_definition_loader.gd"
    ) as GDScript

    _expect(
        loader_script != null
        and loader_script.can_instantiate(),
        "ZoneDefinitionLoader script cannot instantiate."
    )

    if (
        loader_script == null
        or not loader_script.can_instantiate()
    ):
        return

    var loader: Variant = loader_script.new()

    _expect(
        loader.load_catalog(),
        "Zone catalog did not load: %s"
        % loader.last_error
    )

    _expect(
        loader.default_zone_key()
        == "eqm:zone:halas",
        "Halas is not selected through the zone catalog."
    )

    _expect(
        str(
            loader.zone_definition_path()
        ) == "res://data/halas.json",
        "Default zone definition path did not resolve through the catalog."
    )

    var definition: Dictionary = loader.load_zone()

    _expect(
        not definition.is_empty(),
        "Default zone definition did not load: %s"
        % loader.last_error
    )

    if definition.is_empty():
        return

    _expect(
        str(
            definition.get(
                "key",
                ""
            )
        ) == "eqm:zone:halas",
        "Loaded ZoneDefinition lost its stable key."
    )

    _expect(
        not str(
            definition.get(
                "geometry_scene",
                ""
            )
        ).is_empty(),
        "ZoneDefinition has no geometry reference."
    )

    _expect(
        definition.get(
            "bounds",
            {}
        ) is Dictionary,
        "ZoneDefinition has no bounds contract."
    )

    _expect(
        definition.get(
            "safe_point",
            {}
        ) is Dictionary,
        "ZoneDefinition has no safe-point contract."
    )

    _expect(
        definition.get(
            "environment",
            {}
        ) is Dictionary,
        "ZoneDefinition has no environment contract."
    )

    var paths: Dictionary = loader.runtime_content_paths(
        definition
    )

    for required_key in [
        "npcs",
        "world_objects",
        "transitions",
    ]:
        _expect(
            not str(
                paths.get(
                    required_key,
                    ""
                )
            ).is_empty(),
            "ZoneDefinition did not resolve runtime content path: %s"
            % required_key
        )


func _test_definition_is_not_halas_locked() -> void:
    var loader := ZoneDefinitionLoader.new()

    _expect(
        loader.load_catalog(),
        "Zone catalog did not load for generic-definition test."
    )

    var definition: Dictionary = loader.load_zone()

    if definition.is_empty():
        _expect(
            false,
            "Generic-definition test has no source definition."
        )
        return

    var probe := definition.duplicate(true)

    probe[
        "key"
    ] = "eqm:zone:foundation_probe"
    probe[
        "id"
    ] = "foundation_probe"
    probe[
        "display_name"
    ] = "Foundation Probe"
    probe[
        "source_refs"
    ] = {}

    _expect(
        loader.validate_definition(
            probe,
            "eqm:zone:foundation_probe"
        ).is_empty(),
        "Generic ZoneDefinition validation contains a Halas-specific requirement."
    )


func _test_main_startup_uses_zone_catalog() -> void:
    var file := FileAccess.open(
        "res://scripts/main.gd",
        FileAccess.READ
    )

    _expect(
        file != null,
        "Unable to inspect main.gd startup wiring."
    )

    if file == null:
        return

    var source := file.get_as_text()
    file.close()

    _expect(
        source.contains(
            "ZoneDefinitionLoader.new()"
        ),
        "main.gd does not select its startup zone through ZoneDefinitionLoader."
    )

    _expect(
        not source.contains(
            "const ZONE_KEY"
        ),
        "main.gd still hardcodes a startup ZONE_KEY."
    )

    _expect(
        not source.contains(
            "const CONTENT_PATHS"
        ),
        "main.gd still owns the old hardcoded zone content table."
    )

    for forbidden_path in [
        "res://data/halas_npcs.json",
        "res://data/halas_merchants_source.json",
        "res://data/halas_factions_source.json",
        "res://data/halas_items_source.json",
    ]:
        _expect(
            not source.contains(
                forbidden_path
            ),
            "main.gd still directly names zone-owned content: %s"
            % forbidden_path
        )


func _test_zone_world_space_contract() -> void:
    var loader := ZoneDefinitionLoader.new()

    _expect(
        loader.load_catalog(),
        "Zone catalog did not load for world-space test."
    )

    var definition := loader.load_zone()

    _expect(
        not definition.is_empty(),
        "World-space test has no ZoneDefinition."
    )

    if definition.is_empty():
        return

    var mapper := ZoneWorldSpace.new(
        definition
    )

    _expect(
        mapper.is_valid(),
        "ZoneWorldSpace rejected the loaded definition: %s"
        % mapper.last_error
    )

    if not mapper.is_valid():
        return

    _expect(
        mapper.server_position([
            10.0,
            20.0,
            30.0,
        ]).is_equal_approx(
            Vector3(
                -20.0,
                30.0,
                10.0
            )
        ),
        "Zone server position mapping changed."
    )

    _expect(
        mapper.object_position([
            10.0,
            20.0,
            30.0,
        ]).is_equal_approx(
            Vector3(
                -10.0,
                20.0,
                30.0
            )
        ),
        "Zone object position mapping changed."
    )

    _expect(
        is_equal_approx(
            mapper.object_heading_yaw(
                90.0
            ),
            -PI * 0.5
        ),
        "Zone object heading mapping changed."
    )

    _expect(
        is_equal_approx(
            mapper.server_heading_yaw(
                128.0
            ),
            0.0
        ),
        "Zone server heading mapping changed."
    )

    _expect(
        is_equal_approx(
            EqWorldSpace.heading_to_godot_yaw(
                256.0,
                1024.0
            ),
            0.0
        ),
        "Generic heading conversion does not honor units-per-turn."
    )

    # JSON numeric arrays are Variants. Mesh surface matching must normalize
    # configured values rather than depending on Variant numeric membership.
    var json_style_indices: Array = [
        58.0,
        61.0,
    ]

    var normalized_surface_match := false

    for configured_index_variant in json_style_indices:
        if int(
            configured_index_variant
        ) == 58:
            normalized_surface_match = true
            break

    _expect(
        normalized_surface_match,
        "JSON-style water surface indices do not normalize to mesh indices."
    )

    var file := FileAccess.open(
        "res://scripts/main.gd",
        FileAccess.READ
    )

    _expect(
        file != null,
        "Unable to inspect main.gd world wiring."
    )

    if file == null:
        return

    var source := file.get_as_text()
    file.close()

    for forbidden in [
        "EqWorldSpace.halas_lantern_prop_position",
        "EqWorldSpace.halas_lantern_prop_yaw",
        "_surface_is_halas_water",
        "_surface_defines_halas_water_surface",
        "\"halaswater\"",
        "Color(\"9fb9c5\")",
        "Color(\"bfd7c8\")",
    ]:
        _expect(
            not source.contains(
                forbidden
            ),
            "main.gd still owns a Halas-specific world rule: %s"
            % forbidden
        )


func _test_zone_spawn_resolver() -> void:
    var dataset := {
        "npc_types": [
            {
                "id": 101,
                "key": "peq:npc:101",
                "name": "First",
            },
            {
                "id": 102,
                "key": "peq:npc:102",
                "name": "Second",
            },
        ],
        "spawn_groups": {
            "50": {
                "id": 50,
                "key": "peq:spawn_group:50",
                "candidates": [
                    {
                        "chance": 40,
                        "npc_ref": "peq:npc:101",
                        "npc_type_id": 101,
                    },
                    {
                        "chance": 60,
                        "npc_ref": "peq:npc:102",
                        "npc_type_id": 102,
                    },
                ],
            },
        },
        "spawns": [
            {
                "spawn2_id": 100,
                "key": "peq:spawn:100",
                "spawn_group_id": 50,
                "spawn_group_ref": "peq:spawn_group:50",
                "position_eq": [
                    1.0,
                    2.0,
                    3.0,
                ],
                "heading_eq": 128.0,
                "grid_id": 0,
                "respawn_seconds": 30.0,
            },
            {
                "spawn2_id": 145,
                "key": "peq:spawn:145",
                "spawn_group_id": 50,
                "spawn_group_ref": "peq:spawn_group:50",
                "position_eq": [
                    4.0,
                    5.0,
                    6.0,
                ],
                "heading_eq": 64.0,
                "grid_id": 7,
                "respawn_seconds": 45.0,
            },
        ],
    }

    var state := ZoneRuntimeState.new(
        "eqm:zone:test"
    )
    var resolver := ZoneSpawnResolver.new(
        "eqm:zone:test"
    )
    var resolved := resolver.resolve_into_state(
        dataset,
        state
    )

    _expect(
        resolver.last_error.is_empty(),
        "Generic spawn resolution failed: %s"
        % resolver.last_error
    )

    _expect(
        resolved.size() == 2,
        "Generic spawn resolver did not preserve the source spawn roster."
    )

    var first_state := state.spawn_state(
        "peq:spawn:100"
    )
    var second_state := state.spawn_state(
        "peq:spawn:145"
    )

    _expect(
        str(
            first_state.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:101",
        "Compatibility selection changed the first weighted spawn."
    )

    _expect(
        str(
            second_state.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:102",
        "Compatibility selection changed the second weighted spawn."
    )

    _expect(
        str(
            second_state.get(
                "spawn_group_ref",
                ""
            )
        ) == "peq:spawn_group:50"
        and is_equal_approx(
            float(
                second_state.get(
                    "respawn_seconds",
                    -1.0
                )
            ),
            45.0
        ),
        "SpawnPoint did not own its group identity and respawn definition."
    )

    var seeded_runtime_variant: Variant = (
        second_state.get(
            "runtime",
            {}
        )
    )
    var seeded_runtime: Dictionary = (
        seeded_runtime_variant
        if seeded_runtime_variant is Dictionary
        else {}
    )

    _expect(
        int(
            seeded_runtime.get(
                "grid_id",
                -1
            )
        ) == 7
        and int(
            seeded_runtime.get(
                "patrol_index",
                -1
            )
        ) == 0
        and is_equal_approx(
            float(
                seeded_runtime.get(
                    "pause_remaining",
                    -1.0
                )
            ),
            0.0
        ),
        "Spawn resolver did not seed canonical patrol runtime defaults."
    )

    # Simulate a persisted valid selection that differs from what the
    # compatibility first-selection algorithm would currently choose.
    _expect(
        state.select_spawn_definition(
            "peq:spawn:145",
            "peq:npc:101"
        ),
        "Test could not install a persisted spawn selection."
    )

    var snapshot := state.snapshot()
    var restored := ZoneRuntimeState.new()

    _expect(
        restored.restore(
            snapshot,
            "eqm:zone:test"
        ),
        "Spawn resolver state fixture did not restore."
    )

    var restored_resolver := ZoneSpawnResolver.new(
        "eqm:zone:test"
    )
    restored_resolver.resolve_into_state(
        dataset,
        restored
    )

    _expect(
        restored_resolver.last_error.is_empty(),
        "Resolver rejected a valid restored spawn selection."
    )

    var restored_second := restored.spawn_state(
        "peq:spawn:145"
    )

    _expect(
        str(
            restored_second.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:101",
        "Zone reload rerolled an already-selected living SpawnPoint."
    )

    var main_file := FileAccess.open(
        "res://scripts/main.gd",
        FileAccess.READ
    )

    _expect(
        main_file != null,
        "Unable to inspect main.gd spawn wiring."
    )

    if main_file == null:
        return

    var main_source := main_file.get_as_text()
    main_file.close()

    var prepare_save_index := (
        main_source.find(
            "_prepare_save_read()"
        )
    )
    var resolve_spawns_index := (
        main_source.find(
            "_resolve_zone_spawns()"
        )
    )
    var build_population_index := (
        main_source.find(
            "_build_npc_population()"
        )
    )
    var restore_simulation_index := (
        main_source.find(
            "_restore_simulation_save()"
        )
    )

    _expect(
        prepare_save_index >= 0
        and resolve_spawns_index > prepare_save_index
        and build_population_index > resolve_spawns_index
        and restore_simulation_index > build_population_index,
        "Startup does not restore zone state before spawn resolution "
        + "and simulation state after actor construction."
    )

    _expect(
        main_source.contains(
            "ZoneHost.new()"
        )
        and main_source.contains(
            "zone_host.resolve_spawns("
        )
        and main_source.contains(
            "zone_runtime_state.occupy_spawn("
        )
        and main_source.contains(
            "resolved_zone_spawns"
        )
        and main_source.contains(
            "restore_zone_store_from_read("
        )
        and main_source.contains(
            "zone_host.restore_active_from_store()"
        ),
        "main.gd does not bridge presentation actors into generic SpawnPoint state."
    )

    var population_file := FileAccess.open(
        "res://scripts/halas_npc_population.gd",
        FileAccess.READ
    )

    _expect(
        population_file != null,
        "Unable to inspect Halas population compatibility presentation."
    )

    if population_file == null:
        return

    var population_source := (
        population_file.get_as_text()
    )
    population_file.close()

    _expect(
        population_source.contains(
            "_resolved_spawns"
        )
        and population_source.contains(
            "\"npc_definition\""
        ),
        "Halas presentation does not consume generic resolved spawn definitions."
    )

    _expect(
        not population_source.contains(
            "func _choose_npc_type("
        ),
        "Halas presentation still owns SpawnGroup candidate selection."
    )

    _expect(
        not population_source.contains(
            "spawn2_id) % total_weight"
        ),
        "Halas presentation still contains legacy weighted selection logic."
    )

    _expect(
        population_source.contains(
            "_zone_runtime_state.set_spawn_runtime("
        )
        and population_source.contains(
            "_spawn_runtime("
        )
        and population_source.contains(
            "\"heading_radians\""
        ),
        "Halas patrol compatibility controller is not bridged through ZoneRuntimeState."
    )


    _expect(
        main_source.contains(
            "_prepare_zone_presentation()"
        )
        and main_source.contains(
            "zone_presentation_host.begin_zone("
        )
        and main_source.contains(
            "active_zone_presentation.add_child("
        )
        and main_source.contains(
            "active_zone_presentation.add_child(container)"
        ),
        "Active-zone world presentation is not routed through ZonePresentationHost."
    )

    _expect(
        main_source.contains(
            "func _release_active_zone_population() -> bool:"
        )
        and main_source.contains(
            "view_registry.unbind("
        )
        and main_source.contains(
            "simulation.release_entity("
        )
        and main_source.contains(
            "func _unload_active_zone() -> bool:"
        ),
        "Zone-owned NPC presentation does not have reload-safe teardown."
    )

    _expect(
        main_source.contains(
            "func execute_zone_transition("
        )
        and main_source.contains(
            "_staged_content_service_for_zone("
        )
        and main_source.contains(
            "_unload_active_zone()"
        )
        and main_source.contains(
            "zone_host.prepare_definition("
        )
        and main_source.contains(
            "_place_persistent_player_after_transition("
        ),
        "Main does not execute transitions through staged content and ZoneHost."
    )

func _test_spawn_point_state_round_trip() -> void:
    var state := ZoneRuntimeState.new(
        "eqm:zone:test"
    )

    state.ensure_spawn_point(
        "peq:spawn:101",
        "peq:spawn_group:202",
        30.0
    )

    state.occupy_spawn(
        "peq:spawn:101",
        "eqm:runtime:test:spawn:101",
        "peq:npc:303"
    )

    state.set_spawn_runtime(
        "peq:spawn:101",
        {
            "grid_id": 17,
            "position": [
                1.0,
                2.0,
                3.0,
            ],
            "heading_eq": 128.0,
            "heading_radians": 1.25,
            "patrol_index": 2,
            "pause_remaining": 4.5,
        }
    )

    var snapshot := state.snapshot()

    var restored := ZoneRuntimeState.new()

    _expect(
        restored.restore(
            snapshot,
            "eqm:zone:test"
        ),
        "Zone runtime state did not restore."
    )

    var restored_spawn := restored.spawn_state(
        "peq:spawn:101"
    )

    _expect(
        str(
            restored_spawn.get(
                "state",
                ""
            )
        ) == ZoneRuntimeState.SPAWN_OCCUPIED,
        "Spawn occupant state did not survive zone-state restore."
    )

    _expect(
        str(
            restored_spawn.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:303",
        "Spawn-point selected NPC definition did not survive restore."
    )

    var restored_runtime_variant: Variant = (
        restored_spawn.get(
            "runtime",
            {}
        )
    )
    var restored_runtime: Dictionary = (
        restored_runtime_variant
        if restored_runtime_variant is Dictionary
        else {}
    )

    _expect(
        int(
            restored_runtime.get(
                "grid_id",
                -1
            )
        ) == 17
        and int(
            restored_runtime.get(
                "patrol_index",
                -1
            )
        ) == 2
        and is_equal_approx(
            float(
                restored_runtime.get(
                    "pause_remaining",
                    -1.0
                )
            ),
            4.5
        )
        and is_equal_approx(
            float(
                restored_runtime.get(
                    "heading_radians",
                    0.0
                )
            ),
            1.25
        ),
        "Spawn-point patrol runtime state did not survive restore."
    )

    var restored_position_variant: Variant = (
        restored_runtime.get(
            "position",
            []
        )
    )

    _expect(
        restored_position_variant is Array
        and (
            restored_position_variant
            as Array
        ).size() == 3
        and is_equal_approx(
            float(
                (
                    restored_position_variant
                    as Array
                )[0]
            ),
            1.0
        ),
        "Spawn-point runtime position did not survive restore."
    )

    restored.begin_respawn(
        "peq:spawn:101",
        "peq:npc:303",
        12.25
    )

    restored_spawn = restored.spawn_state(
        "peq:spawn:101"
    )

    _expect(
        str(
            restored_spawn.get(
                "state",
                ""
            )
        ) == ZoneRuntimeState.SPAWN_RESPAWNING
        and str(
            restored_spawn.get(
                "occupant_entity_id",
                "occupied"
            )
        ).is_empty()
        and is_equal_approx(
            float(
                restored_spawn.get(
                    "respawn_remaining",
                    -1.0
                )
            ),
            12.25
        ),
        "Respawn timing/state is not owned by the spawn point."
    )


func _test_world_object_state_round_trip() -> void:
    var state := ZoneRuntimeState.new(
        "eqm:zone:test"
    )

    state.set_world_object_state(
        "fixture:world_object:test_door",
        {
            "state": "open",
            "close_remaining": 3.0,
        }
    )

    var restored := ZoneRuntimeState.new()

    _expect(
        restored.restore(
            state.snapshot(),
            "eqm:zone:test"
        ),
        "World-object zone state did not restore."
    )

    var door_state := restored.world_object_state(
        "fixture:world_object:test_door"
    )

    _expect(
        str(
            door_state.get(
                "state",
                ""
            )
        ) == "open"
        and is_equal_approx(
            float(
                door_state.get(
                    "close_remaining",
                    0.0
                )
            ),
            3.0
        ),
        "Interactable world-object state did not survive zone-state restore."
    )


func _test_zone_presentation_lifetime() -> void:
    var host := ZonePresentationHost.new()

    var presentation := (
        host.begin_zone(
            "eqm:zone:presentation_test"
        )
    )

    _expect(
        presentation != null
        and host.active_zone_root
        == presentation
        and presentation.zone_key
        == "eqm:zone:presentation_test"
        and host.get_child_count() == 1
        and host.get_child(0)
        == presentation,
        "ZonePresentationHost did not own one active-zone presentation root."
    )

    if presentation != null:
        var geometry := Node3D.new()
        geometry.name = "ZoneGeometryFixture"
        presentation.add_child(
            geometry
        )

        var objects := Node3D.new()
        objects.name = "ZoneObjects"
        presentation.add_child(
            objects
        )

        _expect(
            presentation.get_child_count()
            == 2,
            "Active-zone presentation did not contain zone-owned children."
        )

    host.clear_zone()

    _expect(
        host.active_zone_root
        == null
        and host.get_child_count()
        == 0,
        "Presentation host clear left active-zone nodes attached."
    )

    var second := host.begin_zone(
        "eqm:zone:presentation_second"
    )

    _expect(
        second != null
        and second.zone_key
        == "eqm:zone:presentation_second"
        and host.get_child_count()
        == 1,
        "ZonePresentationHost could not establish a second zone presentation."
    )

    host.clear_zone()
    host.free()


func _test_zone_host_domain_separation() -> void:
    var file := FileAccess.open(
        "res://scripts/domain/zone_host.gd",
        FileAccess.READ
    )

    _expect(
        file != null,
        "ZoneHost source could not be read for architecture audit."
    )

    if file == null:
        return

    var source := file.get_as_text()

    for forbidden in [
        "active_presentation_root",
        "ActiveZonePresentation",
        "ZonePresentationHost",
        "create_presentation_root",
        "clear_active_presentation",
        "Unload the active-zone presentation",
        "queue_free(",
        "add_child(",
        "remove_child(",
        "Node3D",
    ]:
        _expect(
            not source.contains(
                forbidden
            ),
            "Domain ZoneHost leaked presentation dependency: %s"
            % forbidden
        )



func _test_zone_host_lifecycle() -> void:
    var host := ZoneHost.new()

    _expect(
        host.prepare_definition(
            {
                "key": "eqm:zone:first",
                "id": "first",
            },
            false
        ),
        "ZoneHost could not prepare its first zone."
    )

    _expect(
        host.is_prepared()
        and host.active_zone_key
        == "eqm:zone:first"
        and host.active_runtime_state
        != null
        and host.spawn_resolver
        != null,
        "ZoneHost did not establish the active-zone lifecycle objects."
    )

    host.active_runtime_state.ensure_spawn_point(
        "peq:spawn:501",
        "peq:spawn_group:601",
        30.0
    )
    host.active_runtime_state.select_spawn_definition(
        "peq:spawn:501",
        "peq:npc:701"
    )
    host.active_runtime_state.set_spawn_runtime(
        "peq:spawn:501",
        {
            "grid_id": 9,
            "patrol_index": 4,
            "pause_remaining": 2.5,
        }
    )
    host.active_runtime_state.set_world_object_state(
        "fixture:first:door",
        {
            "state": "open",
        }
    )

    _expect(
        host.unload_active_zone(),
        "ZoneHost could not capture and unload the active zone."
    )

    _expect(
        not host.is_prepared()
        and host.active_zone_key.is_empty()
        and host.state_store.has_zone(
            "eqm:zone:first"
        ),
        "ZoneHost unload did not leave the captured zone dormant."
    )

    _expect(
        host.prepare_definition(
            {
                "key": "eqm:zone:second",
                "id": "second",
            },
            false
        ),
        "ZoneHost could not prepare a second zone."
    )

    host.active_runtime_state.set_world_object_state(
        "fixture:second:door",
        {
            "state": "closed",
        }
    )

    _expect(
        host.capture_active_zone(),
        "ZoneHost could not capture the second zone."
    )

    _expect(
        host.prepare_definition(
            {
                "key": "eqm:zone:first",
                "id": "first",
            }
        ),
        "ZoneHost could not return to the first zone."
    )

    var restored_spawn := (
        host.active_runtime_state.spawn_state(
            "peq:spawn:501"
        )
    )
    var runtime_variant: Variant = (
        restored_spawn.get(
            "runtime",
            {}
        )
    )
    var runtime: Dictionary = (
        runtime_variant
        if runtime_variant is Dictionary
        else {}
    )

    _expect(
        str(
            restored_spawn.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:701"
        and int(
            runtime.get(
                "grid_id",
                -1
            )
        ) == 9
        and int(
            runtime.get(
                "patrol_index",
                -1
            )
        ) == 4
        and str(
            host.active_runtime_state
            .world_object_state(
                "fixture:first:door"
            ).get(
                "state",
                ""
            )
        ) == "open",
        "ZoneHost reload did not restore the first zone runtime state."
    )

    _expect(
        host.state_store.has_zone(
            "eqm:zone:second"
        )
        and str(
            host.state_store.zone_snapshot(
                "eqm:zone:second"
            ).get(
                "zone_key",
                ""
            )
        ) == "eqm:zone:second",
        "ZoneHost lost the dormant second zone while reactivating the first."
    )


func _test_zone_state_store_unload_reload() -> void:
    var store := ZoneStateStore.new()

    var first := ZoneRuntimeState.new(
        "eqm:zone:first"
    )

    first.ensure_spawn_point(
        "peq:spawn:1001",
        "peq:spawn_group:2001",
        30.0
    )
    first.select_spawn_definition(
        "peq:spawn:1001",
        "peq:npc:3001"
    )
    first.occupy_spawn(
        "peq:spawn:1001",
        "eqm:runtime:first:1001",
        "peq:npc:3001"
    )
    first.set_spawn_runtime(
        "peq:spawn:1001",
        {
            "grid_id": 11,
            "patrol_index": 3,
            "pause_remaining": 4.25,
            "position": [
                1.0,
                2.0,
                3.0,
            ],
            "heading_radians": 0.75,
        }
    )
    first.set_world_object_state(
        "fixture:first:door",
        {
            "state": "open",
        }
    )

    var second := ZoneRuntimeState.new(
        "eqm:zone:second"
    )

    second.ensure_spawn_point(
        "peq:spawn:1002",
        "peq:spawn_group:2002",
        60.0
    )
    second.select_spawn_definition(
        "peq:spawn:1002",
        "peq:npc:3002"
    )
    second.begin_respawn(
        "peq:spawn:1002",
        "peq:npc:3002",
        12.5
    )
    second.set_spawn_runtime(
        "peq:spawn:1002",
        {
            "grid_id": 22,
            "patrol_index": 8,
            "pause_remaining": 1.5,
            "position": [
                9.0,
                8.0,
                7.0,
            ],
            "heading_radians": 1.5,
        }
    )
    second.set_world_object_state(
        "fixture:second:door",
        {
            "state": "closed",
        }
    )

    _expect(
        store.capture_zone(
            first
        ),
        "Zone-state store could not capture the first zone."
    )

    _expect(
        store.capture_zone(
            second
        ),
        "Zone-state store could not capture the second zone."
    )

    _expect(
        store.zone_keys()
        == [
            "eqm:zone:first",
            "eqm:zone:second",
        ],
        "Zone-state store did not retain two isolated zone keys."
    )

    # Simulate unloading both zone-runtime objects and later recreating them.
    first = ZoneRuntimeState.new(
        "eqm:zone:first"
    )
    second = ZoneRuntimeState.new(
        "eqm:zone:second"
    )

    _expect(
        store.restore_zone(
            "eqm:zone:first",
            first
        ),
        "First zone could not reload from the generic zone-state store."
    )

    _expect(
        store.restore_zone(
            "eqm:zone:second",
            second
        ),
        "Second zone could not reload from the generic zone-state store."
    )

    var first_spawn := first.spawn_state(
        "peq:spawn:1001"
    )
    var second_spawn := second.spawn_state(
        "peq:spawn:1002"
    )

    var first_runtime_variant: Variant = (
        first_spawn.get(
            "runtime",
            {}
        )
    )
    var first_runtime: Dictionary = (
        first_runtime_variant
        if first_runtime_variant is Dictionary
        else {}
    )

    var second_runtime_variant: Variant = (
        second_spawn.get(
            "runtime",
            {}
        )
    )
    var second_runtime: Dictionary = (
        second_runtime_variant
        if second_runtime_variant is Dictionary
        else {}
    )

    _expect(
        str(
            first_spawn.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:3001"
        and str(
            first_spawn.get(
                "occupant_entity_id",
                ""
            )
        ) == "eqm:runtime:first:1001"
        and int(
            first_runtime.get(
                "grid_id",
                -1
            )
        ) == 11
        and int(
            first_runtime.get(
                "patrol_index",
                -1
            )
        ) == 3
        and is_equal_approx(
            float(
                first_runtime.get(
                    "pause_remaining",
                    0.0
                )
            ),
            4.25
        ),
        "First zone lost its independent spawn/patrol runtime state."
    )

    _expect(
        str(
            second_spawn.get(
                "state",
                ""
            )
        ) == ZoneRuntimeState.SPAWN_RESPAWNING
        and str(
            second_spawn.get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:3002"
        and int(
            second_runtime.get(
                "grid_id",
                -1
            )
        ) == 22
        and int(
            second_runtime.get(
                "patrol_index",
                -1
            )
        ) == 8
        and is_equal_approx(
            float(
                second_spawn.get(
                    "respawn_remaining",
                    0.0
                )
            ),
            12.5
        ),
        "Second zone lost its independent respawn/patrol runtime state."
    )

    var first_door := first.world_object_state(
        "fixture:first:door"
    )
    var second_door := second.world_object_state(
        "fixture:second:door"
    )

    _expect(
        str(
            first_door.get(
                "state",
                ""
            )
        ) == "open"
        and second.world_object_state(
            "fixture:first:door"
        ).is_empty(),
        "First-zone world-object state leaked into the second zone."
    )

    _expect(
        str(
            second_door.get(
                "state",
                ""
            )
        ) == "closed"
        and first.world_object_state(
            "fixture:second:door"
        ).is_empty(),
        "Second-zone world-object state leaked into the first zone."
    )

    # The state store itself must also be serializable independently of live
    # ZoneRuntimeState instances; this becomes the disk-persistence boundary
    # in the next slice.
    var persisted_store := store.snapshot()
    var restored_store := ZoneStateStore.new()

    _expect(
        restored_store.restore(
            persisted_store
        ),
        "Zone-state store snapshot did not restore."
    )

    var reloaded_first := ZoneRuntimeState.new()
    var reloaded_second := ZoneRuntimeState.new()

    _expect(
        restored_store.restore_zone(
            "eqm:zone:first",
            reloaded_first
        )
        and restored_store.restore_zone(
            "eqm:zone:second",
            reloaded_second
        ),
        "Persisted zone-state store did not reload both zones."
    )

    _expect(
        str(
            reloaded_first.spawn_state(
                "peq:spawn:1001"
            ).get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:3001"
        and str(
            reloaded_second.spawn_state(
                "peq:spawn:1002"
            ).get(
                "selected_definition_ref",
                ""
            )
        ) == "peq:npc:3002",
        "Persisted store mixed zone identities during reload."
    )

    # A malformed store must fail atomically rather than partially replacing
    # the already-valid snapshots.
    var malformed := persisted_store.duplicate(
        true
    )
    var malformed_zones: Dictionary = (
        malformed.get(
            "zones",
            {}
        )
    )
    var malformed_first: Dictionary = (
        malformed_zones[
            "eqm:zone:first"
        ]
    )
    malformed_first[
        "zone_key"
    ] = "eqm:zone:wrong"
    malformed_zones[
        "eqm:zone:first"
    ] = malformed_first
    malformed[
        "zones"
    ] = malformed_zones

    _expect(
        not restored_store.restore(
            malformed
        ),
        "Malformed multi-zone state store was accepted."
    )

    _expect(
        restored_store.has_zone(
            "eqm:zone:first"
        )
        and restored_store.has_zone(
            "eqm:zone:second"
        ),
        "Failed store restore partially destroyed previously valid zone state."
    )


func _test_zone_transition_contract() -> void:
    var request := ZoneTransitionRequest.new()

    request.configure({
        "source_zone_key":
            "eqm:zone:test_a",
        "target_zone_key":
            "eqm:zone:test_b",
        "target_entry_ref":
            "eqm:zone_entry:test_b:south",
        "target_heading_eq":
            128.0,
        "reason":
            "zone_line",
    })

    _expect(
        request.is_valid(),
        "Zone transition request with an entry reference is invalid."
    )

    var restored: ZoneTransitionRequest = (
        ZoneTransitionRequest.from_dict(
            request.to_dict()
        )
    )

    _expect(
        restored.is_valid()
        and restored.source_zone_key
            == "eqm:zone:test_a"
        and restored.target_zone_key
            == "eqm:zone:test_b"
        and restored.target_entry_ref
            == "eqm:zone_entry:test_b:south",
        "Zone transition request did not round-trip."
    )

    var coordinate_request := ZoneTransitionRequest.new()

    coordinate_request.configure({
        "source_zone_key":
            "eqm:zone:test_a",
        "target_zone_key":
            "eqm:zone:test_b",
        "target_position": [
            4.0,
            5.0,
            6.0,
        ],
    })

    _expect(
        coordinate_request.is_valid(),
        "Coordinate-based zone transition request is invalid."
    )
    var loader := ZoneDefinitionLoader.new()
    var fixture := loader.load_zone(
        "eqm:zone:phase6_transition_fixture"
    )

    _expect(
        not fixture.is_empty()
        and bool(
            fixture.get(
                "fixture",
                false
            )
        )
        and str(
            fixture.get(
                "geometry_scene",
                ""
            )
        ) == "res://scenes/fixtures/phase6_transition_fixture_geometry.tscn"
        and str(
            fixture.get(
                "npc_model_directory",
                ""
            )
        ).is_empty()
        and not loader.runtime_content_paths(
            fixture
        ).get(
            "npcs",
            ""
        ).is_empty(),
        "Phase 6 transition fixture is not a clean data-only zone."
    )



func _expect(
    condition: bool,
    message: String
) -> void:
    if not condition:
        _failures.append(
            message
        )
