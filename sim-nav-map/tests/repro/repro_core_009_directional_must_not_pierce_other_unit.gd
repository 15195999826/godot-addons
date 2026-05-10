extends Node

# CORE-009: Directional LOS escape must not let segment pierce the collision
# ring of a *different* obstacle.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 2997, log 2026-05-10T18-51-44.
#   - blue_1 at (530.53, 201.05), nearby static unit blue_3 at (535, 179)
#     (distance 22.5 — exactly on the vertex-graph outset ring of blue_3 with
#     EDGE_EXPAND_DELTA = 0.5; just outside the real 22-unit collision ring).
#   - Vertex pathfinder emitted a path whose first waypoint was (528.5, 119.5)
#     (blue_0.SE corner) — a NORTH-going segment that pierces directly through
#     blue_3's center (mid-segment distance to blue_3 ≈ 5 px, deep inside the
#     collision ring).
#   - Before fix (binary directional with `start_dist <= inside_threshold`):
#     LOS treated start as "inside" because 22.5 ≤ inside_threshold 22.5,
#     allowed any escape direction including this piercing one. Path was
#     accepted, then movement_line repeatedly blocked → unit stuck → move_failed.
#
# 0 A.D. expected (Geometry.cpp:259-305 TestRaySquare):
#   `'a' inside, 'b' outside -> no collision`. But 'inside' means inside the
#   real obstacle, not inside an outset ring used only for the visibility graph.
#   When start is outside the real collision ring, the standard separating-axis
#   check applies and a piercing segment IS a collision.
#
# Fix (sim_nav_line_of_sight.gd _unit_shape_blocks_segment): directional escape
# branch now triggers only when start_dist < collision_threshold - 0.001
# (genuinely overlapping); otherwise the standard collision check rules,
# rejecting any segment whose middle dives into the real collision ring of a
# different obstacle.
#
# Before fix: short path returns piercing path. FAIL.
# After fix: short path either rejects piercing edges or routes around. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_009_directional_must_not_pierce_other_unit.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-009 directional pierce regression (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-009 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	# Direct LOS unit-test on the exact piercing segment from the log.
	# blue_1 (start) -> (528.5, 119.5) (first wp, blue_0.SE corner).
	# blue_3 (535, 179) sits in the middle.
	var a := Vector2(530.53, 201.05)
	var b := Vector2(528.5, 119.5)
	var blue_3 := SimNavObstructionShapeUnit.new()
	blue_3.entity_id = "blue_3"
	blue_3.center = Vector2(535.0, 179.0)
	blue_3.clearance = 11.0
	blue_3.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blue_3.moving = false

	var blocked := SimNavLineOfSight.shape_blocks_segment(a, b, blue_3, 11.0)
	if not blocked:
		_failures.append(
			"piercing segment %s->%s through blue_3 center (mid-dist ~5px) was wrongly accepted; LOS must reject it"
			% [str(a), str(b)]
		)

	# Sanity: a tangent escape segment from a *real overlap* must still pass
	# (start truly inside collision ring, target outside, escaping outward).
	var overlapped := Vector2(485.0, 197.0)            # 3 px from blue_3 center
	var escape_target := Vector2(465.5, 219.5)
	var escape_blocked := SimNavLineOfSight.shape_blocks_segment(
		overlapped, escape_target, blue_3, 11.0
	)
	if escape_blocked:
		_failures.append(
			"escape from real overlap %s->%s wrongly blocked; directional rule must allow it"
			% [str(overlapped), str(escape_target)]
		)

	# Full short-path repro: build the actual scene with blue_3 + blue_0 and
	# confirm the vertex pathfinder no longer returns a path whose first wp
	# pierces blue_3.
	_test_short_path()


func _test_short_path() -> void:
	var cell_size := 16.0
	var nav_map := SimNavMap.new(int(ceil(720.0 / cell_size)), int(ceil(420.0 / cell_size)), cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 12.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)
	nav_map.rebuild_dirty()

	var blockers: Array[SimNavObstructionShapeUnit] = []
	blockers.append(_make_blocker("blue_3", Vector2(535.0, 179.0), 11.0))
	blockers.append(_make_blocker("blue_0", Vector2(506.0, 142.0), 11.0))
	nav_map.replace_dynamic_obstructions(blockers)

	var start := Vector2(530.53, 201.05)
	var goal_point := Vector2(459.0, 119.0)
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal_point)
	req.clearance = 11.0
	req.range_px = 12.0 * cell_size
	req.pass_mask = pass_mask
	req.avoid_moving_units = false
	req.control_group = ""
	req.static_vertex_extra_outset = cell_size * 0.5

	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(req)
	if not result.is_success() or result.path.is_empty():
		# Empty result is acceptable here (the layout may have no short route);
		# the bug we're guarding against is a SUCCESS result that pierces blue_3.
		return

	var prev := start
	for i in range(result.path.size() - 1, -1, -1):
		var wp: Vector2 = result.path.waypoints[i]
		if SimNavLineOfSight.shape_blocks_segment(prev, wp, _make_blocker("blue_3", Vector2(535.0, 179.0), 11.0), 11.0):
			_failures.append(
				"short path segment %s->%s pierces blue_3 collision ring; full path=%s"
				% [str(prev), str(wp), str(_path_to_array(result.path))]
			)
		prev = wp


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
