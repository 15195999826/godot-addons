extends Node

# CORE-003: HierarchicalPathfinder fallback uses fixed 256-cell radius
#
# Bug reproduced here:
#   - sim_nav_hierarchical_pathfinder.gd:139-149,169-178,424-443 caps fallback
#     ring scans at _MAX_NEAREST_RADIUS = 256 navcells.
#   - When a goal is unreachable AND the geographically nearest reachable cell
#     is more than 256 navcells away, canonicalization fails.
#
# 0 A.D. expected (HierarchicalPathfinder.cpp:713-719,741-786):
#     enumerate every region in the start's global region, compute nearest
#     navcell per region, take the global minimum. Bounded by region count,
#     not by geographic distance.
#
# Repro: 320×16 navcell grid. Vertical wall at column 30 (full height, no gap).
#     Start at (5, 8) in the small left region. Goal at (319, 8) in the large
#     right region. The nearest passable cell on the start side is (29, 8) —
#     290 cells from the goal anchor. That distance > 256, so the ring scan
#     centered on goal cannot find any cell in the start's reachable region.
#
# At HEAD: query_goal_reachability returns canonicalized=false, no canonical
#     navcell. FAIL (reproduction confirmed).
# After fix: returns canonicalized=true, canonical_navcell.x ≈ 29. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_003_hierarchical_far_goal.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-003 hierarchical far-goal canonicalization (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-003 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var grid_w := 320
	var grid_h := 16
	var wall_x := 30
	var nav_map := SimNavMap.new(grid_w, grid_h, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	for y in range(grid_h):
		nav_map.or_navcell_data(Vector2i(wall_x, y), pass_mask)

	var hierarchical := SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [pass_mask])

	var start := Vector2i(5, 8)
	var goal_cell := Vector2i(grid_w - 1, 8)
	var distance_from_goal_to_wall_left_side := goal_cell.x - (wall_x - 1)
	if distance_from_goal_to_wall_left_side <= 256:
		_failures.append(
			"setup error: wall-left to goal distance %d ≤ 256, scenario doesn't exercise the fallback radius cap"
			% distance_from_goal_to_wall_left_side
		)
		return

	if hierarchical.is_navcell_reachable(start, goal_cell, pass_mask):
		_failures.append("setup error: start should be UNREACHABLE from goal across the wall")
		return

	var goal := SimNavPathGoal.point(nav_map.navcell_center_world(goal_cell))
	var reachability := hierarchical.query_goal_reachability(start, goal, pass_mask, "ground")

	if not reachability.canonicalized:
		_failures.append(
			"goal at navcell %s should canonicalize to start's reachable region (failure_reason=%s)"
			% [str(goal_cell), reachability.failure_reason]
		)
		return

	var canonical := reachability.canonical_navcell
	if canonical.x >= wall_x:
		_failures.append("canonical navcell %s should be on start side (x < %d)" % [str(canonical), wall_x])
	if not nav_map.is_passable_navcell(canonical, pass_mask):
		_failures.append("canonical navcell %s should be passable" % str(canonical))
	if not hierarchical.is_navcell_reachable(start, canonical, pass_mask):
		_failures.append("canonical navcell %s should be reachable from start" % str(canonical))
