extends Node2D


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

enum ToolMode {
	COMMAND,
	OBSTACLE,
	BLOCKER,
	ERASE,
}

const DRAG_SELECT_THRESHOLD: float = 5.0
const OBSTACLE_SIZE: Vector2 = Vector2(74.0, 74.0)
const LOG_DIR: String = "user://rts_pathfinding_lab_logs"
const MAX_EVENT_LOG_ENTRIES: int = 160
const TRACE_EXPORT_LIMIT: int = 240
const SLOW_STEP_LOG_THRESHOLD_USEC: int = 50000

var _world: RtsPathfindingLabWorld = null
var _paused: bool = false
var _hud: Label = null
var _export_button: Button = null
var _mode: int = ToolMode.COMMAND
var _selected_unit_ids: Array[String] = []
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _last_action: String = "ready"
var _last_step_usec: int = 0
var _max_step_usec: int = 0
var _total_step_usec: int = 0
var _measured_step_count: int = 0
var _event_log: Array[Dictionary] = []
var _last_export_path: String = ""


func _ready() -> void:
	_world = LabWorld.new()
	_world.setup_default()
	_selected_unit_ids = _world.get_mobile_unit_ids()
	_hud = Label.new()
	_hud.position = Vector2(12.0, 10.0)
	add_child(_hud)
	_export_button = Button.new()
	_export_button.text = "Export log"
	_export_button.position = Vector2(606.0, 118.0)
	_export_button.custom_minimum_size = Vector2(102.0, 30.0)
	_export_button.z_index = 20
	_export_button.pressed.connect(_on_export_log_pressed)
	add_child(_export_button)
	_record_event("ready", {})
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		var step_start_usec := Time.get_ticks_usec()
		_world.step(minf(delta, 0.05))
		_last_step_usec = Time.get_ticks_usec() - step_start_usec
		_max_step_usec = maxi(_max_step_usec, _last_step_usec)
		_total_step_usec += _last_step_usec
		_measured_step_count += 1
		if _last_step_usec >= SLOW_STEP_LOG_THRESHOLD_USEC:
			_record_event("slow_step", {
				"step_usec": _last_step_usec,
				"max_step_usec": _max_step_usec,
				"tick": _world.tick_count,
				"metrics": _world.analyze_movement(),
				"pathfinder_last_report": _world.pathfinder.last_report,
			})
	_update_hud()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_handle_mouse_button(mb)
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_mode = ToolMode.COMMAND
			KEY_2:
				_mode = ToolMode.OBSTACLE
			KEY_3:
				_mode = ToolMode.BLOCKER
			KEY_4:
				_mode = ToolMode.ERASE
			KEY_A:
				_selected_unit_ids = _world.get_mobile_unit_ids()
				_last_action = "selected all"
				_record_event("select_all", {"selected_unit_ids": _selected_unit_ids})
			KEY_C:
				_world.clear_traces()
				_last_action = "cleared traces"
				_record_event("clear_traces", {})
			KEY_R:
				_world.setup_default()
				_selected_unit_ids = _world.get_mobile_unit_ids()
				_reset_perf_metrics()
				_last_action = "reset"
				_record_event("reset", {"selected_unit_ids": _selected_unit_ids})
			KEY_SPACE:
				_paused = not _paused
				_record_event("pause_toggle", {"paused": _paused})
			KEY_G:
				_world.group_filter_enabled = not _world.group_filter_enabled
				_world.set_group_target(_world.current_target)
				_record_event("group_filter_toggle", {"enabled": _world.group_filter_enabled})
			KEY_D:
				_world.avoid_moving_units_enabled = not _world.avoid_moving_units_enabled
				_world.set_group_target(_world.current_target)
				_record_event("dynamic_avoidance_toggle", {"enabled": _world.avoid_moving_units_enabled})
		queue_redraw()


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if _mode == ToolMode.COMMAND:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = mb.position
				_drag_current = mb.position
				_is_dragging = true
			else:
				_finish_selection(mb.position)
			queue_redraw()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_move_selection(mb.position)
			queue_redraw()
			return

	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	match _mode:
		ToolMode.OBSTACLE:
			var obstacle_id := _world.add_static_obstacle(mb.position, OBSTACLE_SIZE)
			_last_action = "placed %s" % obstacle_id
			_record_event("place_obstacle", {"id": obstacle_id, "position": mb.position})
		ToolMode.BLOCKER:
			var blocker_id := _world.add_blocker(mb.position)
			_last_action = "placed %s" % blocker_id
			_record_event("place_blocker", {"id": blocker_id, "position": mb.position})
		ToolMode.ERASE:
			var removed_id := _world.remove_nearest_editable(mb.position)
			_last_action = "removed %s" % removed_id if removed_id != "" else "nothing to erase"
			_record_event("erase", {"removed_id": removed_id, "position": mb.position})
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _is_dragging and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_drag_current = motion.position
		queue_redraw()


