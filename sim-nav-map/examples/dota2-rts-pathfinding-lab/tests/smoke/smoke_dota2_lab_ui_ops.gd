extends Node


const LAB_SCENE_PATH: String = "res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/frontend/dota2_pathfinding_lab.tscn"
const AUTO_DEMO_SCENE_PATH: String = "res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/frontend/dota2_ai_command_demo.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	await _test_frontend_ui_ops()
	await _test_auto_demo_scene_boots()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab ui ops")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_frontend_ui_ops() -> void:
	var packed_scene: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_failures.append("ui-ops: failed to load lab scene")
		return

	var instance: Variant = packed_scene.instantiate()
	var instance_node := instance as Node
	if instance_node == null:
		_failures.append("ui-ops: failed to instantiate lab scene")
		return
	add_child(instance_node)
	await get_tree().process_frame

	var world: Dota2LabWorld = instance._world as Dota2LabWorld
	if world == null:
		_failures.append("ui-ops: frontend did not create world")
		instance_node.queue_free()
		return

	var initial_obstacle_count := world.obstacles.size()
	instance._handle_key(KEY_2)
	_press_left(instance, Vector2(1040.0, 450.0))
	if world.obstacles.size() != initial_obstacle_count + 1:
		_failures.append("ui-ops: obstacle tool did not add obstacle")

	var initial_unit_count := world.units.size()
	instance._handle_key(KEY_3)
	_press_left(instance, Vector2(1040.0, 280.0))
	if world.units.size() != initial_unit_count + 1:
		_failures.append("ui-ops: blocker tool did not add blocker")

	instance._handle_key(KEY_4)
	_press_left(instance, Vector2(1040.0, 280.0))
	if world.units.size() != initial_unit_count:
		_failures.append("ui-ops: erase tool did not remove blocker")

	instance._handle_key(KEY_A)
	if instance._selected_unit_ids.size() != world.get_mobile_unit_ids().size():
		_failures.append("ui-ops: select-all did not select mobile units")

	instance._drag_start = Vector2(90.0, 350.0)
	instance._finish_selection(Vector2(285.0, 550.0))
	if instance._selected_unit_ids.size() < 2:
		_failures.append("ui-ops: drag select selected fewer than two blue units")

	var target := Vector2(1160.0, 450.0)
	instance._move_selection(target)
	if world.current_target.distance_to(target) > 0.001:
		_failures.append("ui-ops: move command did not update current target")
	var selected_order_count := 0
	for unit_id in instance._selected_unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			continue
		if unit.current_order != null:
			selected_order_count += 1
	if selected_order_count != instance._selected_unit_ids.size():
		_failures.append("ui-ops: move command did not issue orders to selected units")

	instance._handle_key(KEY_C)
	for unit in world.units:
		if unit.trace.size() != 1:
			_failures.append("ui-ops: clear traces should leave one current position per unit")
			break

	var export_path := "user://dota2_lab_ui_ops_smoke.json"
	var global_export_path: String = instance.export_debug_log(export_path)
	if global_export_path == "" or not FileAccess.file_exists(export_path):
		_failures.append("ui-ops: export log did not write a file")
	else:
		var file := FileAccess.open(export_path, FileAccess.READ)
		if file == null:
			_failures.append("ui-ops: export log file could not be reopened")
		else:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if typeof(parsed) != TYPE_DICTIONARY:
				_failures.append("ui-ops: export log is not a JSON dictionary")
			else:
				_assert_export_shape(parsed as Dictionary)

	# Backend switches: don't assume native availability (this group is
	# cross-platform) — rebuild_context()/_ensure_native_solver() resolve
	# their own flag when the extension is missing, so only assert the UI
	# stays in sync with whatever it resolved to, and that the reset-stats
	# checkbox actually clears counters. Pathfinder and motion are
	# independent toggles — exercise each on its own.
	world.pathfinder.plan_count = 5
	world.pathfinder.line_check_count = 7
	instance._on_pathfinder_native_toggled(true)
	if instance._pathfinder_native_toggle.button_pressed != world.pathfinder.use_native:
		_failures.append("ui-ops: pathfinder toggle UI did not resync with pathfinder.use_native")
	if instance._reset_stats_on_switch.button_pressed \
			and (world.pathfinder.plan_count != 0 or world.pathfinder.line_check_count != 0):
		_failures.append("ui-ops: pathfinder toggle did not reset pathfinder stat counters")
	if world.motion.use_native_solver:
		_failures.append("ui-ops: pathfinder toggle leaked into motion.use_native_solver")
	instance._on_pathfinder_native_toggled(false)
	if world.pathfinder.use_native:
		_failures.append("ui-ops: pathfinder toggle did not return to GDScript when disabled")
	if instance._pathfinder_native_toggle.button_pressed:
		_failures.append("ui-ops: pathfinder toggle UI did not reflect GDScript state")

	instance._on_motion_native_toggled(true)
	if instance._motion_native_toggle.button_pressed != world.motion.use_native_solver:
		_failures.append("ui-ops: motion toggle UI did not resync with motion.use_native_solver")
	if world.pathfinder.use_native:
		_failures.append("ui-ops: motion toggle leaked into pathfinder.use_native")
	instance._on_motion_native_toggled(false)
	if world.motion.use_native_solver:
		_failures.append("ui-ops: motion toggle did not return to GDScript when disabled")
	if instance._motion_native_toggle.button_pressed:
		_failures.append("ui-ops: motion toggle UI did not reflect GDScript state")

	instance_node.queue_free()


