extends Node2D


enum ToolMode {
	COMMAND,
	OBSTACLE,
	BLOCKER,
	ERASE,
}

const DRAG_SELECT_THRESHOLD: float = 5.0
const OBSTACLE_SIZE: Vector2 = Vector2(74.0, 74.0)
const LOG_DIR: String = "user://zero_ad_rts_pathfinding_lab_logs"
const MAX_EVENT_LOG_ENTRIES: int = 160
const MAX_SLOW_FRAME_LOG_ENTRIES: int = 80
const SLOW_FRAME_THRESHOLD_USEC: int = 8000
const TRACE_EXPORT_LIMIT: int = 120

var _world: ZeroAdRtsLabWorld = null
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
var _max_step_tick: int = 0
var _total_step_usec: int = 0
var _measured_step_count: int = 0
var _event_log: Array[Dictionary] = []
var _slow_frame_log: Array[Dictionary] = []
var _last_export_path: String = ""


func _ready() -> void:
	_world = ZeroAdRtsLabWorld.new()
	_world.set_group_target(_world.current_target)
	_selected_unit_ids = _world.get_mobile_unit_ids()
	_hud = Label.new()
	_hud.position = Vector2(12.0, 10.0)
	_hud.z_index = 20
	add_child(_hud)
	_export_button = Button.new()
	_export_button.text = "Export log"
	_export_button.position = Vector2(606.0, 118.0)
	_export_button.custom_minimum_size = Vector2(102.0, 30.0)
	_export_button.z_index = 20
	_export_button.pressed.connect(_on_export_log_pressed)
	add_child(_export_button)
	_record_event("ready", {"selected_unit_ids": _selected_unit_ids})
	_update_hud()
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		var step_tick := _world.tick_count
		var step_start_usec := Time.get_ticks_usec()
		_world.step(minf(delta, 0.05))
		_last_step_usec = Time.get_ticks_usec() - step_start_usec
		if _last_step_usec > _max_step_usec:
			_max_step_usec = _last_step_usec
			_max_step_tick = step_tick
		_total_step_usec += _last_step_usec
		_measured_step_count += 1
		if _last_step_usec >= SLOW_FRAME_THRESHOLD_USEC:
			_record_slow_frame(step_tick, _last_step_usec, minf(delta, 0.05))
	_update_hud()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		_handle_mouse_button(mouse_button)
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed:
			return
		_handle_key(key_event.keycode)


func _input(event: InputEvent) -> void:
	if _is_dragging and event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		_drag_current = mouse_motion.position
		queue_redraw()


func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_1:
			_mode = ToolMode.COMMAND
			_last_action = "mode move/select"
			_record_event("mode", {"mode": _mode_name()})
		KEY_2:
			_mode = ToolMode.OBSTACLE
			_last_action = "mode obstacle"
			_record_event("mode", {"mode": _mode_name()})
		KEY_3:
			_mode = ToolMode.BLOCKER
			_last_action = "mode blocker"
			_record_event("mode", {"mode": _mode_name()})
		KEY_4:
			_mode = ToolMode.ERASE
			_last_action = "mode erase"
			_record_event("mode", {"mode": _mode_name()})
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
			_world.set_group_target(_world.current_target)
			_selected_unit_ids = _world.get_mobile_unit_ids()
			_reset_perf_metrics()
			_last_action = "reset"
			_record_event("reset", {"selected_unit_ids": _selected_unit_ids})
		KEY_SPACE:
			_paused = not _paused
			_last_action = "paused" if _paused else "resumed"
			_record_event("pause_toggle", {"paused": _paused})
	_update_hud()
	queue_redraw()


