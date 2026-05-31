extends Node


const LAB_SCENE_PATH: String = "res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/frontend/zero_ad_rts_pathfinding_lab.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	await _test_frontend_ui_ops()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - 0ad rts lab ui ops")
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

	var world: ZeroAdRtsLabWorld = instance._world as ZeroAdRtsLabWorld
	if world == null:
		_failures.append("ui-ops: frontend did not create world")
		instance_node.queue_free()
		return

	var initial_obstacle_count: int = world.obstacles.size()
	instance._handle_key(KEY_2)
	_press_left(instance, Vector2(520.0, 210.0))
	if world.obstacles.size() != initial_obstacle_count + 1:
		_failures.append("ui-ops: obstacle tool did not add obstacle")

	var initial_unit_count: int = world.units.size()
	instance._handle_key(KEY_3)
	_press_left(instance, Vector2(500.0, 120.0))
	if world.units.size() != initial_unit_count + 1:
		_failures.append("ui-ops: blocker tool did not add blocker")

	instance._handle_key(KEY_4)
	_press_left(instance, Vector2(500.0, 120.0))
	if world.units.size() != initial_unit_count:
		_failures.append("ui-ops: erase tool did not remove blocker")

	instance._handle_key(KEY_A)
	if instance._selected_unit_ids.size() != world.get_mobile_unit_ids().size():
		_failures.append("ui-ops: select-all did not select mobile units")

	instance._drag_start = Vector2(70.0, 160.0)
	instance._finish_selection(Vector2(130.0, 250.0))
	if instance._selected_unit_ids.size() != 2:
		_failures.append("ui-ops: drag select did not select both blue units")

	var target := Vector2(610.0, 210.0)
	instance._move_selection(target)
	if world.current_target.distance_to(target) > 0.001:
		_failures.append("ui-ops: move command did not update current target")
	var selected_moving_count := 0
	for unit_id in instance._selected_unit_ids:
		var unit := world.get_unit(unit_id)
		if unit == null:
			continue
		if unit.has_move_order:
			selected_moving_count += 1
	if selected_moving_count != instance._selected_unit_ids.size():
		_failures.append("ui-ops: move command did not issue orders to selected units")

	instance._handle_key(KEY_C)
	for unit in world.units:
		if unit.trace.size() != 1:
			_failures.append("ui-ops: clear traces should leave one current position per unit")
			break

	var export_path := "user://zero_ad_rts_lab_ui_ops_smoke.json"
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
			elif not (parsed as Dictionary).has("recent_events"):
				_failures.append("ui-ops: export log missing recent_events")
			elif not (parsed as Dictionary).has("recent_path_decisions"):
				_failures.append("ui-ops: export log missing recent_path_decisions")
			elif not (parsed as Dictionary).has("recent_pair_contacts"):
				_failures.append("ui-ops: export log missing recent_pair_contacts")
			elif not (parsed as Dictionary).has("slow_frames"):
				_failures.append("ui-ops: export log missing slow_frames")
			else:
				var parsed_dict: Dictionary = parsed as Dictionary
				var perf: Dictionary = parsed_dict.get("perf", {}) as Dictionary
				var world_data: Dictionary = parsed_dict.get("world", {}) as Dictionary
				if not perf.has("max_step_tick"):
					_failures.append("ui-ops: export log missing max_step_tick")
				if not perf.has("max_step_stage_classification"):
					_failures.append("ui-ops: export log missing max_step_stage_classification")
				for perf_key in [
					"warm_avg_step_usec",
					"p95_step_usec",
					"p99_step_usec",
					"idle_avg_step_usec",
					"slow_frame_stage_counts",
					"warm_stage_avg_usec",
					"idle_stage_avg_usec",
				]:
					if not perf.has(perf_key):
						_failures.append("ui-ops: export log missing perf.%s" % perf_key)
				if not world_data.has("last_step_profile"):
					_failures.append("ui-ops: export log missing world.last_step_profile")
				if not world_data.has("recent_step_profiles"):
					_failures.append("ui-ops: export log missing world.recent_step_profiles")

	instance_node.queue_free()


func _press_left(instance: Variant, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	instance._handle_mouse_button(event)
