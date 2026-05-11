extends Node

# CORE-018: short path threads passable gap between two adjacent unit obstacles
#
# Bug reproduced here:
#   - 现象：blue_1 at (171.7, 238.4) walks to (243, 164) through a goal-side
#     cluster of 5 stationary blues. The geometrically shortest viable path
#     `start → midpoint(blue_4, blue_0) (184.65, 217.4) → goal` is 103.77 px.
#     Pre-fix, the short pathfinder returned a perimeter detour of ~278 px
#     (~2.69× optimal) because the gap midpoint was not a vertex in its
#     visibility graph; only 4 outset corners per obstacle were registered,
#     and the goal-side outsets were either covered or required additional
#     detour to reach.
#   - 根因：`sim_nav_vertex_pathfinder.gd:_collect_visibility_inputs` produced
#     only obstacle outset corners. Pair-wise gap midpoints between adjacent
#     units were missing from the search graph.
#
# 0 A.D. expected (`VertexPathfinder.cpp:626-665`, 727-734):
#   Same vertex set scheme (4 outset corners per obstacle) and same
#   covered-vertex filter. 0 A.D. has the **same algorithmic limitation** but
#   masks the visible symptom via three layers that the lab does not have:
#     1. `CCmpFormation` picks reachable formation slots.
#     2. `LongPathfinder::ImprovePathWaypoints` keeps turning points whose
#        non-adjacent waypoint chain remains static-blocked.
#     3. Unit run multiplier compresses detour visuals.
#   The lab lacks all three, so the limitation visibly bites every dense
#   cluster manual test. Adding pair-wise gap midpoint vertices is a
#   **positive lab-only deviation** that closes the visible symptom while
#   remaining a clean geometric construction (no policy / no magic number).
#
# Before fix: short path length ≥ 270 px (perimeter detour). FAIL of the
# `length < 130 px` bound below.
# After fix: short path length ≈ 103.77 px (threads the gap midpoint). PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_018_visibility_graph_gap_threading.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-018 short path threads inter-unit gap midpoint")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-018 gap threading regressed: %s" % "; ".join(_failures))
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

	# Path ends at goal.
	var final_wp: Vector2 = result.path.waypoints[0]
	if final_wp.distance_to(goal) > 0.5:
		_failures.append("path should end at goal; got %s" % str(final_wp))

	# Post-fix: path threads the gap midpoint, so total length is near optimal
	# (geometric optimum 103.77 px). Allow up to 130 px to absorb minor
	# clearance-snap noise but reject any perimeter detour (~270 px+).
	var path_length := start.distance_to(result.path.back())
	for i in range(result.path.waypoints.size() - 1, 0, -1):
		path_length += result.path.waypoints[i].distance_to(result.path.waypoints[i - 1])
	if path_length >= 130.0:
		_failures.append(
			"path length %.2f indicates a perimeter detour, expected gap-threading path < 130 px (geometric optimum ≈ 103.77)"
			% path_length
		)

	# Ensure the actual midpoint of the blue_4 ↔ blue_0 gap is in (or near to)
	# the path. The midpoint is the turning point the fix is designed to
	# expose, so the path must traverse close to it.
	var blue_4_pos := Vector2(201.4, 236.8)
	var blue_0_pos := Vector2(167.9, 198.0)
	var midpoint := (blue_4_pos + blue_0_pos) * 0.5
	var min_dist_to_midpoint := INF
	for wp in result.path.waypoints:
		min_dist_to_midpoint = minf(min_dist_to_midpoint, (wp as Vector2).distance_to(midpoint))
	if min_dist_to_midpoint > 10.0:
		_failures.append(
			"path does not pass near gap midpoint (%.2f px away); pair-wise gap midpoint vertex generation regressed"
			% min_dist_to_midpoint
		)

	# Sanity: the gap midpoint is genuinely passable.
	var mid_to_blue_4 := midpoint.distance_to(blue_4_pos)
	var mid_to_blue_0 := midpoint.distance_to(blue_0_pos)
	if mid_to_blue_4 < 22.0 or mid_to_blue_0 < 22.0:
		_failures.append(
			"midpoint sanity broken — distance to blue_4=%.2f / blue_0=%.2f, both should be > 22"
			% [mid_to_blue_4, mid_to_blue_0]
		)
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
