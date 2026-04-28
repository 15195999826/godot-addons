## Smoke: SkillPreview scene can stage a StoneWall into world/grid/replay.
extends Node


const SKILL_PREVIEW_SCENE := preload("res://addons/logic-game-framework/example/skill-preview/skill_preview.tscn")


var _preview: Node = null


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: skill_preview StoneWall placement ===")
	_preview = SKILL_PREVIEW_SCENE.instantiate()
	add_child(_preview)
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not _preview.has_method("_add_stone_wall"):
		_fail("SkillPreview script did not load _add_stone_wall")
		return
	_preview.call("_add_stone_wall", 0, 1)

	var environments: Array = _preview.get("_environments") as Array
	if environments.size() != 1:
		_fail("expected 1 staged environment, got %d" % environments.size())
		return
	var env_data: Dictionary = environments[0] as Dictionary
	if str(env_data.get("type", "")) != "stone_wall":
		_fail("staged environment type mismatch: %s" % str(env_data))
		return

	var environment_ids: Array = _preview.get("_environment_ids") as Array
	if environment_ids.size() != 1 or str(environment_ids[0]) == "":
		_fail("environment id missing after placement: %s" % str(environment_ids))
		return
	var env_id := str(environment_ids[0])

	var world := _preview.get("_world") as SkillPreviewWorldGI
	if world == null:
		_fail("SkillPreview world missing")
		return
	var env_actor := world.get_actor(env_id) as EnvironmentActor
	if env_actor == null:
		_fail("environment id not registered in world: %s" % env_id)
		return
	if env_actor.environment_kind != "stone_wall":
		_fail("world environment kind mismatch: %s" % env_actor.environment_kind)
		return
	var coord := HexCoord.new(0, 1)
	if world.grid == null or world.grid.get_occupant(coord) != env_actor:
		_fail("StoneWall not placed as grid occupant at (0,1)")
		return

	var scene_config: Dictionary = _preview.call("_build_scene_config") as Dictionary
	var env_config: Array = scene_config.get("environment", []) as Array
	if env_config.size() != 1:
		_fail("scene_config.environment missing: %s" % str(scene_config))
		return
	var env_cfg: Dictionary = env_config[0] as Dictionary
	if str(env_cfg.get("type", "")) != "stone_wall":
		_fail("scene_config environment type mismatch: %s" % str(env_cfg))
		return

	_preview.call("_on_start_pressed")
	var timeline: Dictionary = _preview.get("_last_timeline") as Dictionary
	if timeline.is_empty():
		_fail("preview run produced empty replay timeline")
		return

	var found_env := false
	for actor_init in timeline.get("initialActors", []) as Array:
		if not (actor_init is Dictionary):
			continue
		var init_data := actor_init as Dictionary
		if str(init_data.get("type", "")) != "Environment":
			continue
		if str(init_data.get("configId", "")) != "stone_wall":
			continue
		found_env = true
		var attrs: Dictionary = init_data.get("attributes", {}) as Dictionary
		var hp := float(attrs.get("hp", 0.0))
		var max_hp := float(attrs.get("max_hp", attrs.get("maxHp", 0.0)))
		if hp == INF or max_hp == INF or is_nan(hp) or is_nan(max_hp):
			_fail("StoneWall replay attributes are non-finite: %s" % str(attrs))
			return
		break
	if not found_env:
		_fail("replay initialActors missing stone_wall Environment: %s" % str(timeline.get("initialActors", [])))
		return

	_pass("StoneWall staged in UI model, world/grid, scene_config, and replay")


func _pass(reason: String) -> void:
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	if _preview != null:
		_preview.queue_free()
		_preview = null
	await get_tree().process_frame
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	if _preview != null:
		_preview.queue_free()
		_preview = null
	await get_tree().process_frame
	get_tree().quit(1)
