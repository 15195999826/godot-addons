extends Node

# CORE-011: Short path returns empty when goal is unreachable, even though
# A* visited vertices much closer to the goal than the start.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 5350, log 2026-05-10T19-11-25.
#   - blue_1 at (491.24, 229.22) with stationary blue_3 at (491, 207) (just N).
#     Final goal (408, 113) sits 9 px below north_block's top edge (Y=104) —
#     inside the unit clearance ring (clearance 11 > 9), so any segment ending
#     at the goal is rejected by static OBB LOS check.
#   - Long path's navcell raster uses default_clearance 12 (one navcell margin
#     to mirror 0 A.D. CLEARANCE_EXTENSION_RADIUS), so the goal navcell stays
#     passable and canonicalization leaves the goal at (408, 113).
#   - Vertex pathfinder runs A* but cannot terminate at the goal vertex (LOS
#     blocks all incoming edges via the static obstacle). Before fix, A*
#     returned an empty path → motion blocked_recovery → repeated short path
#     no_route → max_failed_movements → unit "stuck" despite an obvious
#     escape route.
#
# 0 A.D. expected (VertexPathfinder.cpp:868-873, 896-900):
#   A* tracks `idBest` — the heuristically-best (closest-to-goal) reachable
#   vertex. After the open list empties, the path is reconstructed back from
#   `idBest`, never empty. Motion makes progress toward the best reachable
#   vertex, then replans next tick.
#
# Fix (sim_nav_vertex_pathfinder.gd _astar_visibility): track `idx_best` and
# `h_best`; when A* exits without reaching the goal, reconstruct path back
# from `idx_best` (if any vertex closer than start was reached). Otherwise
# return empty so caller still surfaces no_route.
#
# Before fix: short path returns empty for unreachable-goal cases, motion
# spins blocked_recovery → max_failed_movements. FAIL.
# After fix: short path returns partial path to best reachable vertex; motion
# advances toward goal, replans next tick. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_011_short_path_best_vertex_fallback.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-011 best-vertex fallback (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-011 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var cell_size := 16.0
	var nav_map := SimNavMap.new(int(ceil(720.0 / cell_size)), int(ceil(420.0 / cell_size)), cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 12.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	# north_block matches the lab default world; goal sits ~9 px south of its top.
	var st := SimNavObstructionShapeStatic.new()
	st.entity_id = "north_block"
	st.center = Vector2(360.0, 76.0)
	st.width = 132.0
	st.height = 56.0
	st.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(st)
	nav_map.rebuild_dirty()

	var blockers: Array[SimNavObstructionShapeUnit] = []
	blockers.append(_make_blocker("blue_3", Vector2(491.0, 207.0), 11.0))
	nav_map.replace_dynamic_obstructions(blockers)

	var start := Vector2(491.242156982422, 229.217956542969)
	var goal_point := Vector2(408.0, 113.0)
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal_point)
	req.clearance = 11.0
	req.range_px = 896.0
	req.pass_mask = pass_mask
	req.avoid_moving_units = false
	req.control_group = ""
	req.obstruction_filter = SimNavObstructionFilter.for_short_path(false, "")
	req.obstruction_filter.ignored_entity_id = "blue_1"
	req.static_vertex_extra_outset = cell_size * 0.5

	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(req)
	if result.path.is_empty():
		_failures.append("expected non-empty partial path even when goal is unreachable; got %s/%s" % [str(result.status), str(result.failure_reason)])
		return

	var first_consumed: Vector2 = result.path.back()
	var start_to_goal := start.distance_to(goal_point)
	var first_to_goal := first_consumed.distance_to(goal_point)
	if first_to_goal >= start_to_goal:
		_failures.append(
			"first consumed waypoint %s did not move closer to goal (start_to_goal=%.2f first_to_goal=%.2f); path=%s"
			% [str(first_consumed), start_to_goal, first_to_goal, str(_path_to_array(result.path))]
		)


func _make_blocker(id: String, pos: Vector2, radius: float) -> SimNavObstructionShapeUnit:
	var shape := SimNavObstructionShapeUnit.new()
	shape.entity_id = id
	shape.center = pos
	shape.clearance = radius
	shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	shape.moving = false
	return shape


func _path_to_array(path: SimNavWaypointPath) -> Array:
	var out: Array = []
	for wp in path.waypoints:
		out.append("(%.1f, %.1f)" % [wp.x, wp.y])
	return out
