extends Node

# CORE-004: SetBounds analogue missing (playable bounds tighter than grid)
#
# Bug reproduced here:
#   - SimNavMap has no set_bounds(x0, z0, x1, z1) API, so callers cannot
#     express a playable rectangle smaller than the underlying navcell grid.
#   - Grid out-of-range start/goal checks already exist, but they do not cover
#     the 0 A.D.-style obstruction/playable bounds contract.
#
# At HEAD: SimNavMap.has_method("set_bounds") is false. FAIL.
# After fix: the smoke also verifies tighter-than-grid goal rejection and
# static OBB raster clipping against the configured bounds.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro_core_004_set_bounds.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-004 set_bounds contract (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-004 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 4)
	if not nav_map.has_method("set_bounds"):
		_failures.append(
			"SimNavMap missing set_bounds(x0, z0, x1, z1); cannot express playable bounds tighter than the navcell grid"
		)
		return

	# Future contract: configure a playable rectangle smaller than the 16x16
	# backing grid. Coordinates are world-space, matching 0 A.D.'s SetBounds.
	nav_map.call("set_bounds", 16.0, 16.0, 96.0, 96.0)

	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var inside_start := Vector2(40.0, 40.0)
	var outside_goal := SimNavPathGoal.point(Vector2(116.0, 40.0))
	var outside_query := SimNavLongPathQuery.from_values(inside_start, outside_goal, pass_mask, "ground")
	var outside_result := long_pathfinder.compute_path_result(outside_query)
	if outside_result.status != SimNavLongPathResult.STATUS_INVALID_QUERY:
		_failures.append(
			"goal outside playable bounds returned status=%s; expected %s"
			% [outside_result.status, SimNavLongPathResult.STATUS_INVALID_QUERY]
		)
	if outside_result.failure_reason != SimNavLongPathResult.FAILURE_GOAL_OUT_OF_BOUNDS:
		_failures.append(
			"goal outside playable bounds returned failure_reason=%s; expected %s"
			% [outside_result.failure_reason, SimNavLongPathResult.FAILURE_GOAL_OUT_OF_BOUNDS]
		)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "straddling_wall"
	blocker.center = Vector2(100.0, 44.0)
	blocker.width = 32.0
	blocker.height = 16.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)
	nav_map.rebuild_dirty()

	var in_bounds_cell := Vector2i(11, 5) # center x=92, inside playable bounds and OBB.
	var outside_bounds_cell := Vector2i(13, 5) # center x=108, inside OBB but outside playable bounds.
	if nav_map.is_passable_navcell(in_bounds_cell, pass_mask):
		_failures.append("straddling OBB should rasterize in-bounds cell %s" % str(in_bounds_cell))
	if not nav_map.is_passable_navcell(outside_bounds_cell, pass_mask):
		_failures.append(
			"straddling OBB rasterized outside-bounds cell %s; expected clipping to playable bounds"
			% str(outside_bounds_cell)
		)
