extends SceneTree

const HALAS_KEY := "eqm:zone:halas"
const FIXTURE_KEY := "eqm:zone:phase6_transition_fixture"
const FIXTURE_POSITION := Vector3(
    12.0,
    1.0,
    -8.0
)

var _failures: Array[String] = []


func _init() -> void:
    call_deferred(
        "_run"
    )


func _run() -> void:
    var packed := load(
        "res://scenes/Main.tscn"
    ) as PackedScene

    _expect(
        packed != null,
        "Main scene could not be loaded."
    )

    if packed == null:
        _finish()
        return

    var game: Node = (
        packed.instantiate()
    )

    root.add_child(
        game
    )

    await process_frame
    await physics_frame

    _expect(
        str(
            game.get(
                "current_zone_key"
            )
        ) == HALAS_KEY,
        "Transition smoke did not start in Halas."
    )

    var halas_ids_variant: Variant = (
        game.get(
            "zone_spawn_entity_ids"
        )
    )
    var halas_ids: Dictionary = (
        halas_ids_variant
        if halas_ids_variant is Dictionary
        else {}
    )

    var actor_ids: Array[String] = []

    for entity_id_variant in (
        halas_ids.values()
    ):
        var entity_id := str(
            entity_id_variant
        )

        if not entity_id.is_empty():
            actor_ids.append(
                entity_id
            )

    actor_ids.sort()

    _expect(
        not actor_ids.is_empty(),
        "Halas transition smoke has no transient NPC runtime IDs."
    )

    var probe_entity_id := (
        actor_ids[0]
        if not actor_ids.is_empty()
        else ""
    )

    var halas_state := (
        game.get(
            "zone_runtime_state"
        ) as ZoneRuntimeState
    )

    _expect(
        halas_state != null,
        "Halas has no active ZoneRuntimeState."
    )

    if halas_state != null:
        halas_state.set_world_object_state(
            "fixture:transition_probe:halas",
            {
                "value": 314,
            }
        )

    var to_fixture := (
        ZoneTransitionRequest.new()
    )

    to_fixture.configure({
        "source_zone_key":
            HALAS_KEY,
        "target_zone_key":
            FIXTURE_KEY,
        "target_position": [
            FIXTURE_POSITION.x,
            FIXTURE_POSITION.y,
            FIXTURE_POSITION.z,
        ],
        "reason":
            "phase6_transition_smoke",
    })

    _expect(
        bool(
            game.call(
                "execute_zone_transition",
                to_fixture
            )
        ),
        "Halas -> fixture transition failed."
    )

    # The fixture intentionally has no collision. Verify the executor's exact
    # 3D entry placement synchronously, before the next physics frame applies
    # gravity to the persistent CharacterBody3D.
    var player := (
        game.get(
            "player"
        ) as CharacterBody3D
    )

    _expect(
        player != null
        and player.global_position.distance_to(
            FIXTURE_POSITION
        ) < 0.001,
        "Persistent player was not placed at the fixture entry coordinate."
    )

    await process_frame
    await physics_frame

    _expect(
        str(
            game.get(
                "current_zone_key"
            )
        ) == FIXTURE_KEY,
        "Fixture zone did not become active."
    )

    _expect(
        game.get(
            "zone_npc_population"
        ) == null,
        "Halas NPC presentation survived fixture transition."
    )

    var simulation := (
        game.get(
            "simulation"
        ) as Simulation
    )

    if (
        simulation != null
        and not probe_entity_id.is_empty()
    ):
        _expect(
            simulation.entity(
                probe_entity_id
            ) == null,
            "Halas transient NPC entity survived fixture transition."
        )

    _expect(
        player != null
        and Vector2(
            player.global_position.x,
            player.global_position.z
        ).distance_to(
            Vector2(
                FIXTURE_POSITION.x,
                FIXTURE_POSITION.z
            )
        ) < 0.01,
        "Persistent player drifted horizontally from the fixture entry."
    )

    var fixture_state := (
        game.get(
            "zone_runtime_state"
        ) as ZoneRuntimeState
    )

    _expect(
        fixture_state != null
        and fixture_state.zone_key
        == FIXTURE_KEY,
        "Fixture ZoneRuntimeState was not activated."
    )

    if fixture_state != null:
        fixture_state.set_world_object_state(
            "fixture:transition_probe:fixture",
            {
                "value": 2718,
            }
        )

    var loader := (
        game.get(
            "zone_definition_loader"
        ) as ZoneDefinitionLoader
    )
    var halas_definition := (
        loader.load_zone(
            HALAS_KEY
        )
        if loader != null
        else {}
    )

    var halas_spawn_variant: Variant = (
        halas_definition.get(
            "player_spawn",
            [
                0.0,
                0.0,
                0.0,
            ]
        )
    )
    var halas_spawn: Array = (
        halas_spawn_variant
        if halas_spawn_variant is Array
        else [
            0.0,
            0.0,
            0.0,
        ]
    )

    var to_halas := (
        ZoneTransitionRequest.new()
    )

    to_halas.configure({
        "source_zone_key":
            FIXTURE_KEY,
        "target_zone_key":
            HALAS_KEY,
        "target_position":
            halas_spawn,
        "reason":
            "phase6_transition_smoke_return",
    })

    _expect(
        bool(
            game.call(
                "execute_zone_transition",
                to_halas
            )
        ),
        "Fixture -> Halas transition failed."
    )

    await process_frame
    await physics_frame

    _expect(
        str(
            game.get(
                "current_zone_key"
            )
        ) == HALAS_KEY,
        "Halas did not become active after return transition."
    )

    simulation = (
        game.get(
            "simulation"
        ) as Simulation
    )

    if (
        simulation != null
        and not probe_entity_id.is_empty()
    ):
        _expect(
            simulation.entity(
                probe_entity_id
            ) != null,
            "Halas transient NPC runtime ID could not be recreated."
        )

    var restored_halas_state := (
        game.get(
            "zone_runtime_state"
        ) as ZoneRuntimeState
    )

    _expect(
        restored_halas_state != null
        and int(
            restored_halas_state
            .world_object_state(
                "fixture:transition_probe:halas"
            ).get(
                "value",
                -1
            )
        ) == 314,
        "Halas runtime state did not survive unload/reload."
    )

    var host := (
        game.get(
            "zone_host"
        ) as ZoneHost
    )

    var fixture_probe := (
        ZoneRuntimeState.new(
            FIXTURE_KEY
        )
    )

    _expect(
        host != null
        and host.state_store.restore_zone(
            FIXTURE_KEY,
            fixture_probe
        )
        and int(
            fixture_probe
            .world_object_state(
                "fixture:transition_probe:fixture"
            ).get(
                "value",
                -1
            )
        ) == 2718,
        "Dormant fixture runtime state was not captured."
    )

    _expect(
        int(
            game.get(
                "zone_prop_instance_count"
            )
        ) == 445
        and int(
            game.get(
                "zone_prop_mesh_count"
            )
        ) == 445
        and int(
            game.get(
                "zone_prop_collision_count"
            )
        ) == 445,
        "Halas static presentation did not rebuild to its canonical counts."
    )

    game.queue_free()
    await process_frame

    _finish()


func _expect(
    condition: bool,
    message: String
) -> void:
    if not condition:
        _failures.append(
            message
        )


func _finish() -> void:
    if _failures.is_empty():
        print(
            "PASS: Halas -> fixture -> Halas transition "
            + "preserves persistent player and per-zone runtime state."
        )
        quit(0)
        return

    for failure in _failures:
        push_error(
            failure
        )

    print(
        "FAIL: Phase 6 transition smoke (%d failures)."
        % _failures.size()
    )
    quit(1)
