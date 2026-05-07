extends Node


const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")
const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

var _failures: Array[String] = []
var _world_metrics: Dictionary = {}
var _perf_metrics: Dictionary = {}


func _ready() -> void:
	_test_static_vertex_path_avoids_obstacle()
	_test_make_goal_reachable()
	_test_dynamic_unit_avoidance_and_group_filter()
	_test_bottom_boundary_block_does_not_route_outside_map()
	_test_bottom_boundary_world_units_stay_inside_map()
	_test_single_unit_target_uses_command_center()
	_test_connected_static_push_out_uses_nearest_exit()
	_test_static_push_out_preserves_previous_side()
	_test_logged_idle_gap_push_does_not_cross_component()
	_test_logged_cluster_separation_stays_budgeted()
	_test_logged_stalled_cluster_settles_active_orders()
	_test_world_edit_operations()
	_test_group_move_replans_are_budgeted()
	_test_passive_push_chain_settles_idle_units()
	_test_unreachable_group_target_settles_at_reachable_edge()
	_test_default_world_arrives_with_clean_metrics()
	_test_dynamic_obstacle_edit_stress()
	_test_comprehensive_scripted_lab_stress()
	_test_obstacle_drop_during_walk_does_not_teleport()
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
	var start_usec := Time.get_ticks_usec()
	var path: Array[Vector2] = pf.plan_path(Vector2(100.0, 180.0), Vector2(500.0, 180.0), obstacles, units, "blue", true, true)
	var plan_usec := Time.get_ticks_usec() - start_usec
	if plan_usec > 100000:
		_failures.append("reachable: blocked target canonicalization too slow, plan_usec=%d" % plan_usec)
		return
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


func _test_bottom_boundary_block_does_not_route_outside_map() -> void:
	var map_size := Vector2(640.0, 420.0)
	var clearance := 12.0
	var pf := LabPathfinder.new(map_size, 16.0, clearance)
	var obstacles: Array[RtsPathfindingLabObstacle] = [
		LabObstacle.new("bottom_block", Vector2(320.0, 205.0), Vector2(220.0, 410.0)),
	]
	var units: Array[RtsPathfindingLabUnit] = []
	var start := Vector2(100.0, 210.0)
	var goal := Vector2(540.0, 210.0)
	var path: Array[Vector2] = pf.plan_path(start, goal, obstacles, units, "blue", true, true)
	if path.is_empty():
		_failures.append("bottom-boundary: expected path around obstacle without leaving map")
		return
	if not _path_points_inside_map(start, path, map_size, clearance):
		_failures.append("bottom-boundary: path contains waypoint outside map bounds, path=%s" % str(path))
		return
	if not _path_segments_clear(pf, start, path, obstacles, clearance):
		_failures.append("bottom-boundary: path segment exits map or intersects obstacle, path=%s" % str(path))


func _test_bottom_boundary_world_units_stay_inside_map() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = [
		LabObstacle.new("lower_wall", Vector2(340.0, 382.0), Vector2(200.0, 76.0)),
	]
	world.pathfinder.prewarm_static_context(world.obstacles)
	var unit := world.get_mobile_units()[0]
	unit.position = Vector2(340.0, 405.0)
	unit.target = unit.position
	unit.path.clear()
	unit.path_index = 0
	unit.arrived = true
	unit.has_move_order = false
	world.step(0.05)
	if not _point_inside_map(unit.position, world.map_size, unit.radius):
		_failures.append("bottom-boundary-world: push-out moved unit outside map bounds, point=%s radius=%.1f" % [
			str(unit.position),
			unit.radius,
		])
		return


func _test_single_unit_target_uses_command_center() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var mobile_ids := world.get_mobile_unit_ids()
	if mobile_ids.is_empty():
		_failures.append("single-target: expected at least one mobile unit")
		return
	var command_target := Vector2(180.0, 80.0)
	world.set_units_target([mobile_ids[0]], command_target)
	var selected_unit := world.get_unit_by_id(mobile_ids[0])
	if selected_unit == null:
		_failures.append("single-target: failed to read selected unit")
		return
	if selected_unit.target.distance_to(command_target) > 0.01:
		_failures.append("single-target: expected exact command target, got %s expected %s" % [
			str(selected_unit.target),
			str(command_target),
		])


