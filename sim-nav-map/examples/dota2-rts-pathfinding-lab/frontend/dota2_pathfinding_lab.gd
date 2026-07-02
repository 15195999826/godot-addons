extends Node2D

# Dota2 RTS Pathfinding Lab — manual frontend.
#
# Layer 1 scope (per README): expose the motion controller to a human so edge
# cases can be probed (narrow gaps, target spam, body-blocking own units).
# Mirrors the 0AD lab's operation/debug surface closely enough that manual
# findings can be exported and turned into smoke tests.

enum ToolMode {
	COMMAND,
	OBSTACLE,
	BLOCKER,
	ERASE,
}

const DRAG_SELECT_THRESHOLD: float = 5.0
const OBSTACLE_SIZE: Vector2 = Vector2(64.0, 64.0)
const LOG_DIR: String = "user://dota2_rts_pathfinding_lab_logs"
const MAX_EVENT_LOG_ENTRIES: int = 160
const MAX_SLOW_FRAME_LOG_ENTRIES: int = 80
const SLOW_FRAME_THRESHOLD_USEC: int = 8000
const TRACE_EXPORT_LIMIT: int = 120
const PANEL_GAP: float = 24.0
const PANEL_WIDTH: float = 520.0
const PANEL_PADDING: float = 20.0
const AUTO_DEMO_RESET_DELAY_TICKS: int = 120
const Dota2LabSceneAgentOpsScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/frontend/dota2_lab_scene_agent_ops.gd")
const DevAgentBridgeScript := preload("res://addons/lomolib/dev_agent/dev_agent_bridge.gd")
const AiCommandSourceScript := preload("res://addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/logic/dota2_lab_ai_command_source.gd")

# Mobile units are colored by speed tier so body-block interactions between
# tiers read at a glance.
const UNIT_COLOR_SLOW := Color(0.87, 0.62, 0.20)
const UNIT_COLOR_MID := Color(0.18, 0.55, 0.95)
const UNIT_COLOR_FAST := Color(0.72, 0.40, 0.95)
const UNIT_COLOR_BLOCKER := Color(0.90, 0.45, 0.25)
const UNIT_COLOR_SELECTED := Color(0.25, 1.0, 0.70)
const SPEED_TIER_SLOW_MAX := 85.0
const SPEED_TIER_FAST_MIN := 140.0
const UNIT_OUTLINE_COLOR := Color(0.95, 0.95, 0.92)
const FACING_ARROW_COLOR := Color(1.00, 0.94, 0.42)
const OBSTACLE_COLOR := Color(0.38, 0.35, 0.30)
const OBSTACLE_OUTLINE_COLOR := Color(0.78, 0.67, 0.45)
const OBSTACLE_CLEARANCE_COLOR := Color(0.95, 0.70, 0.25, 0.16)
const PATH_COLOR := Color(0.20, 1.00, 0.55, 0.75)
const TARGET_COLOR := Color(0.2, 0.95, 0.65)
const TRACE_COLOR := Color(0.45, 0.75, 1.0, 0.24)
const DRAG_RECT_COLOR := Color(0.20, 0.70, 1.0, 0.15)
const DRAG_RECT_OUTLINE := Color(0.35, 0.85, 1.0)

const STATE_COLOR := {
	"IDLE":   Color(0.65, 0.65, 0.65),
	"MOVING": Color(0.50, 0.95, 0.50),
}

@export var auto_command_demo: bool = false
@export var auto_demo_loop: bool = true


var _world: Dota2LabWorld = null
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
var _dev_agent_bridge = null
var _ai_command_source = null
var _auto_demo_run_index: int = 0
var _auto_demo_reset_countdown: int = -1


