extends Node

# CORE-002: LongPathfinder LOS refinement sampling can miss narrow gaps
#
# Bug reproduced here:
#   - sim_nav_long_pathfinder.gd::_segment_passable_clear used to sample
#     the segment at fixed step navcell*0.5. For some segments whose
#     blocked-cell crossing arc is shorter than the sample step AND falls
#     between two adjacent samples, uniform sampling missed the blocked
#     cell entirely. 0 A.D. CheckLineMovement walks navcell-by-navcell
#     (Bresenham/Amanatides-Woo) so it cannot skip a cell.
#
# Adversarial geometry constructed analytically:
#   navcell_size = 8. Block cell (5, 5) (world rect [40,48]^2).
#   Segment a = (32, 47) → b = (52, 49). Length ≈ 20.10.
#   With uniform sampling at step navcell*0.5 = 4, steps = ceil(20.1/4) = 6,
#   samples land at i/6 ∈ {0, 1/6, 2/6, 3/6, 4/6, 5/6, 6/6}.
#     t=0    -> (32.00, 47.00)  cell (4, 5)
#     t=1/6  -> (35.33, 47.33)  cell (4, 5)
#     t=2/6  -> (38.67, 47.67)  cell (4, 5)
#     t=3/6  -> (42.00, 48.00)  cell (5, 6)        ← y rounds to 48 → cell (5, 6)
#     t=4/6  -> (45.33, 48.33)  cell (5, 6)
#     t=5/6  -> (48.67, 48.67)  cell (6, 6)
#     t=6/6  -> (52.00, 49.00)  cell (6, 6)
#   None sample cell (5, 5). But the segment is inside cell (5, 5) for
#   t ∈ [0.40, 0.50] (arc ≈ 2.0 px) — between t=2/6 and t=3/6.
#
# At HEAD (uniform sampling): _segment_passable_clear returns true.
#   _refine_waypoint_path then thinks the diagonal segment is clear and
#   keeps a path that crosses cell (5, 5). FAIL.
# After fix (Amanatides-Woo cell traversal): visits cell (5, 5) directly
#   and returns false. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_002_long_path_los_sampling.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-002 long-path LOS sampling (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-002 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "single_cell_wall"
	blocker.center = Vector2(44.0, 44.0)
	blocker.width = 8.0
	blocker.height = 8.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)
	nav_map.rebuild_dirty()

	var blocked_cell := Vector2i(5, 5)
	if nav_map.is_passable_navcell(blocked_cell, pass_mask):
		_failures.append(
			"setup error: cell %s should be impassable after rasterization" % str(blocked_cell)
		)
		return

	var pathfinder := SimNavLongPathfinder.new(nav_map)
	var a := Vector2(32.0, 47.0)
	var b := Vector2(52.0, 49.0)
	var no_excluded: Array[Dictionary] = []
	var clear: Variant = pathfinder.call("_segment_passable_clear", a, b, pass_mask, no_excluded)
	if bool(clear):
		_failures.append(
			"segment %s -> %s reported clear but passes through blocked cell %s — uniform sampling skipped the cell"
			% [str(a), str(b), str(blocked_cell)]
		)
		return

	# Sanity: a segment that does NOT cross cell (5, 5) must still report clear.
	var safe_a := Vector2(32.0, 36.0)
	var safe_b := Vector2(52.0, 36.0)
	var safe_clear: Variant = pathfinder.call("_segment_passable_clear", safe_a, safe_b, pass_mask, no_excluded)
	if not bool(safe_clear):
		_failures.append(
			"segment %s -> %s reported blocked but does not cross any blocked cell" % [str(safe_a), str(safe_b)]
		)