func _handle_mouse_button(mouse_button: InputEventMouseButton) -> void:
	if _mode == ToolMode.COMMAND:
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_drag_start = mouse_button.position
				_drag_current = mouse_button.position
				_is_dragging = true
			else:
				_finish_selection(mouse_button.position)
			queue_redraw()
			return
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			_move_selection(mouse_button.position)
			queue_redraw()
			return

	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	match _mode:
		ToolMode.OBSTACLE:
			var obstacle_id := _world.add_static_obstacle(mouse_button.position, OBSTACLE_SIZE)
			_last_action = "placed %s" % obstacle_id
			_record_event("place_obstacle", {
				"id": obstacle_id,
				"position": mouse_button.position,
			})
		ToolMode.BLOCKER:
			var blocker_id := _world.add_blocker(mouse_button.position)
			_last_action = "placed %s" % blocker_id
			_record_event("place_blocker", {
				"id": blocker_id,
				"position": mouse_button.position,
			})
		ToolMode.ERASE:
			var removed_id := _world.remove_nearest_editable(mouse_button.position)
			_last_action = "removed %s" % removed_id if removed_id != "" else "nothing to erase"
			_record_event("erase", {
				"removed_id": removed_id,
				"position": mouse_button.position,
			})
	_update_hud()
	queue_redraw()


func _finish_selection(position: Vector2) -> void:
	_is_dragging = false
	var drag_dist := position.distance_to(_drag_start)
	if drag_dist <= DRAG_SELECT_THRESHOLD:
		var picked_id := _world.get_mobile_unit_at(position)
		var picked_ids: Array[String] = []
		if picked_id != "":
			picked_ids.append(picked_id)
		_selected_unit_ids = picked_ids
	else:
		_selected_unit_ids = _world.get_mobile_units_in_rect(_rect_from_points(_drag_start, position))
	_last_action = "selected %d" % _selected_unit_ids.size()
	_record_event("select", {
		"position": position,
		"selected_unit_ids": _selected_unit_ids,
	})


func _move_selection(position: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		_selected_unit_ids = _world.get_mobile_unit_ids()
	_world.set_units_target(_selected_unit_ids, position)
	_last_action = "move %d units" % _selected_unit_ids.size()
	_record_event("move", {
		"position": position,
		"selected_unit_ids": _selected_unit_ids,
	})


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
		printerr("ZERO_AD_RTS_LAB_EXPORT_LOG_FAIL: %s" % target_path)
		return ""
	file.store_string(JSON.stringify(_json_safe(_build_export_snapshot()), "\t"))
	file.close()
	_last_export_path = global_path
	_last_action = "exported log"
	print("ZERO_AD_RTS_LAB_EXPORT_LOG: %s" % _last_export_path)
	_update_hud()
	return _last_export_path


func _on_export_log_pressed() -> void:
	export_debug_log()


func _draw() -> void:
	if _world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, _world.map_size), Color(0.08, 0.10, 0.11), true)
	_draw_grid()
	for obstacle in _world.obstacles:
		var rect: Rect2 = obstacle.get_rect()
		draw_rect(rect.grow(_world.pathfinder.default_clearance), Color(0.95, 0.70, 0.25, 0.16), true)
		draw_rect(rect, Color(0.38, 0.35, 0.30), true)
		draw_rect(rect, Color(0.78, 0.67, 0.45), false, 2.0)
	draw_circle(_world.current_target, 7.0, Color(0.2, 0.95, 0.65))
	if _mode == ToolMode.OBSTACLE:
		var mouse_pos := get_local_mouse_position()
		var preview_rect := Rect2(mouse_pos - OBSTACLE_SIZE * 0.5, OBSTACLE_SIZE)
		draw_rect(preview_rect, Color(0.95, 0.70, 0.25, 0.20), true)
		draw_rect(preview_rect, Color(0.95, 0.70, 0.25), false, 1.0)
	elif _mode == ToolMode.BLOCKER:
		draw_circle(get_local_mouse_position(), 14.0, Color(1.0, 0.28, 0.2, 0.24))
		draw_arc(get_local_mouse_position(), 14.0, 0.0, TAU, 24, Color(1.0, 0.40, 0.25), 1.5)

	for unit in _world.units:
		_draw_unit_trace(unit)
		_draw_waypoint_path(unit.long_path, unit.position, Color(0.45, 0.75, 1.0, 0.45))
		_draw_waypoint_path(unit.short_path, unit.position, Color(0.2, 1.0, 0.55, 0.75))

	for unit in _world.units:
		var fill := Color(0.18, 0.55, 0.95) if unit.group_id == "blue" else Color(0.90, 0.26, 0.22)
		if not unit.mobile:
			fill = Color(0.90, 0.45, 0.25)
		draw_circle(unit.position, unit.radius, fill)
		draw_arc(unit.position, unit.radius, 0.0, TAU, 24, Color(0.95, 0.95, 0.92), 1.5)
		if unit.was_obstructed:
			draw_arc(unit.position, unit.radius + 2.5, 0.0, TAU, 24, Color(1.0, 0.2, 0.15), 2.0)
		if _selected_unit_ids.has(unit.id):
			draw_arc(unit.position, unit.radius + 5.0, 0.0, TAU, 32, Color(0.25, 1.0, 0.70), 2.5)

	if _is_dragging and _mode == ToolMode.COMMAND:
		var select_rect := _rect_from_points(_drag_start, _drag_current)
		draw_rect(select_rect, Color(0.20, 0.70, 1.0, 0.15), true)
		draw_rect(select_rect, Color(0.35, 0.85, 1.0), false, 1.5)