func _ready() -> void:
	if auto_command_demo:
		_reset_auto_demo()
	else:
		_world = Dota2LabWorld.new()
	_selected_unit_ids = _world.get_mobile_unit_ids()
	_hud = Label.new()
	_hud.position = _debug_panel_origin() + Vector2(PANEL_PADDING, PANEL_PADDING)
	_hud.z_index = 20
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hud)
	_export_button = Button.new()
	_export_button.text = "Export log"
	_export_button.position = _debug_panel_origin() + Vector2(PANEL_WIDTH - 132.0, PANEL_PADDING)
	_export_button.custom_minimum_size = Vector2(112.0, 32.0)
	_export_button.z_index = 20
	_export_button.pressed.connect(_on_export_log_pressed)
	add_child(_export_button)
	_record_event("ready", {"selected_unit_ids": _selected_unit_ids})
	_install_dev_agent()
	_update_hud()
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		_tick_auto_demo()
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
		_update_auto_demo_loop()
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
			_record_event("mode", {"mode": _mode_name()})
		KEY_2:
			_mode = ToolMode.OBSTACLE
			_last_action = "mode OBSTACLE"
			_record_event("mode", {"mode": _mode_name()})
		KEY_3:
			_mode = ToolMode.BLOCKER
			_last_action = "mode BLOCKER"
			_record_event("mode", {"mode": _mode_name()})
		KEY_4:
			_mode = ToolMode.ERASE
			_last_action = "mode ERASE"
			_record_event("mode", {"mode": _mode_name()})
		KEY_A:
			_selected_unit_ids = _world.get_mobile_unit_ids()
			_last_action = "selected all (%d)" % _selected_unit_ids.size()
			_record_event("select_all", {"selected_unit_ids": _selected_unit_ids})
		KEY_C:
			_world.clear_traces()
			_last_action = "cleared traces"
			_record_event("clear_traces", {})
		KEY_E:
			export_debug_log()
		KEY_R:
			_reset_scene()
		KEY_SPACE:
			_paused = not _paused
			_last_action = "paused" if _paused else "resumed"
			_record_event("pause_toggle", {"paused": _paused})
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
			_record_event("place_obstacle", {
				"id": obstacle_id,
				"position": mb.position,
			})
		ToolMode.BLOCKER:
			var blocker_id := _world.add_blocker(mb.position)
			_last_action = "placed %s" % blocker_id
			_record_event("place_blocker", {
				"id": blocker_id,
				"position": mb.position,
			})
		ToolMode.ERASE:
			var removed_id := _world.remove_nearest_editable(mb.position)
			_last_action = "removed %s" % removed_id if removed_id != "" else "erase: nothing nearby"
			_record_event("erase", {
				"removed_id": removed_id,
				"position": mb.position,
			})
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
	_record_event("select", {
		"position": end_pos,
		"selected_unit_ids": _selected_unit_ids,
	})