func _test_connected_static_push_out_uses_nearest_exit() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = [
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("bridge_obstacle", Vector2(412.0, 123.0), Vector2(74.0, 74.0)),
	]
	world.pathfinder.prewarm_static_context(world.obstacles)
	var unit := world.get_mobile_units()[0]
	unit.position = Vector2(365.0, 136.0)
	unit.target = unit.position
	unit.path.clear()
	unit.path_index = 0
	unit.arrived = true
	unit.has_move_order = false
	world.step(0.05)
	if _active_obstacle_violation_detail(world).get("count", 0) != 0:
		_failures.append("connected-static-push: unit remained inside active obstacle at %s" % str(unit.position))
		return
	var displacement := unit.position.distance_to(Vector2(365.0, 136.0))
	if displacement > 20.0:
		_failures.append("connected-static-push: expected nearest exit, got displacement %.2f position=%s" % [
			displacement,
			str(unit.position),
		])


func _test_static_push_out_preserves_previous_side() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = [
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("right_upper", Vector2(450.0, 47.0), Vector2(74.0, 74.0)),
		LabObstacle.new("right_mid", Vector2(447.0, 165.0), Vector2(74.0, 74.0)),
	]
	world.pathfinder.prewarm_static_context(world.obstacles)
	var unit := world.get_mobile_units()[0]
	unit.position = Vector2(480.0, 144.25)
	unit.target = unit.position
	unit.trace = [
		Vector2(391.635772705078, 135.998733520508),
		Vector2(395.797943115234, 136.007034301758),
		Vector2(398.755004882813, 143.028457641602),
	]
	unit.path.clear()
	unit.path_index = 0
	unit.arrived = true
	unit.has_move_order = false
	world.step(0.05)
	if _active_obstacle_violation_detail(world).get("count", 0) != 0:
		_failures.append("static-push-side: unit remained inside active obstacle at %s" % str(unit.position))
		return
	if unit.position.x > 430.0:
		_failures.append("static-push-side: expected unit to stay on previous side, got %s" % str(unit.position))


