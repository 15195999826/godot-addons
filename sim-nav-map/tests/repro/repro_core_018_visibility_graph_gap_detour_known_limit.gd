extends Node

# CORE-018: KNOWN LIMITATION — visibility-graph short pathfinder cannot
# thread a passable gap between two adjacent obstacles, because the gap's
# midpoint is not a vertex in the search graph.
#
# This is NOT a bug in lab — it mirrors 0 A.D. VertexPathfinder's behavior
# and is inherent to visibility-graph algorithms whose vertex set is only
# obstacle outset corners. Lock-in test so future tweaks to vertex
# collection / covered-vertex filtering don't silently change the
# observable behavior.
#
# Bug reproduced here (from log
# zero_ad_rts_lab_2026-05-11T02-33-22_tick_6144.json tick 5628):
#   blue_1 at (171.7, 238.4) walks to (243, 164). Five stationary blues
#   sit around the goal:
#     blue_4 (201.4, 236.8)  ← directly on the line, blocks long segment
#     blue_0 (167.9, 198.0)  ← north-west of blue_4
#     blue_3 (150.5, 280.2)
#     blue_2 (132.0, 236.5)
#     blue_5 (193.5, 280.1)
#   The geometrically shortest viable path is
#     start → (184.65, 217.4) [blue_4 ↔ blue_0 gap midpoint] → goal
#   total 103.77 px. Both segments clear all five blockers by ≥ 24 px
#   (combined clearance threshold is 22).
#   But (184.65, 217.4) is not a vertex in the visibility graph, and every
#   blue_4 outset that could be a turning point is either on the wrong
#   side of blue_4 or covered by blue_0's clearance ring (filtered by
#   CORE-008's covered-vertex rule). A* can only assemble a perimeter
#   detour, ~278 px, ~2.7× optimal.
#
# 0 A.D. expected (VertexPathfinder.cpp:626-665, 727-734):
#   Same vertex set. Same covered-vertex filter. Same detour. 0 A.D.
#   normally avoids the visible symptom via formation slot selection,
#   less-aggressive long-path simplification, and run multipliers — all
#   of which the lab does not currently have. See
#   docs/issues/core-018-visibility-graph-gap-detour.md for the fix
#   option discussion.
#
# Fix attempted: NONE. Deferred to a later core optimization milestone.
# This repro asserts the current limited behavior remains stable.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_018_visibility_graph_gap_detour_known_limit.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-018 visibility-graph gap detour locked (known limitation)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-018 behavior changed: %s" % "; ".join(_failures))
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
		["blue_0", Vector2(167.9, 198.0)],
		["blue_2", Vector2(132.0, 236.5)],
		["blue_3", Vector2(150.5, 280.2)],
		["blue_4", Vector2(201.4, 236.8)],
		["blue_5", Vector2(193.5, 280.1)],
	]:
		var shape := SimNavObstructionShapeUnit.new()
		shape.entity_id = entry[0]
		shape.center = entry[1]
		shape.clearance = 11.0
		shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
		shape.moving = false
		blockers.append(shape)
	nav_map.replace_dynamic_obstructions(blockers)

	var start := Vector2(171.7, 238.4)
	var goal := Vector2(243.0, 164.0)
	var req := SimNavShortPathRequest.new()
	req.start = start
	req.goal = SimNavPathGoal.point(goal)
	req.clearance = 11.0
	req.range_px = 56.0 * cell_size
	req.pass_mask = pass_mask
	req.avoid_moving_units = false
	req.control_group = ""
	req.obstruction_filter = SimNavObstructionFilter.for_short_path(false, "")
	req.obstruction_filter.ignored_entity_id = "blue_1"
	req.static_vertex_extra_outset = cell_size * 0.5

	var result := SimNavVertexPathfinder.new(nav_map).compute_short_path_result(req)
	if not result.is_success():
		_failures.append("expected success, got %s/%s" % [str(result.status), str(result.failure_reason)])
		return

	# Path goes to the goal (waypoint[0]).
	var final_wp: Vector2 = result.path.waypoints[0]
	if final_wp.distance_to(goal) > 0.5:
		_failures.append("path should end at goal; got %s" % str(final_wp))

	# Path length is at least 200 px — i.e. it's clearly a perimeter detour,
	# not anything near the geometrically optimal 103.77 px route through the
	# blue_4 ↔ blue_0 gap.
	var path_length := start.distance_to(result.path.back())
	for i in range(result.path.waypoints.size() - 1, 0, -1):
		path_length += result.path.waypoints[i].distance_to(result.path.waypoints[i - 1])
	if path_length < 200.0:
		_failures.append(
			"path is shorter than the documented 278 px detour (got %.2f); if a recent core change made A* find a shorter route, update CORE-018 docs and either tighten this bound or convert to a positive 'gap threading works' test"
			% path_length
		)

	# Sanity: the gap midpoint between blue_4 and blue_0 is genuinely passable.
	# This guards against tests passing for the wrong reason (e.g. someone
	# moved an obstacle and the midpoint is no longer mid-gap).
	var blue_4_pos := Vector2(201.4, 236.8)
	var blue_0_pos := Vector2(167.9, 198.0)
	var midpoint := (blue_4_pos + blue_0_pos) * 0.5
	var mid_to_blue_4 := midpoint.distance_to(blue_4_pos)
	var mid_to_blue_0 := midpoint.distance_to(blue_0_pos)
	if mid_to_blue_4 < 22.0 or mid_to_blue_0 < 22.0:
		_failures.append(
			"midpoint sanity broken — distance to blue_4=%.2f / blue_0=%.2f, both should be > 22"
			% [mid_to_blue_4, mid_to_blue_0]
		)
	# And the segments through it should be clear of every blocker.
	for shape in blockers:
		var d_a := _segment_to_point_distance(start, midpoint, shape.center)
		var d_b := _segment_to_point_distance(midpoint, goal, shape.center)
		if d_a < 22.0:
			_failures.append("midpoint sanity: start→midpoint segment grazes %s by %.2f" % [shape.entity_id, d_a])
		if d_b < 22.0:
			_failures.append("midpoint sanity: midpoint→goal segment grazes %s by %.2f" % [shape.entity_id, d_b])


func _segment_to_point_distance(p1: Vector2, p2: Vector2, p: Vector2) -> float:
	var d := p2 - p1
	var len_sq := d.length_squared()
	if len_sq < 1.0e-9:
		return p.distance_to(p1)
	var t: float = clampf((p - p1).dot(d) / len_sq, 0.0, 1.0)
	var closest := p1 + d * t
	return p.distance_to(closest)
