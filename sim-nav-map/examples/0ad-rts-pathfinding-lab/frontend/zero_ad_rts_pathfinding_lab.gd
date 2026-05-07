extends Node2D


const LabWorldScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_world.gd")

var world: Variant = null


func _ready() -> void:
	world = LabWorldScript.new()
	set_process(true)


func _process(delta: float) -> void:
	world.step(minf(delta, 1.0 / 20.0))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			world.issue_move_for_group("blue", mouse_event.position)
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			world.setup_default()


func _draw() -> void:
	if world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, world.map_size), Color(0.08, 0.09, 0.1), true)
	for obstacle in world.obstacles:
		draw_rect(obstacle.get_rect(), Color(0.55, 0.22, 0.18), true)
	for unit in world.units:
		var color := Color(0.2, 0.55, 1.0) if unit.group_id == "blue" else Color(1.0, 0.25, 0.2)
		draw_circle(unit.position, unit.radius, color)
		if unit.has_move_order:
			draw_line(unit.position, unit.target, Color(0.8, 0.8, 0.35, 0.55), 1.0)
			_draw_path(unit.short_path, Color(0.2, 1.0, 0.55, 0.8))
			_draw_path(unit.long_path, Color(0.45, 0.75, 1.0, 0.55))


func _draw_path(path: SimNavWaypointPath, color: Color) -> void:
	if path == null or path.waypoints.size() < 1:
		return
	for point in path.waypoints:
		draw_circle(point, 3.0, color)