func _finish_selection(pos: Vector2) -> void:
	_is_dragging = false
	var drag_dist := pos.distance_to(_drag_start)
	if drag_dist <= DRAG_SELECT_THRESHOLD:
		var picked_id := _world.get_mobile_unit_at(pos)
		var picked_ids: Array[String] = []
		if picked_id != "":
			picked_ids.append(picked_id)
		_selected_unit_ids = picked_ids
	else:
		var rect := _rect_from_points(_drag_start, pos)
		_selected_unit_ids = _world.get_mobile_units_in_rect(rect)
	_last_action = "selected %d" % _selected_unit_ids.size()
	_record_event("select", {"position": pos, "selected_unit_ids": _selected_unit_ids})


func _move_selection(pos: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		_selected_unit_ids = _world.get_mobile_unit_ids()
	_world.set_units_target(_selected_unit_ids, pos)
	_last_action = "move %d units" % _selected_unit_ids.size()
	_record_event("move", {"position": pos, "selected_unit_ids": _selected_unit_ids})


func export_debug_log(file_path: String = "") -> String:
	if _world == null:
		return ""
	var target_path := file_path
	if target_path == "":
		if not _ensure_log_dir():
			return ""
		target_path = _default_export_path()
	var global_path := ProjectSettings.globalize_path(target_path)
	_record_event("export_log_requested", {"path": global_path})
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_last_action = "export failed"
		printerr("RTS_PATHFINDING_LAB_EXPORT_LOG_FAIL: %s" % target_path)
		return ""
	file.store_string(JSON.stringify(_json_safe(_build_export_snapshot()), "\t"))
	file.close()
	_last_export_path = global_path
	_last_action = "exported log"
	print("RTS_PATHFINDING_LAB_EXPORT_LOG: %s" % _last_export_path)
	_update_hud()
	return _last_export_path


func _on_export_log_pressed() -> void:
	export_debug_log()


func _ensure_log_dir() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		_last_action = "export failed"
		printerr("RTS_PATHFINDING_LAB_EXPORT_LOG_FAIL: cannot open user://")
		return false
	var err := dir.make_dir_recursive("rts_pathfinding_lab_logs")
	if err != OK:
		_last_action = "export failed"
		printerr("RTS_PATHFINDING_LAB_EXPORT_LOG_FAIL: mkdir error %d" % err)
		return false
	return true


func _default_export_path() -> String:
	var timestamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	return "%s/rts_pathfinding_lab_%s_tick_%d.json" % [
		LOG_DIR,
		timestamp,
		_world.tick_count,
	]


func _build_export_snapshot() -> Dictionary:
	var metrics := _world.analyze_movement()
	var avg_step_usec := float(_total_step_usec) / float(maxi(_measured_step_count, 1))
	return {
		"schema": "rts_pathfinding_lab_debug_log_v1",
		"exported_at": Time.get_datetime_string_from_system(false, false),
		"scene": "addons/sim-nav-map/examples/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn",
		"mode": _mode_name(),
		"paused": _paused,
		"last_action": _last_action,
		"selected_unit_ids": _selected_unit_ids.duplicate(),
		"current_target": _vector_snapshot(_world.current_target),
		"map_size": _vector_snapshot(_world.map_size),
		"perf": {
			"last_step_usec": _last_step_usec,
			"max_step_usec": _max_step_usec,
			"avg_step_usec": avg_step_usec,
			"measured_step_count": _measured_step_count,
		},
		"world": {
			"tick_count": _world.tick_count,
			"metrics": metrics,
			"group_filter_enabled": _world.group_filter_enabled,
			"avoid_moving_units_enabled": _world.avoid_moving_units_enabled,
			"pending_replans": int(metrics.get("pending_replans", 0)),
		},
		"pathfinder": {
			"last_report": _world.pathfinder.last_report,
			"static_context_cache_hits": _world.pathfinder.static_context_cache_hits,
			"static_context_cache_misses": _world.pathfinder.static_context_cache_misses,
		},
		"obstacles": _snapshot_obstacles(),
		"units": _snapshot_units(),
		"recent_events": _event_log.duplicate(true),
	}


func _snapshot_obstacles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obstacle in _world.obstacles:
		result.append({
			"id": obstacle.id,
			"center": _vector_snapshot(obstacle.center),
			"size": _vector_snapshot(obstacle.size),
			"rect": _rect_snapshot(obstacle.get_rect()),
			"inflated_rect": _rect_snapshot(obstacle.get_inflated_rect(_world.pathfinder.unit_radius)),
		})
	return result


func _snapshot_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in _world.units:
		result.append({
			"id": unit.id,
			"group_id": unit.group_id,
			"mobile": unit.mobile,
			"blocks_pathfinding": unit.blocks_pathfinding,
			"position": _vector_snapshot(unit.position),
			"target": _vector_snapshot(unit.target),
			"radius": unit.radius,
			"speed": unit.speed,
			"arrived": unit.arrived,
			"has_move_order": unit.has_move_order,
			"replan_timer": unit.replan_timer,
			"path_index": unit.path_index,
			"path": _vector_array_snapshot(unit.path, unit.path.size()),
			"trace_tail": _vector_array_snapshot(unit.trace, TRACE_EXPORT_LIMIT),
		})
	return result


func _record_event(kind: String, data: Dictionary) -> void:
	var tick := 0
	if _world != null:
		tick = _world.tick_count
	_event_log.append({
		"kind": kind,
		"tick": tick,
		"last_action": _last_action,
		"last_step_usec": _last_step_usec,
		"max_step_usec": _max_step_usec,
		"data": _json_safe(data),
	})
	while _event_log.size() > MAX_EVENT_LOG_ENTRIES:
		_event_log.pop_front()


func _vector_array_snapshot(points: Array[Vector2], limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index := maxi(points.size() - limit, 0)
	for i in range(start_index, points.size()):
		result.append(_vector_snapshot(points[i]))
	return result


func _vector_snapshot(point: Vector2) -> Dictionary:
	return {
		"x": point.x,
		"y": point.y,
	}


func _rect_snapshot(rect: Rect2) -> Dictionary:
	return {
		"position": _vector_snapshot(rect.position),
		"size": _vector_snapshot(rect.size),
		"end": _vector_snapshot(rect.end),
	}


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			var vector_value: Vector2 = value
			return _vector_snapshot(vector_value)
		TYPE_VECTOR2I:
			var vector_i_value: Vector2i = value
			return {
				"x": vector_i_value.x,
				"y": vector_i_value.y,
			}
		TYPE_RECT2:
			var rect_value: Rect2 = value
			return _rect_snapshot(rect_value)
		TYPE_ARRAY:
			var array_value: Array = value
			var safe_array: Array = []
			for item in array_value:
				safe_array.append(_json_safe(item))
			return safe_array
		TYPE_DICTIONARY:
			var dict_value: Dictionary = value
			var safe_dict: Dictionary = {}
			for key in dict_value.keys():
				safe_dict[str(key)] = _json_safe(dict_value[key])
			return safe_dict
		_:
			return str(value)


func _draw() -> void:
	if _world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, _world.map_size), Color(0.08, 0.10, 0.11), true)
	_draw_grid()
	for obstacle in _world.obstacles:
		var rect := obstacle.get_rect()
		draw_rect(rect, Color(0.38, 0.35, 0.30), true)
		draw_rect(obstacle.get_inflated_rect(_world.pathfinder.unit_radius), Color(0.95, 0.70, 0.25, 0.16), true)
		draw_rect(rect, Color(0.78, 0.67, 0.45), false, 2.0)
	draw_circle(_world.current_target, 7.0, Color(0.2, 0.95, 0.65))
	if _mode == ToolMode.OBSTACLE:
		var mouse_pos := get_viewport().get_mouse_position()
		draw_rect(Rect2(mouse_pos - OBSTACLE_SIZE * 0.5, OBSTACLE_SIZE), Color(0.95, 0.70, 0.25, 0.20), true)
		draw_rect(Rect2(mouse_pos - OBSTACLE_SIZE * 0.5, OBSTACLE_SIZE), Color(0.95, 0.70, 0.25), false, 1.0)

	for unit in _world.units:
		for i in range(1, unit.trace.size()):
			draw_line(unit.trace[i - 1], unit.trace[i], Color(0.45, 0.75, 1.0, 0.24), 1.0)
		if unit.path_index < unit.path.size():
			var prev := unit.position
			for k in range(unit.path_index, unit.path.size()):
				draw_line(prev, unit.path[k], Color(0.1, 0.85, 1.0, 0.55), 2.0)
				prev = unit.path[k]

	for unit in _world.units:
		var fill := Color(0.18, 0.55, 0.95) if unit.group_id == RtsPathfindingLabWorld.MOBILE_GROUP_ID else Color(0.90, 0.26, 0.22)
		if not unit.mobile:
			fill = Color(0.90, 0.45, 0.25)
		draw_circle(unit.position, unit.radius, fill)
		draw_arc(unit.position, unit.radius, 0.0, TAU, 24, Color(0.95, 0.95, 0.92), 1.5)
		if _selected_unit_ids.has(unit.id):
			draw_arc(unit.position, unit.radius + 5.0, 0.0, TAU, 32, Color(0.25, 1.0, 0.70), 2.5)

	if _is_dragging and _mode == ToolMode.COMMAND:
		var select_rect := _rect_from_points(_drag_start, _drag_current)
		draw_rect(select_rect, Color(0.20, 0.70, 1.0, 0.15), true)
		draw_rect(select_rect, Color(0.35, 0.85, 1.0), false, 1.5)


