extends Node2D

# Dota2 RTS Pathfinding Lab — manual frontend.
#
# Layer 1 scope (per README): expose the motion controller to a human so edge
# cases can be probed (narrow gaps, target spam, body-blocking own units).
# Keeps perf tracing and log export deliberately out of scope — this is for
# feel and visual validation, not benchmarking.

enum ToolMode {
	COMMAND,
	OBSTACLE,
	BLOCKER,
	ERASE,
}

const DRAG_SELECT_THRESHOLD := 5.0
const OBSTACLE_SIZE := Vector2(64.0, 64.0)

const UNIT_COLOR_BLUE := Color(0.35, 0.62, 1.0)
const UNIT_COLOR_RED := Color(0.95, 0.40, 0.35)
const UNIT_COLOR_SELECTED := Color(1.0, 0.95, 0.30)
const OBSTACLE_COLOR := Color(0.50, 0.50, 0.55, 1.0)
const PATH_COLOR := Color(0.55, 0.95, 0.55, 0.75)
const TARGET_COLOR := Color(0.95, 0.80, 0.30, 0.75)
const TRACE_COLOR := Color(0.25, 0.55, 0.95, 0.55)
const DRAG_RECT_COLOR := Color(1.0, 0.95, 0.30, 0.18)
const DRAG_RECT_OUTLINE := Color(1.0, 0.95, 0.30, 0.80)

const STATE_COLOR := {
	"IDLE":          Color(0.65, 0.65, 0.65),
	"WAITING_LONG":  Color(1.00, 0.55, 0.20),
	"FOLLOWING":     Color(0.50, 0.95, 0.50),
	"WAITING_SHORT": Color(0.95, 0.80, 0.30),
	"FAILED":        Color(0.95, 0.30, 0.30),
}


var _world: Dota2LabWorld = null
var _paused: bool = false
var _hud: Label = null
var _mode: int = ToolMode.COMMAND
var _selected_unit_ids: Array[String] = []
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _last_action: String = "ready"


func _ready() -> void:
	_world = Dota2LabWorld.new()
	_selected_unit_ids = _world.get_mobile_unit_ids()
	_hud = Label.new()
	_hud.position = Vector2(12.0, 10.0)
	_hud.z_index = 20
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hud)
	_update_hud()
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		_world.step(minf(delta, 0.05))
	_update_hud()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed:
			return
		_handle_key(key_event.keycode)


func _input(event: InputEvent) -> void:
	if _is_dragging and event is InputEventMouseMotion:
		_drag_current = (event as InputEventMouseMotion).position
		queue_redraw()


# ─────────────────────────── Input handlers ──────────────────────────────────

func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_1:
			_mode = ToolMode.COMMAND
			_last_action = "mode COMMAND"
		KEY_2:
			_mode = ToolMode.OBSTACLE
			_last_action = "mode OBSTACLE"
		KEY_3:
			_mode = ToolMode.BLOCKER
			_last_action = "mode BLOCKER"
		KEY_4:
			_mode = ToolMode.ERASE
			_last_action = "mode ERASE"
		KEY_A:
			_selected_unit_ids = _world.get_mobile_unit_ids()
			_last_action = "selected all (%d)" % _selected_unit_ids.size()
		KEY_C:
			_world.clear_traces()
			_last_action = "cleared traces"
		KEY_R:
			_world = Dota2LabWorld.new()
			_selected_unit_ids = _world.get_mobile_unit_ids()
			_last_action = "reset scene"
		KEY_SPACE:
			_paused = not _paused
			_last_action = "paused" if _paused else "resumed"
	_update_hud()
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

	# Edit modes only act on left-button press.
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
			_last_action = "removed %s" % removed_id if removed_id != "" else "erase: nothing nearby"
	_update_hud()
	queue_redraw()


func _finish_selection(end_pos: Vector2) -> void:
	_is_dragging = false
	var drag_dist := end_pos.distance_to(_drag_start)
	if drag_dist <= DRAG_SELECT_THRESHOLD:
		var picked := _world.get_mobile_unit_at(end_pos)
		_selected_unit_ids = []
		if picked != "":
			_selected_unit_ids.append(picked)
	else:
		_selected_unit_ids = _world.get_mobile_units_in_rect(_rect_from_points(_drag_start, end_pos))
	_last_action = "selected %d" % _selected_unit_ids.size()