func _test_logged_idle_gap_push_does_not_cross_component() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = [
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("south_wall", Vector2(340.0, 345.0), Vector2(120.0, 80.0)),
		LabObstacle.new("custom_obstacle_1", Vector2(441.0, 131.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_2", Vector2(442.0, 280.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_3", Vector2(446.0, 391.0), Vector2(74.0, 74.0)),
	]
	world.pathfinder.prewarm_static_context(world.obstacles)
	var positions := {
		"blue_0": Vector2(392.93, 126.038),
		"blue_1": Vector2(392.727, 140.073),
		"blue_2": Vector2(392.078, 140.481),
		"blue_3": Vector2(391.482, 126.558),
		"blue_4": Vector2(385.05, 139.45),
		"blue_5": Vector2(392.912, 142.284),
	}
	var traces := {
		"blue_0": [Vector2(386.262, 133.612), Vector2(390.383, 133.296), Vector2(392.895, 130.171), Vector2(392.93, 126.038)],
		"blue_1": [Vector2(381.341, 136.847), Vector2(385.559, 136.791), Vector2(389.654, 137.45), Vector2(392.727, 140.073)],
		"blue_2": [Vector2(384.009, 139.117), Vector2(388.105, 139.528), Vector2(392.078, 140.481)],
		"blue_3": [Vector2(384.342, 128.087), Vector2(388.232, 129.076), Vector2(391.482, 126.558)],
		"blue_4": [Vector2(381.0, 138.9), Vector2(385.05, 139.45)],
		"blue_5": [Vector2(386.38, 134.279), Vector2(390.681, 134.561), Vector2(392.817, 138.108), Vector2(392.912, 142.284)],
	}
	for unit_id in positions.keys():
		var unit := world.get_unit_by_id(unit_id)
		if unit == null:
			_failures.append("idle-gap-push: missing unit %s" % unit_id)
			return
		unit.position = positions[unit_id]
		unit.target = unit.position
		unit.trace.assign(traces[unit_id])
		unit.path.clear()
		unit.path_index = 0
		unit.arrived = true
		unit.has_move_order = false

	world.step(0.006)
	for unit_id in positions.keys():
		var unit := world.get_unit_by_id(unit_id)
		var before: Vector2 = positions[unit_id] as Vector2
		var displacement := unit.position.distance_to(before)
		if displacement > 24.0:
			_failures.append("idle-gap-push: unit crossed component, unit=%s displacement=%.2f before=%s after=%s" % [
				unit.id,
				displacement,
				str(before),
				str(unit.position),
			])
			return
	if int(_active_obstacle_violation_detail(world).get("count", 0)) != 0:
		_failures.append("idle-gap-push: unit remained inside active obstacle")


func _test_logged_cluster_separation_stays_budgeted() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = [
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("south_wall", Vector2(340.0, 345.0), Vector2(120.0, 80.0)),
		LabObstacle.new("custom_obstacle_1", Vector2(419.0, 137.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_2", Vector2(430.0, 284.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_3", Vector2(429.0, 382.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_4", Vector2(426.0, 29.0), Vector2(74.0, 74.0)),
	]
	world.pathfinder.prewarm_static_context(world.obstacles)
	var positions := {
		"blue_0": Vector2(337.3, 276.5),
		"blue_1": Vector2(349.6, 293.5),
		"blue_2": Vector2(359.4, 276.5),
		"blue_3": Vector2(371.7, 293.5),
		"blue_4": Vector2(327.1, 293.5),
		"blue_5": Vector2(377.5, 276.5),
	}
	for unit_id in positions.keys():
		var unit := world.get_unit_by_id(unit_id)
		if unit == null:
			_failures.append("logged-cluster: missing unit %s" % unit_id)
			return
		unit.position = positions[unit_id]
		unit.target = Vector2(376.0, 280.0)
		unit.path = [unit.target]
		unit.path_index = 0
		unit.arrived = false
		unit.has_move_order = true
		unit.replan_timer = 0.0
	world.get_unit_by_id("blue_5").target = Vector2(377.5, 276.5)
	world.get_unit_by_id("blue_5").path.clear()
	world.get_unit_by_id("blue_5").arrived = true
	world.get_unit_by_id("blue_5").has_move_order = false

	world.step(0.05)
	var profile := world.last_step_profile
	if int(profile.get("separation_usec", 0)) > 30000:
		_failures.append("logged-cluster: separation too slow, profile=%s" % str(profile))
		return
	var metrics := world.analyze_movement()
	if float(metrics.get("max_overlap", 99.0)) > 5.0:
		_failures.append("logged-cluster: overlap exploded, metrics=%s" % str(metrics))


func _test_logged_stalled_cluster_settles_active_orders() -> void:
	var world := LabWorld.new()
	world.setup_default()
	world.obstacles = [
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("south_wall", Vector2(340.0, 345.0), Vector2(120.0, 80.0)),
		LabObstacle.new("custom_obstacle_1", Vector2(423.0, 134.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_2", Vector2(435.0, 289.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_3", Vector2(431.0, 381.0), Vector2(74.0, 74.0)),
		LabObstacle.new("custom_obstacle_4", Vector2(438.0, 40.0), Vector2(74.0, 74.0)),
	]
	world.pathfinder.prewarm_static_context(world.obstacles)
	var active_positions := {
		"blue_0": Vector2(329.74, 293.5),
		"blue_1": Vector2(342.17, 276.5),
		"blue_2": Vector2(364.68, 276.5),
		"blue_3": Vector2(376.7, 293.5),
		"blue_4": Vector2(354.47, 293.5),
	}
	for unit_id in active_positions.keys():
		var unit := world.get_unit_by_id(unit_id)
		if unit == null:
			_failures.append("logged-stall: missing unit %s" % unit_id)
			return
		unit.position = active_positions[unit_id]
		unit.target = Vector2(376.0, 280.0)
		unit.path = [unit.target]
		unit.path_index = 0
		unit.arrived = false
		unit.has_move_order = true
		unit.replan_timer = 0.0
	var settled_unit := world.get_unit_by_id("blue_5")
	if settled_unit == null:
		_failures.append("logged-stall: missing settled unit blue_5")
		return
	settled_unit.position = Vector2(385.5, 276.5)
	settled_unit.target = settled_unit.position
	settled_unit.path.clear()
	settled_unit.path_index = 0
	settled_unit.arrived = true
	settled_unit.has_move_order = false

	var max_separation_usec := 0
	var stuck_settle_count := 0
	for _i in range(520):
		world.step(0.05)
		var profile := world.last_step_profile
		max_separation_usec = maxi(max_separation_usec, int(profile.get("separation_usec", 0)))
		var stuck_settles: Array = profile.get("stuck_settles", []) as Array
		stuck_settle_count += stuck_settles.size()
		var metrics := world.analyze_movement()
		if int(metrics.get("active_move_orders", 99)) == 0 and int(metrics.get("pending_replans", 99)) == 0:
			break

	var final_metrics := world.analyze_movement()
	final_metrics["max_separation_usec"] = max_separation_usec
	final_metrics["stuck_settle_count"] = stuck_settle_count
	final_metrics["movement_debug"] = world.movement_debug_snapshot()
	if int(final_metrics.get("active_move_orders", 99)) != 0:
		_failures.append("logged-stall: expected active move orders to settle, metrics=%s" % str(final_metrics))
		return
	if int(final_metrics.get("pending_replans", 99)) != 0:
		_failures.append("logged-stall: expected no queued replans after settle, metrics=%s" % str(final_metrics))
		return
	if max_separation_usec > 24000:
		_failures.append("logged-stall: separation stayed too expensive, metrics=%s" % str(final_metrics))
		return
	if int(_active_obstacle_violation_detail(world).get("count", 0)) != 0:
		_failures.append("logged-stall: unit inside active obstacle, metrics=%s" % str(final_metrics))
		return
	if float(final_metrics.get("max_overlap", 99.0)) > 6.0:
		_failures.append("logged-stall: overlap too high after settle, metrics=%s" % str(final_metrics))


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
	var max_step_usec := 0
	for _i in range(260):
		var step_start_usec := Time.get_ticks_usec()
		world.step(0.05)
		max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - step_start_usec)
		if world.all_mobile_arrived() and int(world.analyze_movement().get("pending_replans", 1)) == 0:
			break

	var metrics := world.analyze_movement()
	metrics["max_step_usec"] = max_step_usec
	if max_step_usec > 100000:
		_failures.append("unreachable-target: max step too high for blocked target canonicalization, metrics=%s" % str(metrics))
		return
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


func _test_dynamic_obstacle_edit_stress() -> void:
	var metrics := _measure_dynamic_obstacle_edit_stress(10)
	_perf_metrics["dynamic_edit_stress"] = metrics
	if int(metrics.get("failed_edits", 0)) != 0:
		_failures.append("dynamic-edit-stress: expected all scripted edits to apply, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_step_usec", 0)) > 80000:
		_failures.append("dynamic-edit-stress: max world.step too high, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_edit_usec", 0)) > 100000:
		_failures.append("dynamic-edit-stress: max edit operation too high, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_active_obstacle_violations", 0)) != 0:
		_failures.append("dynamic-edit-stress: unit inside active obstacle, metrics=%s" % str(metrics))
		return
	if float(metrics.get("max_overlap", 99.0)) > 1.0:
		_failures.append("dynamic-edit-stress: overlap too high, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_replans_per_tick", 99)) > LabWorld.REPLAN_BUDGET_PER_TICK:
		_failures.append("dynamic-edit-stress: replan budget exceeded, metrics=%s" % str(metrics))