func _move_selection(target: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		# No selection ⇒ command all mobile units (per README convention).
		_world.issue_move_all_mobile(target)
		_last_action = "move all → %s" % str(target)
		_record_event("move_all", {"position": target})
		return
	_world.issue_move_ids(_selected_unit_ids, target)
	_last_action = "move %d → %s" % [_selected_unit_ids.size(), str(target)]
	_record_event("move", {
		"position": target,
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
		printerr("DOTA2_RTS_LAB_EXPORT_LOG_FAIL: %s" % target_path)
		return ""
	file.store_string(JSON.stringify(_json_safe(_build_export_snapshot()), "\t"))
	file.close()
	_last_export_path = global_path
	_last_action = "exported log"
	print("DOTA2_RTS_LAB_EXPORT_LOG: %s" % _last_export_path)
	_update_hud()
	return _last_export_path


func get_dev_agent_state() -> Dictionary:
	if _world == null:
		return {}

	return {
		"mode": _mode_name(),
		"paused": _paused,
		"last_action": _last_action,
		"selected_unit_ids": _selected_unit_ids.duplicate(),
		"current_target": _vector_snapshot(_world.current_target),
		"tick_count": _world.tick_count,
		"unit_count": _world.units.size(),
		"obstacle_count": _world.obstacles.size(),
		"failed_unit_ids": _failed_unit_ids(),
		"last_export_path": _last_export_path,
		"perf": {
			"last_step_usec": _last_step_usec,
			"max_step_usec": _max_step_usec,
			"max_step_tick": _max_step_tick,
			"measured_step_count": _measured_step_count,
		},
		"world_metrics": _world.get_metrics(),
		"pathfinder": _world.pathfinder.diagnostics(),
	}


func _install_dev_agent() -> void:
	var ops := Dota2LabSceneAgentOpsScript.new() as Node
	ops.name = "Dota2LabSceneAgentOps"
	add_child(ops)

	_dev_agent_bridge = DevAgentBridgeScript.new()
	_dev_agent_bridge.name = "DevAgentBridge"
	_dev_agent_bridge.scene_ops_path = NodePath("../Dota2LabSceneAgentOps")
	add_child(_dev_agent_bridge)
	call_deferred("_print_dev_agent_paths")


func _print_dev_agent_paths() -> void:
	if _dev_agent_bridge == null:
		return
	var info: Dictionary = _dev_agent_bridge.get_session_info() as Dictionary
	var inbox_path := str(info.get("inbox_global", ""))
	if inbox_path.is_empty():
		return
	print("[Dota2PathfindingLab DevAgent] inbox: %s" % inbox_path)
	print("[Dota2PathfindingLab DevAgent] outbox: %s" % str(info.get("outbox_global", "")))
	print("[Dota2PathfindingLab DevAgent] session_dir: %s" % str(info.get("session_dir_global", "")))


func _on_export_log_pressed() -> void:
	export_debug_log()


# ─────────────────────────── Rendering ───────────────────────────────────────

func _draw() -> void:
	if _world == null:
		return
	# Map background (within playable bounds).
	draw_rect(get_viewport_rect(), Color(0.045, 0.05, 0.055), true)
	draw_rect(Rect2(Vector2.ZERO, _world.map_size), Color(0.08, 0.10, 0.11), true)
	_draw_debug_panel_chrome()
	_draw_grid()

	# Static obstacles.
	for obstacle in _world.obstacles:
		var rect := Rect2(obstacle.center - obstacle.size * 0.5, obstacle.size)
		draw_rect(rect.grow(_world.pathfinder.default_clearance), OBSTACLE_CLEARANCE_COLOR, true)
		draw_rect(rect, OBSTACLE_COLOR, true)
		draw_rect(rect, OBSTACLE_OUTLINE_COLOR, false, 2.0)
	_draw_target_marker(_world.current_target)
	if _mode == ToolMode.OBSTACLE:
		var mouse_pos := get_local_mouse_position()
		var preview_rect := Rect2(mouse_pos - OBSTACLE_SIZE * 0.5, OBSTACLE_SIZE)
		draw_rect(preview_rect, Color(0.95, 0.70, 0.25, 0.20), true)
		draw_rect(preview_rect, Color(0.95, 0.70, 0.25), false, 1.0)
	elif _mode == ToolMode.BLOCKER:
		draw_circle(get_local_mouse_position(), Dota2LabWorld.DEFAULT_BLOCKER_RADIUS, Color(0.95, 0.28, 0.22, 0.24))
		draw_arc(get_local_mouse_position(), Dota2LabWorld.DEFAULT_BLOCKER_RADIUS, 0.0, TAU, 24, Color(0.95, 0.40, 0.25), 1.5)

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
		_draw_waypoint_path(unit.path, unit.position, PATH_COLOR)

	# Units.
	for unit in _world.units:
		var color := _unit_fill_color(unit)
		draw_circle(unit.position, unit.radius, color)
		draw_arc(unit.position, unit.radius, 0.0, TAU, 24, UNIT_OUTLINE_COLOR, 1.5)
		if _selected_unit_ids.has(unit.id):
			draw_arc(unit.position, unit.radius + 5.0, 0.0, TAU, 32, UNIT_COLOR_SELECTED, 2.5)
		if _order_failed_hard(unit) and unit.state == Dota2LabUnit.STATE_IDLE:
			draw_arc(unit.position, unit.radius + 4.5, 0.0, TAU, 32, Color(1.0, 0.18, 0.15, 0.90), 2.5)
			_draw_failed_glyph(unit.position - Vector2(0.0, unit.radius + 9.0))
		_draw_facing_arrow(unit)
		# State indicator: a small ring at top-right of unit.
		var state_color: Color = STATE_COLOR.get(unit.state, Color.WHITE)
		draw_circle(unit.position + Vector2(unit.radius + 4.0, -unit.radius - 4.0), 3.0, state_color)
		# Move target marker for active orders.
		if unit.state == Dota2LabUnit.STATE_MOVING:
			draw_line(unit.position, unit.effective_target, TARGET_COLOR, 0.8)

	# Drag selection rectangle.
	if _is_dragging:
		var drag_rect := _rect_from_points(_drag_start, _drag_current)
		draw_rect(drag_rect, DRAG_RECT_COLOR, true)
		draw_rect(drag_rect, DRAG_RECT_OUTLINE, false, 1.0)


func _draw_debug_panel_chrome() -> void:
	var panel_origin := _debug_panel_origin()
	var panel_size := Vector2(PANEL_WIDTH, _world.map_size.y)
	draw_rect(Rect2(panel_origin, panel_size), Color(0.07, 0.08, 0.10), true)
	draw_line(panel_origin, panel_origin + Vector2(0.0, panel_size.y), Color(0.18, 0.22, 0.26), 2.0)
	for y in [76.0, 292.0, 470.0, 620.0]:
		var start := panel_origin + Vector2(PANEL_PADDING, y)
		var end := panel_origin + Vector2(PANEL_WIDTH - PANEL_PADDING, y)
		draw_line(start, end, Color(0.18, 0.21, 0.24), 1.0)


func _draw_target_marker(center: Vector2) -> void:
	draw_circle(center, 7.0, TARGET_COLOR)
	draw_arc(center, 17.0, 0.0, TAU, 40, Color(0.2, 0.95, 0.65, 0.58), 1.5)
	draw_line(center + Vector2(-20.0, 0.0), center + Vector2(-10.0, 0.0), TARGET_COLOR, 1.5)
	draw_line(center + Vector2(10.0, 0.0), center + Vector2(20.0, 0.0), TARGET_COLOR, 1.5)
	draw_line(center + Vector2(0.0, -20.0), center + Vector2(0.0, -10.0), TARGET_COLOR, 1.5)
	draw_line(center + Vector2(0.0, 10.0), center + Vector2(0.0, 20.0), TARGET_COLOR, 1.5)


func _draw_grid() -> void:
	var step: float = _world.pathfinder.cell_size
	var major_step := step * 4.0
	var minor_grid_color := Color(0.32, 0.36, 0.39, 0.28)
	var major_grid_color := Color(0.42, 0.46, 0.48, 0.42)
	var x := 0.0
	while x <= _world.map_size.x:
		var x_is_major := fmod(x, major_step) < 0.01
		var x_color := major_grid_color if x_is_major else minor_grid_color
		var x_width := 1.35 if x_is_major else 1.0
		draw_line(Vector2(x, 0.0), Vector2(x, _world.map_size.y), x_color, x_width)
		x += step
	var y := 0.0
	while y <= _world.map_size.y:
		var y_is_major := fmod(y, major_step) < 0.01
		var y_color := major_grid_color if y_is_major else minor_grid_color
		var y_width := 1.35 if y_is_major else 1.0
		draw_line(Vector2(0.0, y), Vector2(_world.map_size.x, y), y_color, y_width)
		y += step


func _draw_failed_glyph(center: Vector2) -> void:
	var arm := 4.0
	var color := Color(1.0, 0.25, 0.18)
	var width := 2.0
	draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm), color, width)
	draw_line(center + Vector2(-arm, arm), center + Vector2(arm, -arm), color, width)


func _unit_fill_color(unit: Dota2LabUnit) -> Color:
	if not unit.mobile:
		return UNIT_COLOR_BLOCKER
	if unit.speed <= SPEED_TIER_SLOW_MAX:
		return UNIT_COLOR_SLOW
	if unit.speed >= SPEED_TIER_FAST_MIN:
		return UNIT_COLOR_FAST
	return UNIT_COLOR_MID


func _draw_facing_arrow(unit: Dota2LabUnit) -> void:
	var direction := Vector2(cos(unit.facing_angle_rad), sin(unit.facing_angle_rad))
	var start := unit.position + direction * maxf(unit.radius * 0.15, 2.0)
	var tip := unit.position + direction * (unit.radius + 9.0)
	var head_left := tip - direction.rotated(0.65) * 6.0
	var head_right := tip - direction.rotated(-0.65) * 6.0
	var turning := unit.is_moving() and unit.last_speed_factor < 0.5
	var color := Color(1.0, 0.45, 0.18) if turning else FACING_ARROW_COLOR
	draw_line(start, tip, color, 2.0)
	draw_line(tip, head_left, color, 2.0)
	draw_line(tip, head_right, color, 2.0)


func _draw_waypoint_path(path: SimNavWaypointPath, start: Vector2, color: Color) -> void:
	if path == null or path.waypoints.is_empty():
		return
	var previous := start
	for i in range(path.waypoints.size() - 1, -1, -1):
		var point := path.waypoints[i]
		draw_line(previous, point, color, 2.0)
		draw_circle(point, 3.0, color)
		previous = point


# ─────────────────────────── HUD ─────────────────────────────────────────────

func _update_hud() -> void:
	if _hud == null:
		return
	var metrics := _world.get_metrics()
	var state_counts: Dictionary = metrics.get("state_counts", {})
	var step_stats: Dictionary = metrics.get("last_step_stats", {})
	var pf: Dictionary = metrics.get("pathfinder", {})
	var avg_step_msec := float(_total_step_usec) / float(maxi(_measured_step_count, 1)) / 1000.0
	var failed_line := _format_failed_line()
	var selected_path_line := _format_selected_path_line()
	var title := "Dota2 RTS Pathfinding Lab (Layer 2 Demo)" if auto_command_demo else "Dota2 RTS Pathfinding Lab (Fable Motion)"
	var subtitle := "Automatic command-source demo" if auto_command_demo else "Manual motion debug surface"
	var auto_line := _format_auto_demo_line()
	var lines := [
		title,
		subtitle,
		"Mode: %s   %s" % [_mode_name(), "[PAUSED]" if _paused else ""],
		"Action: %s%s" % [
			_last_action,
			" | exported %s" % _last_export_path if _last_export_path != "" else "",
		],
		"Selected: %d   Tick: %d   Map: %dx%d" % [
			_selected_unit_ids.size(),
			metrics.get("tick_count", 0),
			int(_world.map_size.x),
			int(_world.map_size.y),
		],
		auto_line,
		"",
		"Motion",
		"IDLE %d   MOVING %d" % [
			int(state_counts.get("IDLE", 0)),
			int(state_counts.get("MOVING", 0)),
		],
		"Orders done %d   failed %d" % [
			int(metrics.get("orders_completed", 0)),
			int(metrics.get("orders_failed", 0)),
		],
		"Overlap residual %.2f   sep rounds %d" % [
			float(step_stats.get("max_residual_overlap", 0.0)),
			int(step_stats.get("separation_rounds", 0)),
		],
		"Plans %d   LOS checks %d" % [
			int(pf.get("plan_count", 0)),
			int(pf.get("line_check_count", 0)),
		],
		"Speed tiers: amber %.0f   blue %.0f   violet %.0f" % [
			Dota2LabWorld.SPEED_SLOW, Dota2LabWorld.SPEED_MID, Dota2LabWorld.SPEED_FAST,
		],
		selected_path_line,
		"",
		"Performance",
		"step %.2fms   avg %.2fms   max %.2fms @ tick %d" % [
			float(_last_step_usec) / 1000.0,
			avg_step_msec,
			float(_max_step_usec) / 1000.0,
			_max_step_tick,
		],
		"slow %d   events %d   motion updates %d" % [
			_slow_frame_log.size(),
			_event_log.size(),
			_world.recent_motion_updates.size(),
		],
		failed_line,
		"",
		"Controls",
		"1 command/select   Right click move",
		"2 obstacle   3 blocker   4 erase",
		"A all   C traces   E export   R reset   Space pause",
	]
	if auto_line == "":
		lines.remove_at(5)
	_hud.text = "\n".join(lines)


func _format_failed_line() -> String:
	if _world == null:
		return ""
	var failed_ids := _failed_unit_ids()
	if failed_ids.is_empty():
		return ""
	var labels: Array[String] = failed_ids.duplicate()
	var suffix := ""
	if labels.size() > 5:
		suffix = " +%d more" % (labels.size() - 5)
		labels = labels.slice(0, 5)
	return "Failed (%d): %s%s" % [failed_ids.size(), ", ".join(labels), suffix]


func _format_selected_path_line() -> String:
	if _world == null or _selected_unit_ids.is_empty():
		return "Selected: none"
	var unit := _world.get_unit(_selected_unit_ids[0])
	if unit == null:
		return "Selected: missing"
	var last := unit.last_order_snapshot()
	var last_text := "none"
	if not last.is_empty():
		last_text = "%s:%s" % [str(last.get("status", "")), str(last.get("reason", ""))]
	return "Selected: %s state=%s wp=%d speed=%.0f%% last=%s" % [
		unit.id,
		unit.state,
		unit.path.size(),
		unit.last_speed_factor * 100.0,
		last_text,
	]


func _format_auto_demo_line() -> String:
	if not auto_command_demo:
		return ""
	if _ai_command_source == null:
		return "Auto: not started"
	var status := "running"
	if _ai_command_source.is_finished():
		status = "settling"
	if _auto_demo_reset_countdown >= 0:
		status = "reset in %d" % _auto_demo_reset_countdown
	return "Auto: run %d   %s   emitted %d" % [
		_auto_demo_run_index,
		status,
		int(_ai_command_source.emitted_count()),
	]


# A cancel is a deliberate stop, not an error — only no_path/stalled orders
# get the red failure treatment.
func _order_failed_hard(unit: Dota2LabUnit) -> bool:
	return unit.mobile and unit.last_order_failed() \
		and unit.last_order.reason != Dota2LabMoveOrder.REASON_CANCELLED


func _failed_unit_ids() -> Array[String]:
	var result: Array[String] = []
	if _world == null:
		return result
	for unit in _world.units:
		if _order_failed_hard(unit):
			result.append(unit.id)
	return result


# ─────────────────────────── Helpers ─────────────────────────────────────────

func _reset_scene() -> void:
	if auto_command_demo:
		_reset_auto_demo()
	else:
		_world = Dota2LabWorld.new()
		_ai_command_source = null
		_selected_unit_ids = _world.get_mobile_unit_ids()
		_reset_perf_metrics()
		_last_action = "reset scene"
		_record_event("reset", {"selected_unit_ids": _selected_unit_ids})


func _reset_auto_demo() -> void:
	_world = _create_auto_demo_world()
	_ai_command_source = AiCommandSourceScript.build_visual_demo_driver()
	_selected_unit_ids = _world.get_mobile_unit_ids()
	_auto_demo_run_index += 1
	_auto_demo_reset_countdown = -1
	_reset_perf_metrics()
	_last_action = "auto demo run %d" % _auto_demo_run_index
	_record_event("auto_demo_reset", {"selected_unit_ids": _selected_unit_ids})


func _create_auto_demo_world() -> Dota2LabWorld:
	var world := Dota2LabWorld.new()
	world.obstacles = []
	world.units = [
		Dota2LabUnit.new("lane_0", "blue", Vector2(100.0, 160.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_1", "blue", Vector2(100.0, 240.0), 11.0, 110.0, true),
		Dota2LabUnit.new("lane_2", "blue", Vector2(100.0, 320.0), 11.0, 110.0, true),
		Dota2LabUnit.new("chaser", "blue", Vector2(140.0, 450.0), 11.0, 110.0, true),
		Dota2LabUnit.new("cancelled", "blue", Vector2(140.0, 560.0), 11.0, 110.0, true),
	]
	world.rebuild_navigation()
	world.clear_traces()
	return world


func _tick_auto_demo() -> void:
	if not auto_command_demo or _ai_command_source == null:
		return
	var before_count := int(_ai_command_source.emitted_count())
	_ai_command_source.tick(_world)
	var after_count := int(_ai_command_source.emitted_count())
	if after_count <= before_count:
		return
	var snapshots: Array = _ai_command_source.emitted_snapshots() as Array
	if snapshots.is_empty():
		return
	var last_snapshot: Dictionary = snapshots[snapshots.size() - 1] as Dictionary
	_last_action = "auto %s" % str(last_snapshot.get("label", "command"))
	_record_event("auto_command", last_snapshot)


func _update_auto_demo_loop() -> void:
	if not auto_command_demo or not auto_demo_loop or _ai_command_source == null:
		return
	if not _ai_command_source.is_finished():
		return
	if not _auto_demo_units_are_terminal():
		return
	if _auto_demo_reset_countdown < 0:
		_auto_demo_reset_countdown = AUTO_DEMO_RESET_DELAY_TICKS
		return
	_auto_demo_reset_countdown -= 1
	if _auto_demo_reset_countdown <= 0:
		_reset_auto_demo()


func _auto_demo_units_are_terminal() -> bool:
	for unit in _world.get_mobile_units():
		if unit.state == Dota2LabUnit.STATE_MOVING:
			return false
	return true


func _debug_panel_origin() -> Vector2:
	if _world == null:
		return Vector2.ZERO
	return Vector2(_world.map_size.x + PANEL_GAP, 0.0)


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
		printerr("DOTA2_RTS_LAB_EXPORT_LOG_FAIL: cannot open user://")
		return false
	var err := dir.make_dir_recursive("dota2_rts_pathfinding_lab_logs")
	if err != OK:
		_last_action = "export failed"
		printerr("DOTA2_RTS_LAB_EXPORT_LOG_FAIL: mkdir error %d" % err)
		return false
	return true


func _default_export_path() -> String:
	var timestamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	return "%s/dota2_rts_lab_%s_tick_%d.json" % [
		LOG_DIR,
		timestamp,
		_world.tick_count,
	]


func _build_export_snapshot() -> Dictionary:
	var avg_step_usec := float(_total_step_usec) / float(maxi(_measured_step_count, 1))
	return {
		"schema": "dota2_rts_pathfinding_lab_debug_log_v1",
		"exported_at": Time.get_datetime_string_from_system(false, false),
		"scene": _scene_label(),
		"auto_command_demo": auto_command_demo,
		"auto_demo": _auto_demo_snapshot(),
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
			"recent_motion_updates": _world.recent_motion_updates.duplicate(true),
		},
		"pathfinder": _world.pathfinder.diagnostics(),
		"obstacles": _snapshot_obstacles(),
		"units": _snapshot_units(),
		"recent_events": _event_log.duplicate(true),
		"slow_frames": _slow_frame_log.duplicate(true),
	}


func _scene_label() -> String:
	if auto_command_demo:
		return "addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/frontend/dota2_ai_command_demo.tscn"
	return "addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/frontend/dota2_pathfinding_lab.tscn"


func _auto_demo_snapshot() -> Dictionary:
	if not auto_command_demo or _ai_command_source == null:
		return {}
	return {
		"run_index": _auto_demo_run_index,
		"reset_countdown": _auto_demo_reset_countdown,
		"source_finished": _ai_command_source.is_finished(),
		"emitted_count": int(_ai_command_source.emitted_count()),
		"emitted": _ai_command_source.emitted_snapshots(),
		"commanded_unit_ids": _ai_command_source.commanded_unit_ids(),
		"latest_targets_by_unit": _target_snapshots(_ai_command_source.latest_targets_by_unit() as Dictionary),
	}


func _snapshot_obstacles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obstacle in _world.obstacles:
		var rect := Rect2(obstacle.center - obstacle.size * 0.5, obstacle.size)
		result.append({
			"id": obstacle.id,
			"center": _vector_snapshot(obstacle.center),
			"size": _vector_snapshot(obstacle.size),
			"rect": _rect_snapshot(rect),
			"inflated_rect": _rect_snapshot(rect.grow(_world.pathfinder.default_clearance)),
			"rotation_rad": obstacle.rotation_rad,
		})
	return result


func _snapshot_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in _world.units:
		result.append({
			"id": unit.id,
			"group_id": unit.group_id,
			"mobile": unit.mobile,
			"position": _vector_snapshot(unit.position),
			"move_target": _vector_snapshot(unit.move_target),
			"effective_target": _vector_snapshot(unit.effective_target),
			"radius": unit.radius,
			"speed": unit.speed,
			"facing_angle_rad": unit.facing_angle_rad,
			"turn_rate_rad_per_sec": unit.turn_rate_rad_per_sec,
			"last_turn_delta_rad": unit.last_turn_delta_rad,
			"last_speed_factor": unit.last_speed_factor,
			"state": unit.state,
			"stall_seconds": unit.stall_seconds,
			"repath_count": unit.repath_count,
			"active_order_id": unit.active_order_id(),
			"current_order": unit.current_order_snapshot(),
			"last_order": unit.last_order_snapshot(),
			"path_size": unit.path.waypoints.size() if unit.path != null else 0,
			"path": _waypoint_path_snapshot(unit.path),
			"trace_tail": _packed_vector_snapshot(unit.trace, TRACE_EXPORT_LIMIT),
		})
	return result


func _target_snapshots(targets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for unit_id in targets.keys():
		var target: Vector2 = targets.get(unit_id, Vector2.ZERO) as Vector2
		result[str(unit_id)] = _vector_snapshot(target)
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
		"pathfinder": _world.pathfinder.diagnostics(),
		"recent_motion_updates_tail": _tail_dictionaries(_world.recent_motion_updates, 24),
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
