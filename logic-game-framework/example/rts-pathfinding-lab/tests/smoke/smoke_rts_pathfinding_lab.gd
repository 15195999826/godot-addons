extends Node


const LabObstacle := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")
const LabWorld := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

var _failures: Array[String] = []
var _world_metrics: Dictionary = {}


func _ready() -> void:
	_test_static_vertex_path_avoids_obstacle()
	_test_make_goal_reachable()
	_test_dynamic_unit_avoidance_and_group_filter()
	_test_world_edit_operations()
	_test_default_world_arrives_with_clean_metrics()

	if _failures.is_empty():
		print("RTS_PATHFINDING_LAB_METRICS: %s" % str(_world_metrics))
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab static/dynamic/world metrics OK")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_static_vertex_path_avoids_obstacle() -> void:
	var pf := LabPathfinder.new(Vector2(640.0, 360.0), 16.0, 12.0)
	var obstacles: Array[RtsPathfindingLabObstacle] = [
		LabObstacle.new("block", Vector2(320.0, 180.0), Vector2(120.0, 120.0)),
	]
	var units: Array[RtsPathfindingLabUnit] = []
	var start := Vector2(100.0, 180.0)
	var goal := Vector2(540.0, 180.0)
	var path: Array[Vector2] = pf.plan_path(start, goal, obstacles, units, "blue", true, true)
	if path.size() < 2:
		_failures.append("static: expected vertex path around obstacle, got %d waypoints" % path.size())
		return
	if not bool(pf.last_report.get("used_vertex", false)):
		_failures.append("static: expected vertex pathfinder to be used")
		return
	if not _path_segments_clear(pf, start, path, obstacles, 12.0):
		_failures.append("static: planned path intersects inflated obstacle")


func _test_make_goal_reachable() -> void:
	var pf := LabPathfinder.new(Vector2(640.0, 360.0), 16.0, 12.0)
	var obstacles: Array[RtsPathfindingLabObstacle] = [
		LabObstacle.new("target_block", Vector2(500.0, 180.0), Vector2(100.0, 100.0)),
	]
	var units: Array[RtsPathfindingLabUnit] = []
	var path: Array[Vector2] = pf.plan_path(Vector2(100.0, 180.0), Vector2(500.0, 180.0), obstacles, units, "blue", true, true)
	if path.is_empty():
		_failures.append("reachable: expected fallback path to nearest passable point")
		return
	if not bool(pf.last_report.get("used_make_goal_reachable", false)):
		_failures.append("reachable: expected used_make_goal_reachable=true")
	var reachable_goal: Vector2 = pf.last_report.get("reachable_goal", Vector2.ZERO) as Vector2
	if not pf.is_point_passable(reachable_goal, obstacles, 12.0):
		_failures.append("reachable: reachable_goal still inside inflated obstacle")


func _test_dynamic_unit_avoidance_and_group_filter() -> void:
	var pf := LabPathfinder.new(Vector2(640.0, 360.0), 16.0, 12.0)
	var obstacles: Array[RtsPathfindingLabObstacle] = []
	var start := Vector2(100.0, 180.0)
	var goal := Vector2(540.0, 180.0)

	var blocker := LabUnit.new("red_0", "red", Vector2(320.0, 180.0), 18.0, 0.0, false)
	var blockers: Array[RtsPathfindingLabUnit] = [blocker]
	var avoid_path: Array[Vector2] = pf.plan_path(start, goal, obstacles, blockers, "blue", true, true)
	if avoid_path.size() < 2:
		_failures.append("dynamic: expected path to route around red blocker")
		return
	var active := pf.build_obstacles_for_analysis(obstacles, blockers, "blue", true, true)
	if not _path_segments_clear(pf, start, avoid_path, active, 12.0):
		_failures.append("dynamic: avoid path intersects blocker proxy")

	var same_group := LabUnit.new("blue_friend", "blue", Vector2(320.0, 180.0), 18.0, 0.0, false)
	var friends: Array[RtsPathfindingLabUnit] = [same_group]
	var filtered_path: Array[Vector2] = pf.plan_path(start, goal, obstacles, friends, "blue", true, true)
	if filtered_path.size() != 1:
		_failures.append("dynamic: group filter should allow direct path through same group, got %d waypoints" % filtered_path.size())


func _test_world_edit_operations() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var mobile_ids := world.get_mobile_unit_ids()
	if mobile_ids.size() != 6:
		_failures.append("edit: expected 6 mobile ids, got %d" % mobile_ids.size())
		return
	world.set_units_target([mobile_ids[0], mobile_ids[1]], Vector2(180.0, 80.0))
	var first := world.get_unit_by_id(mobile_ids[0])
	var third := world.get_unit_by_id(mobile_ids[2])
	if first == null or third == null:
		_failures.append("edit: failed to read units by id")
		return
	if first.target == third.target:
		_failures.append("edit: subset move should not retarget unselected units")
	var obstacle_id := world.add_static_obstacle(Vector2(250.0, 120.0), Vector2(60.0, 60.0))
	var blocker_id := world.add_blocker(Vector2(260.0, 220.0))
	if obstacle_id == "" or blocker_id == "":
		_failures.append("edit: failed to create obstacle/blocker")
	var removed_id := world.remove_nearest_editable(Vector2(260.0, 220.0), 60.0)
	if removed_id == "":
		_failures.append("edit: expected erase to remove nearest blocker/obstacle")


func _test_default_world_arrives_with_clean_metrics() -> void:
	var world := LabWorld.new()
	world.setup_default()
	for _i in range(520):
		world.step(0.05)
		if world.all_mobile_arrived():
			break
	var metrics := world.analyze_movement()
	_world_metrics = metrics
	if int(metrics.get("arrived_count", 0)) != int(metrics.get("mobile_count", -1)):
		_failures.append("world: expected all mobile units arrived, metrics=%s" % str(metrics))
	if float(metrics.get("max_final_error", 999.0)) > 10.0:
		_failures.append("world: max_final_error too high, metrics=%s" % str(metrics))
	if float(metrics.get("max_overlap", 999.0)) > 1.0:
		_failures.append("world: max_overlap too high, metrics=%s" % str(metrics))
	if int(metrics.get("obstacle_violations", 99)) != 0:
		_failures.append("world: trace entered inflated obstacle, metrics=%s" % str(metrics))


func _path_segments_clear(
	pf: RtsPathfindingLabPathfinder,
	start: Vector2,
	path: Array[Vector2],
	obstacles: Array[RtsPathfindingLabObstacle],
	clearance: float
) -> bool:
	var prev := start
	for point in path:
		if not pf.segment_clear(prev, point, obstacles, clearance):
			return false
		prev = point
	return true