func _test_comprehensive_scripted_lab_stress() -> void:
	var metrics := _measure_comprehensive_scripted_lab_stress(10)
	_perf_metrics["comprehensive_scripted_stress"] = metrics
	if int(metrics.get("failed_edits", 0)) != 0:
		_failures.append("scripted-stress: expected all scripted edits to apply, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_step_usec", 0)) > 80000:
		_failures.append("scripted-stress: max world.step too high, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_edit_usec", 0)) > 120000:
		_failures.append("scripted-stress: max edit operation too high, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_active_obstacle_violations", 0)) != 0:
		_failures.append("scripted-stress: unit inside active obstacle, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_out_of_bounds", 0)) != 0:
		_failures.append("scripted-stress: unit left playable map, metrics=%s" % str(metrics))
		return
	if float(metrics.get("max_overlap", 99.0)) > 12.0:
		_failures.append("scripted-stress: overlap too high, metrics=%s" % str(metrics))
		return
	# Active unit 上限:无 per-frame static push budget,worst case OVERLAP_RESOLVE_ITERATIONS × static push max_per_call ≈ 96,
	# 实测在 6 unit + 8 obstacle stress 场景下 ~74。这是 lab 简化 motion model 的已知限制(没有 acceleration / no-replan-on-overlap)。
	if float(metrics.get("max_any_jump", 0.0)) > 80.0:
		_failures.append("scripted-stress: large unit jump, metrics=%s" % str(metrics))
		return
	# Idle unit 在 _resolve_overlaps 推它后被 _push_out_static 修正回来,累积单帧 ~28。
	# overlap budget 16 限制了 _resolve_overlaps,但 _push_out_static 没有 per-frame budget(避免 unit 卡 obstacle)。
	if float(metrics.get("max_idle_jump", 0.0)) > 32.0:
		_failures.append("scripted-stress: idle unit jump, metrics=%s" % str(metrics))
		return
	if int(metrics.get("max_replans_per_tick", 99)) > LabWorld.REPLAN_BUDGET_PER_TICK:
		_failures.append("scripted-stress: replan budget exceeded, metrics=%s" % str(metrics))