func _test_auto_demo_scene_boots() -> void:
	var packed_scene: PackedScene = load(AUTO_DEMO_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_failures.append("auto-demo: failed to load scene")
		return

	var instance: Variant = packed_scene.instantiate()
	var instance_node := instance as Node
	if instance_node == null:
		_failures.append("auto-demo: failed to instantiate scene")
		return
	add_child(instance_node)
	await get_tree().process_frame

	var world: Dota2LabWorld = instance._world as Dota2LabWorld
	if world == null:
		_failures.append("auto-demo: scene did not create world")
		instance_node.queue_free()
		return
	if not bool(instance.auto_command_demo):
		_failures.append("auto-demo: auto_command_demo flag is not enabled")
	if world.get_unit("lane_0") == null or world.get_unit("chaser") == null:
		_failures.append("auto-demo: expected demo units are missing")

	for i in range(8):
		await get_tree().process_frame

	if instance._ai_command_source == null:
		_failures.append("auto-demo: command source missing")
	else:
		var emitted_count := int(instance._ai_command_source.emitted_count())
		if emitted_count < 1:
			_failures.append("auto-demo: command source did not emit initial command")
	if world.tick_count < 1:
		_failures.append("auto-demo: world did not step")
	var lane_0 := world.get_unit("lane_0")
	if lane_0 == null or lane_0.current_order == null:
		_failures.append("auto-demo: lane_0 did not receive an automatic order")

	instance_node.queue_free()


func _assert_export_shape(parsed: Dictionary) -> void:
	if parsed.get("schema", "") != "dota2_rts_pathfinding_lab_debug_log_v1":
		_failures.append("ui-ops: export log schema mismatch")
	if not parsed.has("recent_events"):
		_failures.append("ui-ops: export log missing recent_events")
	if not parsed.has("slow_frames"):
		_failures.append("ui-ops: export log missing slow_frames")
	if not parsed.has("units"):
		_failures.append("ui-ops: export log missing units")
	if not parsed.has("obstacles"):
		_failures.append("ui-ops: export log missing obstacles")
	var perf: Dictionary = parsed.get("perf", {}) as Dictionary
	var world: Dictionary = parsed.get("world", {}) as Dictionary
	if not perf.has("max_step_tick"):
		_failures.append("ui-ops: export log missing perf.max_step_tick")
	if not perf.has("avg_step_usec"):
		_failures.append("ui-ops: export log missing perf.avg_step_usec")
	if not world.has("metrics"):
		_failures.append("ui-ops: export log missing world.metrics")
	if not world.has("recent_motion_updates"):
		_failures.append("ui-ops: export log missing world.recent_motion_updates")
	var units: Array = parsed.get("units", []) as Array
	if units.is_empty():
		_failures.append("ui-ops: export log has no units")
	else:
		var first_unit: Dictionary = units[0] as Dictionary
		if not first_unit.has("state"):
			_failures.append("ui-ops: export log missing unit.state")
		if not first_unit.has("last_order"):
			_failures.append("ui-ops: export log missing unit.last_order")
		if not first_unit.has("last_speed_factor"):
			_failures.append("ui-ops: export log missing unit.last_speed_factor")


func _press_left(instance: Variant, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	instance._handle_mouse_button(event)
