extends Node


const LabObstacle := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")
const LabWorld := preload("res://addons/logic-game-framework/example/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

var _failures: Array[String] = []
var _world_metrics: Dictionary = {}
var _perf_metrics: Dictionary = {}


func _ready() -> void:
	_test_static_vertex_path_avoids_obstacle()
	_test_make_goal_reachable()
	_test_dynamic_unit_avoidance_and_group_filter()
	_test_world_edit_operations()
	_test_group_move_replans_are_budgeted()
	_test_passive_push_chain_settles_idle_units()
	_test_unreachable_group_target_settles_at_reachable_edge()
	_test_default_world_arrives_with_clean_metrics()
	_test_step_perf_metrics()

	if _failures.is_empty():
		print("RTS_PATHFINDING_LAB_METRICS: %s" % str(_world_metrics))
		print("RTS_PATHFINDING_LAB_STEP_PERF: %s" % str(_perf_metrics))
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


func _test_group_move_replans_are_budgeted() -> void:
	var world := LabWorld.new()
	world.setup_default()
	for _i in range(24):
		world.step(0.05)
		if world.max_replans_per_tick > LabWorld.REPLAN_BUDGET_PER_TICK:
			_failures.append("budget: expected at most %d replans per tick, got %d" % [
				LabWorld.REPLAN_BUDGET_PER_TICK,
				world.max_replans_per_tick,
			])
			return
	if world.total_replans < world.get_mobile_unit_ids().size():
		_failures.append("budget: expected initial group move to replan every mobile unit, got %d" % world.total_replans)
	var mobile_ids := world.get_mobile_unit_ids()
	world.set_units_target(mobile_ids, Vector2(120.0, 330.0))
	var replan_total_before := world.total_replans
	for _i in range(24):
		world.step(0.05)
		if world.last_replans_this_tick > LabWorld.REPLAN_BUDGET_PER_TICK:
			_failures.append("budget: group retarget exceeded per tick budget, got %d" % world.last_replans_this_tick)
			return
	if world.total_replans - replan_total_before < mobile_ids.size():
		_failures.append("budget: expected retarget to replan every selected unit, got %d" % (world.total_replans - replan_total_before))


func _test_passive_push_chain_settles_idle_units() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = []
	world.pathfinder.prewarm_static_context(world.obstacles)
	var mobile_ids := world.get_mobile_unit_ids()
	var positions: Array[Vector2] = [
		Vector2(180.0, 210.0),
		Vector2(205.0, 210.0),
		Vector2(229.0, 210.0),
		Vector2(253.0, 210.0),
		Vector2(520.0, 120.0),
		Vector2(520.0, 300.0),
	]
	for i in range(mobile_ids.size()):
		var unit := world.get_unit_by_id(mobile_ids[i])
		if unit == null:
			_failures.append("push-chain: failed to find mobile unit %s" % mobile_ids[i])
			return
		unit.position = positions[i]
		unit.target = positions[i]
		unit.path.clear()
		unit.path_index = 0
		unit.arrived = true
		unit.has_move_order = false

	world.set_units_target([mobile_ids[0]], Vector2(310.0, 225.0))
	for _i in range(160):
		world.step(0.05)

	var idle_positions_before: Dictionary = {}
	for i in range(1, 4):
		var idle_unit := world.get_unit_by_id(mobile_ids[i])
		if idle_unit == null:
			_failures.append("push-chain: missing idle unit %s" % mobile_ids[i])
			return
		if idle_unit.has_move_order or not idle_unit.arrived:
			_failures.append("push-chain: passive unit became active, unit=%s arrived=%s active=%s" % [
				idle_unit.id,
				str(idle_unit.arrived),
				str(idle_unit.has_move_order),
			])
			return
		if idle_unit.position.distance_to(idle_unit.target) > 0.01:
			_failures.append("push-chain: idle target did not settle to pushed position, unit=%s" % idle_unit.id)
			return
		idle_positions_before[idle_unit.id] = idle_unit.position

	for _i in range(60):
		world.step(0.05)
	for i in range(1, 4):
		var settled_unit := world.get_unit_by_id(mobile_ids[i])
		var before: Vector2 = idle_positions_before[mobile_ids[i]] as Vector2
		if settled_unit.position.distance_to(before) > 0.25:
			_failures.append("push-chain: idle unit drifted after settling, unit=%s drift=%.3f" % [
				settled_unit.id,
				settled_unit.position.distance_to(before),
			])
			return


func _test_unreachable_group_target_settles_at_reachable_edge() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var obstacle_center := Vector2(340.0, 210.0)
	world.set_group_target(obstacle_center)
	var canonicalized_count := 0
	for _i in range(260):
		world.step(0.05)
		if world.all_mobile_arrived() and int(world.analyze_movement().get("pending_replans", 1)) == 0:
			break

	var metrics := world.analyze_movement()
	if int(metrics.get("arrived_count", 0)) != int(metrics.get("mobile_count", -1)):
		_failures.append("unreachable-target: expected all units to settle at reachable edge, metrics=%s" % str(metrics))
		return
	if int(metrics.get("active_move_orders", 99)) != 0:
		_failures.append("unreachable-target: expected no active move orders after settling, metrics=%s" % str(metrics))
		return
	if float(metrics.get("max_overlap", 99.0)) > 1.0:
		_failures.append("unreachable-target: overlap too high after settling, metrics=%s" % str(metrics))
		return
	for unit in world.get_mobile_units():
		if not world.pathfinder.is_point_passable(unit.target, world.obstacles, unit.radius):
			_failures.append("unreachable-target: final target is still impassable for %s at %s" % [unit.id, str(unit.target)])
			return
		if unit.target.distance_to(obstacle_center) > 2.0:
			canonicalized_count += 1
	if canonicalized_count == 0:
		_failures.append("unreachable-target: expected at least one unit target to be canonicalized")
		return

	var positions_before: Dictionary = {}
	for unit in world.get_mobile_units():
		positions_before[unit.id] = unit.position
	for _i in range(80):
		world.step(0.05)
	for unit in world.get_mobile_units():
		var before: Vector2 = positions_before[unit.id] as Vector2
		if unit.position.distance_to(before) > 0.25:
			_failures.append("unreachable-target: unit drifted after settling, unit=%s drift=%.3f" % [
				unit.id,
				unit.position.distance_to(before),
			])
			return


func _test_default_world_arrives_with_clean_metrics() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var max_step_usec := 0
	var total_step_usec := 0
	var step_count := 0
	for _i in range(520):
		var step_start_usec := Time.get_ticks_usec()
		world.step(0.05)
		var step_usec := Time.get_ticks_usec() - step_start_usec
		max_step_usec = maxi(max_step_usec, step_usec)
		total_step_usec += step_usec
		step_count += 1
		if world.all_mobile_arrived():
			break
	var metrics := world.analyze_movement()
	metrics["max_step_usec"] = max_step_usec
	metrics["avg_step_usec"] = float(total_step_usec) / float(maxi(step_count, 1))
	_world_metrics = metrics
	if int(metrics.get("arrived_count", 0)) != int(metrics.get("mobile_count", -1)):
		_failures.append("world: expected all mobile units arrived, metrics=%s" % str(metrics))
	if float(metrics.get("max_final_error", 999.0)) > 10.0:
		_failures.append("world: max_final_error too high, metrics=%s" % str(metrics))
	if float(metrics.get("max_overlap", 999.0)) > 1.0:
		_failures.append("world: max_overlap too high, metrics=%s" % str(metrics))
	if int(metrics.get("obstacle_violations", 99)) != 0:
		_failures.append("world: trace entered inflated obstacle, metrics=%s" % str(metrics))
	if int(metrics.get("max_replans_per_tick", 99)) > LabWorld.REPLAN_BUDGET_PER_TICK:
		_failures.append("world: replan spike exceeded budget, metrics=%s" % str(metrics))
	if int(metrics.get("static_context_cache_misses", 99)) != 1:
		_failures.append("world: expected exactly one static context build after prewarm, metrics=%s" % str(metrics))
	if int(metrics.get("static_context_cache_hits", 0)) < int(metrics.get("total_replans", 0)):
		_failures.append("world: expected per-plan static context cache hits, metrics=%s" % str(metrics))


func _test_step_perf_metrics() -> void:
	_perf_metrics = {
		"single_unit_retarget": _measure_retarget_perf(1),
		"six_unit_retarget": _measure_retarget_perf(6),
	}


func _measure_retarget_perf(unit_count: int) -> Dictionary:
	var world := LabWorld.new()
	world.setup_default()
	for _i in range(520):
		world.step(0.05)
		if world.all_mobile_arrived():
			break

	var all_ids := world.get_mobile_unit_ids()
	var selected_ids: Array[String] = []
	for i in range(mini(unit_count, all_ids.size())):
		selected_ids.append(all_ids[i])

	var replan_total_before := world.total_replans
	world.set_units_target(selected_ids, Vector2(120.0, 330.0))
	var max_step_usec := 0
	var total_step_usec := 0
	var step_count := 0
	var max_replans_this_run := 0
	for _i in range(240):
		var step_start_usec := Time.get_ticks_usec()
		world.step(0.05)
		var step_usec := Time.get_ticks_usec() - step_start_usec
		max_step_usec = maxi(max_step_usec, step_usec)
		total_step_usec += step_usec
		step_count += 1
		max_replans_this_run = maxi(max_replans_this_run, world.last_replans_this_tick)
		if _selected_units_arrived(world, selected_ids):
			break

	return {
		"unit_count": selected_ids.size(),
		"ticks": step_count,
		"max_step_usec": max_step_usec,
		"avg_step_usec": float(total_step_usec) / float(maxi(step_count, 1)),
		"planned_paths": world.total_replans - replan_total_before,
		"max_replans_per_tick": max_replans_this_run,
	}


func _selected_units_arrived(world: RtsPathfindingLabWorld, selected_ids: Array[String]) -> bool:
	for unit_id in selected_ids:
		var unit := world.get_unit_by_id(unit_id)
		if unit == null or not unit.arrived:
			return false
	return true


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
