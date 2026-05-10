extends Node

# CORE-007: Static obstruction rasterization scans full grid
#
# Bug reproduced here:
#   - sim_nav_map.gd:404-421 _rasterize_static_obstruction iterates every
#     navcell on every passability class, regardless of the OBB's AABB.
#   - 0 A.D. only iterates the OBB's AABB (clipped to map bounds).
#
# Repro: rasterize one small static OBB (16×16) on a 256×256 grid versus the
# same OBB on a 1024×1024 grid. Area ratio is 16×. With AABB-clipped raster
# the work is bounded by the OBB AABB and time should be roughly equal. With
# full-grid scan time scales with the grid.
#
# At HEAD: time ratio > 5×. FAIL.
# After fix: time ratio ≤ 2× (within noise). PASS.
#
# Note: numeric thresholds are calibrated against the area ratio (16×), not
# absolute milliseconds, so the test is portable across machines.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_007_static_rasterize_aabb.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-007 rasterize scaling (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-007 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	# Warm up to amortize one-time JIT / allocator costs.
	_time_rasterize(64)

	var t_small := _time_rasterize(256)
	var t_large := _time_rasterize(1024)
	var divisor := maxi(t_small, 1)
	var ratio := float(t_large) / float(divisor)
	var max_ratio := 5.0

	print("CORE-007 rasterize timing: small_256² = %d µs, large_1024² = %d µs, ratio = %.2fx" % [t_small, t_large, ratio])

	if ratio > max_ratio:
		_failures.append(
			"rasterize time grew %.1fx going from 256² to 1024² (small=%d µs, large=%d µs); expected ≤ %.1fx with AABB-clipped raster"
			% [ratio, t_small, t_large, max_ratio]
		)


func _time_rasterize(grid_dim: int) -> int:
	var nav_map := SimNavMap.new(grid_dim, grid_dim, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	nav_map.register_passability_class(ground)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "small_block"
	blocker.center = Vector2(100.0, 100.0)
	blocker.width = 16.0
	blocker.height = 16.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)

	var t0 := Time.get_ticks_usec()
	nav_map.rebuild_dirty()
	return Time.get_ticks_usec() - t0