func _draw_grid() -> void:
	var step: float = _world.pathfinder.cell_size
	var grid_color := Color(0.33, 0.37, 0.39, 0.35)
	var x := 0.0
	while x <= _world.map_size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, _world.map_size.y), grid_color, 1.0)
		x += step
	var y := 0.0
	while y <= _world.map_size.y:
		draw_line(Vector2(0.0, y), Vector2(_world.map_size.x, y), grid_color, 1.0)
		y += step


func _draw_unit_trace(unit: ZeroAdRtsLabUnit) -> void:
	for i in range(1, unit.trace.size()):
		draw_line(unit.trace[i - 1], unit.trace[i], Color(0.45, 0.75, 1.0, 0.24), 1.0)


func _draw_waypoint_path(path: SimNavWaypointPath, start: Vector2, color: Color) -> void:
	if path == null or path.waypoints.is_empty():
		return
	var previous := start
	for i in range(path.waypoints.size() - 1, -1, -1):
		var point := path.waypoints[i]
		draw_line(previous, point, color, 2.0)
		draw_circle(point, 3.0, color)
		previous = point


func _update_hud() -> void:
	if _hud == null or _world == null:
		return
	var metrics := _world.get_metrics()
	var avg_step_msec := float(_total_step_usec) / float(maxi(_measured_step_count, 1)) / 1000.0
	_hud.text = "0AD RTS pathfinding lab | mode %s | 1 move/select  2 obstacle  3 blocker  4 erase  A all  C clear traces\nselected %d | last: %s | R reset | Space %s\narrived %d/%d active %d pathless %d  short %d  long %d  queue p/r/proc %d/%d/%d\nblocked %d  fail %d  obs/vobs %d/%d  suppress %d  stale %d  imperfect %d/%d\npush ok/reject %d/%d  pair checks %d  buckets %d  static %.0f\nworld.step %.2fms  avg %.2fms  max %.2fms@%d%s" % [
		_mode_name(),
		_selected_unit_ids.size(),
		_last_action,
		"resume" if _paused else "pause",
		int(metrics.get("arrived_count", 0)),
		int(metrics.get("mobile_count", 0)),
		int(metrics.get("active_count", 0)),
		int(metrics.get("pathless_active_count", 0)),
		int(metrics.get("short_path_requests", 0)),
		int(metrics.get("long_path_requests", 0)),
		int(metrics.get("path_queue_pending", 0)),
		int(metrics.get("path_queue_results", 0)),
		int(metrics.get("path_queue_processed", 0)),
		int(metrics.get("blocked_moves", 0)),
		int(metrics.get("move_failures", 0)),
		int(metrics.get("obstructed_notifications", 0)),
		int(metrics.get("very_obstructed_notifications", 0)),
		int(metrics.get("repath_suppressed", 0)),
		int(metrics.get("obsolete_path_requests", 0)),
		int(metrics.get("known_imperfect_paths", 0)),
		int(metrics.get("known_imperfect_suppressed", 0)),
		int(metrics.get("applied_pushes", 0)),
		int(metrics.get("rejected_pushes", 0)),
		int(metrics.get("push_pair_checks", 0)),
		int(metrics.get("push_grid_cells", 0)),
		float(metrics.get("static_violation", 0.0)),
		float(_last_step_usec) / 1000.0,
		avg_step_msec,
		float(_max_step_usec) / 1000.0,
		_max_step_tick,
		" | exported %s" % _last_export_path if _last_export_path != "" else "",
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
	var rect_pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var rect_end := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(rect_pos, rect_end - rect_pos)


func _reset_perf_metrics() -> void:
	_last_step_usec = 0
	_max_step_usec = 0
	_max_step_tick = 0
	_total_step_usec = 0
	_measured_step_count = 0
	_slow_frame_log.clear()
	_last_export_path = ""


func _ensure_log_dir() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		_last_action = "export failed"
		printerr("ZERO_AD_RTS_LAB_EXPORT_LOG_FAIL: cannot open user://")
		return false
	var err := dir.make_dir_recursive("zero_ad_rts_pathfinding_lab_logs")
	if err != OK:
		_last_action = "export failed"
		printerr("ZERO_AD_RTS_LAB_EXPORT_LOG_FAIL: mkdir error %d" % err)
		return false
	return true


func _default_export_path() -> String:
	var timestamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	return "%s/zero_ad_rts_lab_%s_tick_%d.json" % [
		LOG_DIR,
		timestamp,
		_world.tick_count,
	]


func _build_export_snapshot() -> Dictionary:
	var avg_step_usec := float(_total_step_usec) / float(maxi(_measured_step_count, 1))
	return {
		"schema": "zero_ad_rts_pathfinding_lab_debug_log_v2",
		"exported_at": Time.get_datetime_string_from_system(false, false),
		"scene": "addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/frontend/zero_ad_rts_pathfinding_lab.tscn",
		"mode": _mode_name(),
		"paused": _paused,
		"last_action": _last_action,
		"selected_unit_ids": _selected_unit_ids.duplicate(),
		"current_target": _vector_snapshot(_world.current_target),
		"map_size": _vector_snapshot(_world.map_size),
		"perf": {
			"last_step_usec": _last_step_usec,
			"max_step_usec": _max_step_usec,
			"max_step_tick": _max_step_tick,
			"avg_step_usec": avg_step_usec,
			"measured_step_count": _measured_step_count,
			"slow_frame_threshold_usec": SLOW_FRAME_THRESHOLD_USEC,
		},
		"world": {
			"tick_count": _world.tick_count,
			"metrics": _world.get_metrics(),
			"last_step_profile": _world.last_step_profile,
			"recent_step_profiles": _world.recent_step_profiles.duplicate(true),
		},
		"pathfinder": {
			"last_report": _world.pathfinder.last_report,
		},
		"obstacles": _snapshot_obstacles(),
		"units": _snapshot_units(),
		"recent_path_decisions": _world.motion.recent_path_decisions(),
		"recent_pair_contacts": _world.recent_pair_contacts.duplicate(true),
		"recent_motion_updates": _world.recent_motion_updates.duplicate(true),
		"recent_events": _event_log.duplicate(true),
		"slow_frames": _slow_frame_log.duplicate(true),
	}


func _snapshot_obstacles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obstacle in _world.obstacles:
		result.append({
			"id": obstacle.id,
			"center": _vector_snapshot(obstacle.center),
			"size": _vector_snapshot(obstacle.size),
			"rect": _rect_snapshot(obstacle.get_rect()),
			"inflated_rect": _rect_snapshot(obstacle.get_rect().grow(_world.pathfinder.default_clearance)),
		})
	return result


func _snapshot_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in _world.units:
		result.append({
			"id": unit.id,
			"group_id": unit.group_id,
			"control_group_id": unit.control_group_id,
			"mobile": unit.mobile,
			"blocks_pathfinding": unit.blocks_pathfinding,
			"position": _vector_snapshot(unit.position),
			"target": _vector_snapshot(unit.target),
			"path_target": _vector_snapshot(unit.path_target),
			"radius": unit.radius,
			"speed": unit.speed,
			"arrived": unit.arrived,
			"move_failed": unit.move_failed,
			"has_move_order": unit.has_move_order,
			"active_order_id": unit.active_order_id(),
			"current_order": unit.current_order_snapshot(),
			"last_order": unit.last_order_snapshot(),
			"obstruction_state": unit.obstruction_state,
			"failed_movements": unit.failed_movements,
			"pushing_pressure": unit.pushing_pressure,
			"follow_known_imperfect_path_countdown": unit.follow_known_imperfect_path_countdown,
			"pending_long_ticket": unit.pending_long_ticket,
			"pending_short_ticket": unit.pending_short_ticket,
			"long_path_size": unit.long_path.size() if unit.long_path != null else 0,
			"short_path_size": unit.short_path.size() if unit.short_path != null else 0,
			"long_path": _waypoint_path_snapshot(unit.long_path),
			"short_path": _waypoint_path_snapshot(unit.short_path),
			"trace_tail": _packed_vector_snapshot(unit.trace, TRACE_EXPORT_LIMIT),
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
		"max_step_tick": _max_step_tick,
		"data": _json_safe(data),
	})
	while _event_log.size() > MAX_EVENT_LOG_ENTRIES:
		_event_log.pop_front()


func _record_slow_frame(tick: int, step_usec: int, delta: float) -> void:
	if _world == null:
		return
	_slow_frame_log.append({
		"tick": tick,
		"step_usec": step_usec,
		"delta": delta,
		"last_action": _last_action,
		"selected_unit_ids": _selected_unit_ids.duplicate(),
		"world_metrics": _world.get_metrics(),
		"world_step_profile": _world.last_step_profile.duplicate(true),
		"pathfinder_last_report": _world.pathfinder.last_report.duplicate(true),
		"recent_path_decisions_tail": _tail_dictionaries(_world.motion.recent_path_decisions(), 24),
		"recent_pair_contacts_tail": _tail_dictionaries(_world.recent_pair_contacts, 16),
		"unit_snapshots": _snapshot_units(),
	})
	while _slow_frame_log.size() > MAX_SLOW_FRAME_LOG_ENTRIES:
		_slow_frame_log.pop_front()


func _tail_dictionaries(entries: Array, limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index := maxi(entries.size() - limit, 0)
	for i in range(start_index, entries.size()):
		var entry: Dictionary = entries[i] as Dictionary
		result.append(entry.duplicate(true))
	return result


func _waypoint_path_snapshot(path: SimNavWaypointPath) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if path == null:
		return result
	for point in path.waypoints:
		result.append(_vector_snapshot(point))
	return result


func _packed_vector_snapshot(points: PackedVector2Array, limit: int) -> Array[Dictionary]:
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
			var vector_value: Vector2 = value as Vector2
			return _vector_snapshot(vector_value)
		TYPE_VECTOR2I:
			var vector_i_value: Vector2i = value as Vector2i
			return {
				"x": vector_i_value.x,
				"y": vector_i_value.y,
			}
		TYPE_RECT2:
			var rect_value: Rect2 = value as Rect2
			return _rect_snapshot(rect_value)
		TYPE_PACKED_VECTOR2_ARRAY:
			var packed_points: PackedVector2Array = value as PackedVector2Array
			return _packed_vector_snapshot(packed_points, packed_points.size())
		TYPE_ARRAY:
			var array_value: Array = value as Array
			var safe_array: Array = []
			for item in array_value:
				safe_array.append(_json_safe(item))
			return safe_array
		TYPE_DICTIONARY:
			var dict_value: Dictionary = value as Dictionary
			var safe_dict: Dictionary = {}
			for key in dict_value.keys():
				safe_dict[str(key)] = _json_safe(dict_value[key])
			return safe_dict
		_:
			return str(value)
