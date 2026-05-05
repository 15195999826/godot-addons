extends Node2D


const LabWorld := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

enum ToolMode {
	COMMAND,
	OBSTACLE,
	BLOCKER,
	ERASE,
}

const DRAG_SELECT_THRESHOLD: float = 5.0
const OBSTACLE_SIZE: Vector2 = Vector2(74.0, 74.0)

var _world: RtsPathfindingLabWorld = null
var _paused: bool = false
var _hud: Label = null
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


func _ready() -> void:
	_world = LabWorld.new()
	_world.setup_default()
	_selected_unit_ids = _world.get_mobile_unit_ids()
	_hud = Label.new()
	_hud.position = Vector2(12.0, 10.0)
	add_child(_hud)
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		var step_start_usec := Time.get_ticks_usec()
		_world.step(minf(delta, 0.05))
		_last_step_usec = Time.get_ticks_usec() - step_start_usec
		_max_step_usec = maxi(_max_step_usec, _last_step_usec)
		_total_step_usec += _last_step_usec
		_measured_step_count += 1
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
			KEY_C:
				_world.clear_traces()
				_last_action = "cleared traces"
			KEY_R:
				_world.setup_default()
				_selected_unit_ids = _world.get_mobile_unit_ids()
				_reset_perf_metrics()
				_last_action = "reset"
			KEY_SPACE:
				_paused = not _paused
			KEY_G:
				_world.group_filter_enabled = not _world.group_filter_enabled
				_world.set_group_target(_world.current_target)
			KEY_D:
				_world.avoid_moving_units_enabled = not _world.avoid_moving_units_enabled
				_world.set_group_target(_world.current_target)
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
		ToolMode.BLOCKER:
			var blocker_id := _world.add_blocker(mb.position)
			_last_action = "placed %s" % blocker_id
		ToolMode.ERASE:
			var removed_id := _world.remove_nearest_editable(mb.position)
			_last_action = "removed %s" % removed_id if removed_id != "" else "nothing to erase"
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


func _move_selection(pos: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		_selected_unit_ids = _world.get_mobile_unit_ids()
	_world.set_units_target(_selected_unit_ids, pos)
	_last_action = "move %d units" % _selected_unit_ids.size()


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