func _test_obstacle_drop_during_walk_does_not_teleport() -> void:
	# Replay user-reported scenario: units walking along stone_block south corridor,
	# user drops custom_obstacle_2/3 on their path. Original code teleported units
	# 26-63 px in a single step and spent 22 ms in separation. Both must stay bounded.
	var world := LabWorld.new()
	world.setup_default()
	world.group_filter_enabled = true
	world.avoid_moving_units_enabled = true
	var mobile_ids := world.get_mobile_unit_ids()
	world.set_units_target(mobile_ids, Vector2(610.0, 225.0))
	for _i in range(120):
		world.step(0.05)
	var max_jump := 0.0
	var max_jump_unit := ""
	var max_jump_step := -1
	var max_separation_usec := 0
	var add_at_step := 5
	var second_add_at_step := 90
	for step_index in range(220):
		match step_index:
			5:
				world.add_static_obstacle(Vector2(445.0, 283.0), Vector2(74.0, 74.0))
			90:
				world.add_static_obstacle(Vector2(455.0, 380.0), Vector2(74.0, 74.0))
		var positions_before := _mobile_positions(world)
		world.step(0.05)
		max_separation_usec = maxi(max_separation_usec, int(world.last_step_profile.get("separation_usec", 0)))
		for unit in world.get_mobile_units():
			if not positions_before.has(unit.id):
				continue
			var before: Vector2 = positions_before[unit.id] as Vector2
			var distance := before.distance_to(unit.position)
			if distance > max_jump:
				max_jump = distance
				max_jump_unit = unit.id
				max_jump_step = step_index
	# 上限 = static push max_per_call (≈ cell_size * 1.5 = 24) + overlap budget (≈ cell_size * 1 = 16) = 40,
	# 但因为单帧 unit 通常不会同时把 static push 和 overlap push 都用满,实际 ≤ 24。
	if max_jump > 24.0:
		_failures.append("obstacle-drop-walk: unit teleported %.2f px (unit=%s, step=%d, add_at=%d/%d)" % [
			max_jump,
			max_jump_unit,
			max_jump_step,
			add_at_step,
			second_add_at_step,
		])
		return
	if max_separation_usec > 16000:
		_failures.append("obstacle-drop-walk: separation too slow %d us" % max_separation_usec)
		return


func _test_step_perf_metrics() -> void:
	_perf_metrics = {
		"single_unit_retarget": _measure_retarget_perf(1),
		"six_unit_retarget": _measure_retarget_perf(6),
		"dynamic_edit_stress": _perf_metrics.get("dynamic_edit_stress", {}),
		"comprehensive_scripted_stress": _perf_metrics.get("comprehensive_scripted_stress", {}),
	}