func _draw_grid() -> void:
	var step := _world.pathfinder.cell_size
	var grid_color := Color(0.33, 0.37, 0.39, 0.35)
	var x := 0.0
	while x <= _world.map_size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, _world.map_size.y), grid_color, 1.0)
		x += step
	var y := 0.0
	while y <= _world.map_size.y:
		draw_line(Vector2(0.0, y), Vector2(_world.map_size.x, y), grid_color, 1.0)
		y += step


func _update_hud() -> void:
	var metrics := _world.analyze_movement()
	var avg_step_msec := float(_total_step_usec) / float(maxi(_measured_step_count, 1)) / 1000.0
	_hud.text = "RTS pathfinding lab | mode %s | 1 move/select  2 obstacle  3 blocker  4 erase  A all  C clear traces\nselected %d | last: %s | R reset | Space pause | G group=%s | D dynamic=%s\narrived %d/%d  max_final_error %.1f  max_overlap %.2f  obstacle_violations %d  ticks %d\nworld.step %.2fms  avg %.2fms  max %.2fms  replans %d/%d pending %d" % [
		_mode_name(),
		_selected_unit_ids.size(),
		_last_action,
		str(_world.group_filter_enabled),
		str(_world.avoid_moving_units_enabled),
		int(metrics.get("arrived_count", 0)),
		int(metrics.get("mobile_count", 0)),
		float(metrics.get("max_final_error", 0.0)),
		float(metrics.get("max_overlap", 0.0)),
		int(metrics.get("obstacle_violations", 0)),
		int(metrics.get("ticks", 0)),
		float(_last_step_usec) / 1000.0,
		avg_step_msec,
		float(_max_step_usec) / 1000.0,
		int(metrics.get("last_replans_this_tick", 0)),
		int(metrics.get("max_replans_per_tick", 0)),
		int(metrics.get("pending_replans", 0)),
	]


func _mode_name() -> String:
	match _mode:
		ToolMode.COMMAND:
			return "move/select"
		ToolMode.OBSTACLE:
			return "place obstacle"
		ToolMode.BLOCKER:
			return "place blocker"
		ToolMode.ERASE:
			return "erase"
		_:
			return "unknown"


func _rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var end := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(pos, end - pos)


func _reset_perf_metrics() -> void:
	_last_step_usec = 0
	_max_step_usec = 0
	_total_step_usec = 0
	_measured_step_count = 0