func _move_selection(target: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		# No selection ⇒ command all mobile units (per README convention).
		_world.issue_move_all_mobile(target)
		_last_action = "move all → %s" % str(target)
		return
	_world.issue_move_ids(_selected_unit_ids, target)
	_last_action = "move %d → %s" % [_selected_unit_ids.size(), str(target)]


# ─────────────────────────── Rendering ───────────────────────────────────────

func _draw() -> void:
	# Map background (within playable bounds).
	draw_rect(Rect2(Vector2.ZERO, _world.map_size), Color(0.10, 0.12, 0.16), true)

	# Static obstacles.
	for obstacle in _world.obstacles:
		var rect := Rect2(obstacle.center - obstacle.size * 0.5, obstacle.size)
		draw_rect(rect, OBSTACLE_COLOR, true)
		draw_rect(rect, OBSTACLE_COLOR.darkened(0.4), false, 1.5)

	# Unit traces.
	for unit in _world.units:
		if unit.trace.size() < 2:
			continue
		for i in range(unit.trace.size() - 1):
			draw_line(unit.trace[i], unit.trace[i + 1], TRACE_COLOR, 1.2)

	# Selected units' current paths.
	for unit_id in _selected_unit_ids:
		var unit := _world.get_unit(unit_id)
		if unit == null or not unit.has_path():
			continue
		var prev := unit.position
		# Path waypoints are stored in reverse-consumption order; back() is next.
		# Walk from back to front for visual order.
		var path := unit.path
		var pts: Array[Vector2] = []
		for i in range(path.size() - 1, -1, -1):
			pts.append(path.waypoints[i])
		for p in pts:
			draw_line(prev, p, PATH_COLOR, 2.0)
			prev = p

	# Units.
	for unit in _world.units:
		var color := UNIT_COLOR_BLUE if unit.group_id == "blue" else UNIT_COLOR_RED
		draw_circle(unit.position, unit.radius, color)
		if _selected_unit_ids.has(unit.id):
			draw_arc(unit.position, unit.radius + 3.0, 0.0, TAU, 32, UNIT_COLOR_SELECTED, 2.0)
		# State indicator: a small ring at top-right of unit.
		var state_color: Color = STATE_COLOR.get(unit.state, Color.WHITE)
		draw_circle(unit.position + Vector2(unit.radius + 4.0, -unit.radius - 4.0), 3.0, state_color)
		# Move target marker for active orders.
		if unit.state != Dota2LabUnit.STATE_IDLE and unit.state != Dota2LabUnit.STATE_FAILED:
			draw_line(unit.position, unit.move_target, TARGET_COLOR, 0.8)

	# Drag selection rectangle.
	if _is_dragging:
		var drag_rect := _rect_from_points(_drag_start, _drag_current)
		draw_rect(drag_rect, DRAG_RECT_COLOR, true)
		draw_rect(drag_rect, DRAG_RECT_OUTLINE, false, 1.0)


# ─────────────────────────── HUD ─────────────────────────────────────────────

func _update_hud() -> void:
	if _hud == null:
		return
	var metrics := _world.get_metrics()
	var state_counts: Dictionary = metrics.get("state_counts", {})
	var pf: Dictionary = metrics.get("pathfinder", {})
	var lines := [
		"Dota2 RTS Pathfinding Lab (Layer 1)",
		"Mode: %s   %s" % [_mode_name(), "[PAUSED]" if _paused else ""],
		"Action: %s" % _last_action,
		"Selected: %d   Tick: %d" % [_selected_unit_ids.size(), metrics.get("tick_count", 0)],
		"",
		"State counts:",
		"  IDLE          %d" % int(state_counts.get("IDLE", 0)),
		"  WAITING_LONG  %d" % int(state_counts.get("WAITING_LONG", 0)),
		"  FOLLOWING     %d" % int(state_counts.get("FOLLOWING", 0)),
		"  WAITING_SHORT %d" % int(state_counts.get("WAITING_SHORT", 0)),
		"  FAILED        %d" % int(state_counts.get("FAILED", 0)),
		"",
		"Path requests: L=%d S=%d   blocks: U=%d S=%d" % [
			metrics.get("long_path_requests", 0),
			metrics.get("short_path_requests", 0),
			metrics.get("blocked_by_unit_count", 0),
			metrics.get("blocked_by_static_count", 0),
		],
		"Reached: %d   Failed: %d   RetryMax: %d" % [
			metrics.get("reached_goal_count", 0),
			metrics.get("move_failed_count", 0),
			metrics.get("retry_count_max", 0),
		],
		"Queue: pending=%d result=%d processed=%d  PendingPeak=%d" % [
			int(pf.get("pending_count", 0)),
			int(pf.get("result_count", 0)),
			int(pf.get("processed_count", 0)),
			metrics.get("pending_count_peak", 0),
		],
		"",
		"Keys: 1 cmd  2 obstacle  3 blocker  4 erase  A select-all  C clear-traces  R reset  Space pause",
	]
	_hud.text = "\n".join(lines)


# ─────────────────────────── Helpers ─────────────────────────────────────────

func _mode_name() -> String:
	match _mode:
		ToolMode.COMMAND:  return "COMMAND"
		ToolMode.OBSTACLE: return "OBSTACLE"
		ToolMode.BLOCKER:  return "BLOCKER"
		ToolMode.ERASE:    return "ERASE"
	return "?"


func _rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var topleft := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size := Vector2(absf(b.x - a.x), absf(b.y - a.y))
	return Rect2(topleft, size)