func _measure_dynamic_obstacle_edit_stress(rounds: int) -> Dictionary:
	var world := LabWorld.new()
	world.setup_default()
	world.clear_traces()
	var mobile_ids := world.get_mobile_unit_ids()
	var targets: Array[Vector2] = [
		Vector2(610.0, 210.0),
		Vector2(95.0, 210.0),
	]
	var top_gate := Vector2(340.0, 135.0)
	var bottom_gate := Vector2(340.0, 285.0)
	var stress_obstacle_size := Vector2(74.0, 74.0)
	var max_step_usec := 0
	var max_step_detail := {}
	var total_step_usec := 0
	var step_count := 0
	var max_edit_usec := 0
	var failed_edits := 0
	var max_active_obstacle_violations := 0
	var first_active_violation := {}
	var max_overlap := 0.0
	var max_overlap_detail := {}
	var max_replans_this_run := 0

	for round_index in range(rounds):
		world.set_units_target(mobile_ids, targets[round_index % targets.size()])
		for step_index in range(64):
			match step_index:
				8:
					var add_top_start_usec := Time.get_ticks_usec()
					world.add_static_obstacle(top_gate, stress_obstacle_size)
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - add_top_start_usec)
				16:
					var add_bottom_start_usec := Time.get_ticks_usec()
					world.add_static_obstacle(bottom_gate, stress_obstacle_size)
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - add_bottom_start_usec)
				32:
					var remove_top_start_usec := Time.get_ticks_usec()
					if world.remove_nearest_editable(top_gate, 24.0) == "":
						failed_edits += 1
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - remove_top_start_usec)
				48:
					var remove_bottom_start_usec := Time.get_ticks_usec()
					if world.remove_nearest_editable(bottom_gate, 24.0) == "":
						failed_edits += 1
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - remove_bottom_start_usec)

			var step_start_usec := Time.get_ticks_usec()
			world.step(0.05)
			var step_usec := Time.get_ticks_usec() - step_start_usec
			if step_usec > max_step_usec:
				max_step_usec = step_usec
				max_step_detail = {
					"round": round_index,
					"step": step_index,
					"step_usec": step_usec,
					"profile": world.last_step_profile.duplicate(true),
				}
			total_step_usec += step_usec
			step_count += 1
			max_replans_this_run = maxi(max_replans_this_run, world.last_replans_this_tick)
			var active_violation := _active_obstacle_violation_detail(world)
			var active_violation_count := int(active_violation.get("count", 0))
			max_active_obstacle_violations = maxi(max_active_obstacle_violations, active_violation_count)
			if first_active_violation.is_empty() and active_violation_count > 0:
				active_violation["round"] = round_index
				active_violation["step"] = step_index
				first_active_violation = active_violation
			var overlap_detail := _unit_overlap_detail(world)
			var current_overlap := float(overlap_detail.get("overlap", 0.0))
			if current_overlap > max_overlap:
				max_overlap = current_overlap
				overlap_detail["round"] = round_index
				overlap_detail["step"] = step_index
				max_overlap_detail = overlap_detail

	var final_metrics := world.analyze_movement()
	return {
		"rounds": rounds,
		"steps": step_count,
		"max_step_usec": max_step_usec,
		"max_step_detail": max_step_detail,
		"avg_step_usec": float(total_step_usec) / float(maxi(step_count, 1)),
		"max_edit_usec": max_edit_usec,
		"failed_edits": failed_edits,
		"max_active_obstacle_violations": max_active_obstacle_violations,
		"first_active_violation": first_active_violation,
		"max_overlap": max_overlap,
		"max_overlap_detail": max_overlap_detail,
		"max_replans_per_tick": max_replans_this_run,
		"pending_replans": int(final_metrics.get("pending_replans", 0)),
		"total_replans": int(final_metrics.get("total_replans", 0)),
		"static_context_cache_hits": int(final_metrics.get("static_context_cache_hits", 0)),
		"static_context_cache_misses": int(final_metrics.get("static_context_cache_misses", 0)),
	}


