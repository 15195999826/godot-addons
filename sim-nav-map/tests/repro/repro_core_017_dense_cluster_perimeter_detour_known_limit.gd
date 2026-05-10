extends Node

# CORE-017: KNOWN LIMITATION — dense unit cluster forces perimeter detour.
#
# This is NOT a bug in lab — it mirrors 0 A.D. VertexPathfinder's behavior
# and is inherent to visibility-graph pathfinders. Lock-in test so future
# tweaks to covered-vertex filtering don't accidentally "fix" it in a way
# that lets A* pick illegal corners.
#
# Bug reproduced here:
#   - User-reported scenario: 4 stationary units around 1 central unit, with
#     visible gaps between perimeter pairs. User expects shortest path to
#     thread through those gaps; instead path goes the long way around the
#     outside of one perimeter unit.
#   - Concrete case from log 2026-05-10T20-22-44 tick 17319:
#     blue_0 at (534, 208) walking to (547, 73). blue_5 stationary at
#     (530, 167) blocks the direct line. The "ideal" detour blue_5.SE
#     (552.5, 189.5) → blue_5.NE (552.5, 144.5) → goal is impossible because
#     blue_5.SE sits inside blue_4's (567, 202) collision ring (Euclidean
#     distance 19.14 < 22 collision_threshold).
#   - LOS rejects any segment ending at blue_5.SE because its endpoint pierces
#     blue_4's ring; covered-vertex filter (CORE-008) also drops it from the
#     vertex graph. With blue_5.SE unavailable, A* must detour around blue_4
#     (SW → SE → NE corner triangle, 4 waypoints).
#
# 0 A.D. expected (VertexPathfinder.cpp:727-734):
#   `m_Vertexes[j].status = Vertex::CLOSED` for any vertex inside another
#   obstacle's edgeSquare. Same Chebyshev geometry as lab's circle filter for
#   axis-aligned configurations. 0 A.D. produces the same detour for the same
#   setup — this is not lab divergence.
#
# Fix attempted: NONE. This is inherent to visibility-graph algorithms in
# dense clusters. Mitigations would require:
#   - Mid-corridor / Voronoi-derived vertices (large core change), OR
#   - User spaces units further apart (gap > unit clearance + buffer), OR
#   - Switch to a non-visibility pathfinder for short-range cluster traversal.
#
# Before/After: identical. This repro asserts the behavior remains consistent
# (path goes the perimeter detour and target is reachable via a 4-waypoint
# path). Future refactors of covered-vertex filtering must either preserve
# this behavior or document why it's safe to allow the previously-illegal
# vertex.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_017_dense_cluster_perimeter_detour_known_limit.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-017 dense cluster detour locked (known limitation)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-017 behavior changed: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var cell_size := 16.0
	var nav_map := SimNavMap.new(int(ceil(720.0 / cell_size)), int(ceil(420.0 / cell_size)), cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 12.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)
	nav_map.rebuild_dirty()

	var blockers: Array[SimNavObstructionShapeUnit] = []
	for entry in [
		["blue_3", Vector2(497.0, 207.0)],
		["blue_5", Vector2(530.0, 167.0)],
		["blue_4", Vector2(567.0, 202.0)],
		["blue_1", Vector2(531.5, 244.5)],
	]:
		var s := SimNavObstructionShapeUnit.new()
		s.entity_id = entry[0]
		s.center = entry[1]
		s.clearance = 11.0
		s.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
		s.moving = false
		blockers.append(s)
	nav_map.replace_dynamic_obstructions(blockers)

	var start := Vector2(534.0, 208.0)
	var goal := Vector2(547.0, 73.0)
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal)
	req.clearance = 11.0
	req.range_px = 12.0 * cell_size
	req.pass_mask = pass_mask
	req.avoid_moving_units = false
	req.control_group = ""
	req.obstruction_filter = SimNavObstructionFilter.for_short_path(false, "")
	req.obstruction_filter.ignored_entity_id = "blue_0"
	req.static_vertex_extra_outset = cell_size * 0.5

	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(req)
	if not result.is_success():
		_failures.append("expected success, got %s/%s" % [str(result.status), str(result.failure_reason)])
		return

	# Path should reach the goal (waypoint[0]).
	var first_wp: Vector2 = result.path.waypoints[0]
	if first_wp.distance_to(goal) > 0.5:
		_failures.append("path should end at goal; got %s" % str(first_wp))

	# Path takes the blue_4-perimeter detour, not the blocked ideal route.
	# blue_4 corners: SW(544.5, 224.5), SE(589.5, 224.5), NE(589.5, 179.5).
	# The first consumed waypoint should be blue_4.SW (a valid uncovered corner
	# closer to start than blue_5.NE which sits behind blue_5's blocking line).
	var first_consumed: Vector2 = result.path.back()
	if first_consumed.distance_to(Vector2(544.5, 224.5)) > 0.5:
		_failures.append(
			"first consumed waypoint changed; expected blue_4.SW (544.5, 224.5), got %s. If A* now picks a more direct corner, verify it is geometrically reachable (LOS clear)."
			% str(first_consumed)
		)

	# Sanity: blue_5.SE (552.5, 189.5) — the "ideal" mid-corner — must remain
	# unreachable as either a vertex (covered by blue_4) or as a segment
	# endpoint (inside blue_4's collision ring).
	var blue_5_SE := Vector2(552.5, 189.5)
	var blue_4_shape: SimNavObstructionShapeUnit = blockers[2]
	var sse_dist_to_blue_4 := blue_5_SE.distance_to(blue_4_shape.center)
	if sse_dist_to_blue_4 > 22.0:
		_failures.append(
			"blue_5.SE corner geometry shifted: distance to blue_4 was 19.14, now %.2f. If positions changed, this scenario no longer demonstrates the cover cascade."
			% sse_dist_to_blue_4
		)
	var blocked_to_sse := SimNavLineOfSight.shape_blocks_segment(start, blue_5_SE, blue_4_shape, 11.0)
	if not blocked_to_sse:
		_failures.append("LOS to blue_5.SE no longer blocked by blue_4 — cover cascade broken; path could now go shorter through blue_5.SE")
