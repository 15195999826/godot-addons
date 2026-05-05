extends Node


const LAB_SCENE_PATH: String = "res://addons/logic-game-framework/example/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn"
const MODE_COMMAND: int = 0
const MODE_OBSTACLE: int = 1
const MODE_BLOCKER: int = 2
const MODE_ERASE: int = 3

var _frames: int = 0
var _scene: Node = null
var _failures: Array[String] = []


func _ready() -> void:
	var packed: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	if packed == null:
		print("SMOKE_TEST_RESULT: FAIL - failed to load lab scene")
		get_tree().quit(1)
		return
	_scene = packed.instantiate()
	if _scene == null:
		print("SMOKE_TEST_RESULT: FAIL - failed to instantiate lab scene")
		get_tree().quit(1)
		return
	add_child(_scene)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		_run_frontend_interaction_smoke()
		if not _failures.is_empty():
			var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
			printerr(msg)
			print(msg)
			get_tree().quit(1)
			return
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab frontend interaction smoke")
		get_tree().quit(0)


func _run_frontend_interaction_smoke() -> void:
	var world := _scene.get("_world") as RtsPathfindingLabWorld
	if world == null:
		_failures.append("scene world should be initialized")
		return
	var hud := _scene.get("_hud") as Label
	if hud == null:
		_failures.append("scene HUD should be initialized")
		return

	_select_single_unit()
	_move_selected_unit(world)
	_place_obstacle(world)
	_place_and_erase_blocker(world)
	_toggle_runtime_options(world)
	_reset_and_run_until_arrival(world, hud)


func _select_single_unit() -> void:
	var click_pos := Vector2(74.0, 162.0)
	_scene.set("_drag_start", click_pos)
	_scene.call("_finish_selection", click_pos)
	var selected: Array = _scene.get("_selected_unit_ids") as Array
	if selected.size() != 1 or selected[0] != "blue_0":
		_failures.append("click selection expected [blue_0], got %s" % str(selected))


func _move_selected_unit(world: RtsPathfindingLabWorld) -> void:
	var target := Vector2(610.0, 160.0)
	_mouse_button(MOUSE_BUTTON_RIGHT, target, true)
	var selected: Array = _scene.get("_selected_unit_ids") as Array
	if selected.size() != 1:
		_failures.append("move should preserve single selection, got %s" % str(selected))
		return
	var unit := world.get_unit_by_id(str(selected[0]))
	if unit == null:
		_failures.append("selected unit should exist after move")
		return
	if world.current_target.distance_to(target) > 0.01:
		_failures.append("right-click move should update world target")
	if unit.target.distance_to(target) > 40.0:
		_failures.append("right-click move should retarget selected unit near clicked target")
	var last_action := str(_scene.get("_last_action"))
	if not last_action.begins_with("move 1"):
		_failures.append("right-click move should update last_action, got %s" % last_action)


func _place_obstacle(world: RtsPathfindingLabWorld) -> void:
	var obstacle_count := world.obstacles.size()
	_scene.set("_mode", MODE_OBSTACLE)
	_mouse_button(MOUSE_BUTTON_LEFT, Vector2(250.0, 120.0), true)
	if world.obstacles.size() != obstacle_count + 1:
		_failures.append("obstacle tool should add one obstacle")
	var last_action := str(_scene.get("_last_action"))
	if not last_action.begins_with("placed custom_obstacle"):
		_failures.append("obstacle tool should update last_action, got %s" % last_action)


func _place_and_erase_blocker(world: RtsPathfindingLabWorld) -> void:
	var unit_count := world.units.size()
	var blocker_pos := Vector2(260.0, 220.0)
	_scene.set("_mode", MODE_BLOCKER)
	_mouse_button(MOUSE_BUTTON_LEFT, blocker_pos, true)
	if world.units.size() != unit_count + 1:
		_failures.append("blocker tool should add one non-mobile unit")
		return

	_scene.set("_mode", MODE_ERASE)
	_mouse_button(MOUSE_BUTTON_LEFT, blocker_pos, true)
	if world.units.size() != unit_count:
		_failures.append("erase tool should remove the placed blocker")
	var last_action := str(_scene.get("_last_action"))
	if not last_action.begins_with("removed custom_blocker"):
		_failures.append("erase tool should update last_action, got %s" % last_action)


func _toggle_runtime_options(world: RtsPathfindingLabWorld) -> void:
	var group_before := world.group_filter_enabled
	var dynamic_before := world.avoid_moving_units_enabled
	_key(KEY_G)
	_key(KEY_D)
	if world.group_filter_enabled == group_before:
		_failures.append("G key should toggle group filter")
	if world.avoid_moving_units_enabled == dynamic_before:
		_failures.append("D key should toggle dynamic avoidance")


func _reset_and_run_until_arrival(world: RtsPathfindingLabWorld, hud: Label) -> void:
	_key(KEY_R)
	_key(KEY_A)
	for _i in range(520):
		world.step(0.05)
		if world.all_mobile_arrived():
			break
	_scene.call("_update_hud")
	var metrics := world.analyze_movement()
	if int(metrics.get("arrived_count", 0)) != int(metrics.get("mobile_count", -1)):
		_failures.append("frontend world should arrive after reset, metrics=%s" % str(metrics))
	if float(metrics.get("max_final_error", 999.0)) > 10.0:
		_failures.append("frontend max_final_error too high, metrics=%s" % str(metrics))
	if int(metrics.get("obstacle_violations", 99)) != 0:
		_failures.append("frontend obstacle_violations should be zero, metrics=%s" % str(metrics))
	if hud.text.find("arrived 6/6") < 0:
		_failures.append("HUD should expose arrival metrics after update, got %s" % hud.text)


func _mouse_button(button_index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.position = pos
	event.pressed = pressed
	_scene.call("_handle_mouse_button", event)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_scene.call("_unhandled_input", event)