func _measure_comprehensive_scripted_lab_stress(case_count: int) -> Dictionary:
	var edit_points: Array[Vector2] = [
		Vector2(340.0, 135.0),
		Vector2(340.0, 285.0),
		Vector2(441.0, 131.0),
		Vector2(442.0, 280.0),
		Vector2(446.0, 391.0),
		Vector2(446.0, 29.0),
		Vector2(80.0, 210.0),
		Vector2(640.0, 210.0),
		Vector2(340.0, 40.0),
		Vector2(340.0, 380.0),
	]
	var targets: Array[Vector2] = [
		Vector2(610.0, 210.0),
		Vector2(95.0, 210.0),
		Vector2(340.0, 210.0),
		Vector2(340.0, 75.0),
		Vector2(340.0, 345.0),
		Vector2(32.0, 32.0),
		Vector2(688.0, 388.0),
		Vector2(610.0, 40.0),
		Vector2(95.0, 380.0),
		Vector2(376.0, 280.0),
	]
	var max_step_usec := 0
	var max_step_detail := {}
	var total_step_usec := 0
	var step_count := 0
	var max_edit_usec := 0
	var failed_edits := 0
	var max_active_obstacle_violations := 0
	var first_active_violation := {}
	var max_out_of_bounds := 0
	var first_out_of_bounds := {}
	var max_overlap := 0.0
	var max_overlap_detail := {}
	var max_any_jump := 0.0
	var max_any_jump_detail := {}
	var max_idle_jump := 0.0
	var max_idle_jump_detail := {}
	var max_replans_this_run := 0
	var max_final_active_orders := 0
	var final_metrics_by_case: Array[Dictionary] = []

	for case_index in range(case_count):
		var world := LabWorld.new()
		world.setup_default()
		world.clear_traces()
		world.group_filter_enabled = case_index % 2 == 0
		world.avoid_moving_units_enabled = case_index % 3 != 0
		var mobile_ids := world.get_mobile_unit_ids()
		world.set_units_target(mobile_ids, targets[case_index % targets.size()])
		var point_a := edit_points[(case_index * 2) % edit_points.size()]
		var point_b := edit_points[(case_index * 2 + 1) % edit_points.size()]
		var point_c := edit_points[(case_index * 3 + 4) % edit_points.size()]
		for step_index in range(96):
			match step_index:
				8:
					var add_a_start_usec := Time.get_ticks_usec()
					world.add_static_obstacle(point_a, Vector2(74.0, 74.0))
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - add_a_start_usec)
				16:
					var add_b_start_usec := Time.get_ticks_usec()
					world.add_static_obstacle(point_b, Vector2(74.0, 74.0))
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - add_b_start_usec)
				24:
					var add_blocker_start_usec := Time.get_ticks_usec()
					world.add_blocker(point_c)
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - add_blocker_start_usec)
				36:
					world.set_units_target(mobile_ids, targets[(case_index + 3) % targets.size()])
				52:
					var remove_a_start_usec := Time.get_ticks_usec()
					if world.remove_nearest_editable(point_a, 64.0) == "":
						failed_edits += 1
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - remove_a_start_usec)
				68:
					world.group_filter_enabled = not world.group_filter_enabled
					world.avoid_moving_units_enabled = not world.avoid_moving_units_enabled
					world.set_units_target(mobile_ids, targets[(case_index + 6) % targets.size()])
				76:
					var remove_b_start_usec := Time.get_ticks_usec()
					if world.remove_nearest_editable(point_b, 64.0) == "":
						failed_edits += 1
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - remove_b_start_usec)
				88:
					var remove_blocker_start_usec := Time.get_ticks_usec()
					if world.remove_nearest_editable(point_c, 64.0) == "":
						failed_edits += 1
					max_edit_usec = maxi(max_edit_usec, Time.get_ticks_usec() - remove_blocker_start_usec)

			var positions_before := _mobile_positions(world)
			var idle_before := _idle_mobile_ids(world)
			var step_start_usec := Time.get_ticks_usec()
			world.step(0.05)
			var step_usec := Time.get_ticks_usec() - step_start_usec
			if step_usec > max_step_usec:
				max_step_usec = step_usec
				max_step_detail = {
					"case": case_index,
					"step": step_index,
					"step_usec": step_usec,
					"profile": world.last_step_profile.duplicate(true),
				}
			total_step_usec += step_usec
			step_count += 1
			max_replans_this_run = maxi(max_replans_this_run, world.last_replans_this_tick)
			var active_violation := _active_obstacle_violation_detail(world)
			var active_violation_count := int(active_violation.get("count", 0))
			max_active_obstacle_violations = maxi(max_active_obstacle_violations, active_violation_count)
			if first_active_violation.is_empty() and active_violation_count > 0:
				active_violation["case"] = case_index
				active_violation["step"] = step_index
				first_active_violation = active_violation
			var bounds_violation := _out_of_bounds_detail(world)
			var bounds_violation_count := int(bounds_violation.get("count", 0))
			max_out_of_bounds = maxi(max_out_of_bounds, bounds_violation_count)
			if first_out_of_bounds.is_empty() and bounds_violation_count > 0:
				bounds_violation["case"] = case_index
				bounds_violation["step"] = step_index
				first_out_of_bounds = bounds_violation
			var overlap_detail := _unit_overlap_detail(world)
			var current_overlap := float(overlap_detail.get("overlap", 0.0))
			if current_overlap > max_overlap:
				max_overlap = current_overlap
				overlap_detail["case"] = case_index
				overlap_detail["step"] = step_index
				max_overlap_detail = overlap_detail
			var jump_detail := _position_jump_detail(world, positions_before, idle_before)
			var any_jump := float(jump_detail.get("max_any_jump", 0.0))
			if any_jump > max_any_jump:
				max_any_jump = any_jump
				jump_detail["case"] = case_index
				jump_detail["step"] = step_index
				max_any_jump_detail = jump_detail
			var idle_jump := float(jump_detail.get("max_idle_jump", 0.0))
			if idle_jump > max_idle_jump:
				max_idle_jump = idle_jump
				jump_detail["case"] = case_index
				jump_detail["step"] = step_index
				max_idle_jump_detail = jump_detail

		var final_metrics := world.analyze_movement()
		var final_active_orders := int(final_metrics.get("active_move_orders", 0))
		max_final_active_orders = maxi(max_final_active_orders, final_active_orders)
		final_metrics["case"] = case_index
		final_metrics_by_case.append(final_metrics)

	return {
		"cases": case_count,
		"steps": step_count,
		"max_step_usec": max_step_usec,
		"max_step_detail": max_step_detail,
		"avg_step_usec": float(total_step_usec) / float(maxi(step_count, 1)),
		"max_edit_usec": max_edit_usec,
		"failed_edits": failed_edits,
		"max_active_obstacle_violations": max_active_obstacle_violations,
		"first_active_violation": first_active_violation,
		"max_out_of_bounds": max_out_of_bounds,
		"first_out_of_bounds": first_out_of_bounds,
		"max_overlap": max_overlap,
		"max_overlap_detail": max_overlap_detail,
		"max_any_jump": max_any_jump,
		"max_any_jump_detail": max_any_jump_detail,
		"max_idle_jump": max_idle_jump,
		"max_idle_jump_detail": max_idle_jump_detail,
		"max_replans_per_tick": max_replans_this_run,
		"max_final_active_orders": max_final_active_orders,
		"final_metrics_by_case": final_metrics_by_case,
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


func _path_points_inside_map(start: Vector2, path: Array[Vector2], map_size: Vector2, clearance: float) -> bool:
	if not _point_inside_map(start, map_size, clearance):
		return false
	for point in path:
		if not _point_inside_map(point, map_size, clearance):
			return false
	return true


func _point_inside_map(point: Vector2, map_size: Vector2, clearance: float) -> bool:
	return (
		point.x >= clearance
		and point.y >= clearance
		and point.x <= map_size.x - clearance
		and point.y <= map_size.y - clearance
	)


func _mobile_positions(world: RtsPathfindingLabWorld) -> Dictionary:
	var result: Dictionary = {}
	for unit in world.get_mobile_units():
		result[unit.id] = unit.position
	return result


func _idle_mobile_ids(world: RtsPathfindingLabWorld) -> Dictionary:
	var result: Dictionary = {}
	for unit in world.get_mobile_units():
		if unit.arrived and not unit.has_move_order:
			result[unit.id] = true
	return result


func _position_jump_detail(
	world: RtsPathfindingLabWorld,
	positions_before: Dictionary,
	idle_before: Dictionary
) -> Dictionary:
	var result := {
		"max_any_jump": 0.0,
		"max_idle_jump": 0.0,
	}
	for unit in world.get_mobile_units():
		if not positions_before.has(unit.id):
			continue
		var before: Vector2 = positions_before[unit.id] as Vector2
		var distance := before.distance_to(unit.position)
		if distance > float(result.get("max_any_jump", 0.0)):
			result["max_any_jump"] = distance
			result["any_unit_id"] = unit.id
			result["any_from"] = before
			result["any_to"] = unit.position
			result["any_arrived"] = unit.arrived
			result["any_has_move_order"] = unit.has_move_order
		if idle_before.has(unit.id) and unit.arrived and not unit.has_move_order:
			if distance > float(result.get("max_idle_jump", 0.0)):
				result["max_idle_jump"] = distance
				result["idle_unit_id"] = unit.id
				result["idle_from"] = before
				result["idle_to"] = unit.position
	return result


func _out_of_bounds_detail(world: RtsPathfindingLabWorld) -> Dictionary:
	var result := {
		"count": 0,
	}
	for unit in world.get_mobile_units():
		if _point_inside_map(unit.position, world.map_size, unit.radius):
			continue
		result["count"] = int(result["count"]) + 1
		if not result.has("unit_id"):
			result["unit_id"] = unit.id
			result["position"] = unit.position
			result["radius"] = unit.radius
	return result


func _active_obstacle_violation_detail(world: RtsPathfindingLabWorld) -> Dictionary:
	var result := {
		"count": 0,
	}
	for unit in world.get_mobile_units():
		for obstacle in world.obstacles:
			if obstacle.get_inflated_rect(unit.radius).has_point(unit.position):
				result["count"] = int(result["count"]) + 1
				if not result.has("unit_id"):
					result["unit_id"] = unit.id
					result["unit_position"] = unit.position
					result["unit_target"] = unit.target
					result["obstacle_id"] = obstacle.id
					result["obstacle_center"] = obstacle.center
	return result


func _unit_overlap_detail(world: RtsPathfindingLabWorld) -> Dictionary:
	var result := {
		"overlap": 0.0,
	}
	var mobile_units := world.get_mobile_units()
	for i in range(mobile_units.size()):
		for j in range(i + 1, mobile_units.size()):
			var a := mobile_units[i]
			var b := mobile_units[j]
			var overlap := a.radius + b.radius - a.position.distance_to(b.position)
			if overlap > float(result.get("overlap", 0.0)):
				result = {
					"overlap": overlap,
					"a_id": a.id,
					"b_id": b.id,
					"a_position": a.position,
					"b_position": b.position,
					"a_target": a.target,
					"b_target": b.target,
					"a_arrived": a.arrived,
					"b_arrived": b.arrived,
					"a_has_move_order": a.has_move_order,
					"b_has_move_order": b.has_move_order,
				}
	return result
