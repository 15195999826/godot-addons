class_name SimNavLineOfSight


# Mirror SimNavVertexPathfinder.EDGE_EXPAND_DELTA so the LOS "inside" boundary
# matches the vertex-graph obstacle radius. Without this a unit whose center
# lies in (clearance, clearance + EDGE_EXPAND_DELTA) of another unit's center
# is treated as outside by LOS but inside by the vertex graph -> all outgoing
# edges get rejected and short_path returns no_route (escape-overlap deadlock,
# 0 A.D. CCmpObstructionManager TestUnitLine directional ray rule).
const EDGE_EXPAND_DELTA: float = 0.5


static func segment_clear(a: Vector2, b: Vector2, shapes: Array, buffer: float) -> bool:
	for shape in shapes:
		var obstruction_shape := shape as SimNavObstructionShape
		if obstruction_shape != null and shape_blocks_segment(a, b, obstruction_shape, buffer):
			return false
	return true


static func first_blocking_shape(a: Vector2, b: Vector2, shapes: Array, buffer: float) -> SimNavObstructionShape:
	for shape in shapes:
		var obstruction_shape := shape as SimNavObstructionShape
		if obstruction_shape != null and shape_blocks_segment(a, b, obstruction_shape, buffer):
			return obstruction_shape
	return null


static func shape_blocks_segment(a: Vector2, b: Vector2, shape: SimNavObstructionShape, buffer: float) -> bool:
	if shape is SimNavObstructionShapeUnit:
		var unit_shape := shape as SimNavObstructionShapeUnit
		return _unit_shape_blocks_segment(a, b, unit_shape, buffer)
	if shape is SimNavObstructionShapeStatic:
		var static_shape := shape as SimNavObstructionShapeStatic
		if static_shape.contains_point_with_clearance(a, buffer):
			return false
		if static_shape.contains_point_with_clearance(b, buffer):
			return true
		return _segment_to_obb_dist(a, b, static_shape, buffer) < buffer
	return false


static func _unit_shape_blocks_segment(
	a: Vector2,
	b: Vector2,
	unit_shape: SimNavObstructionShapeUnit,
	buffer: float
) -> bool:
	var collision_threshold := unit_shape.clearance + buffer
	var inside_threshold := collision_threshold + EDGE_EXPAND_DELTA
	var start_dist := unit_shape.center.distance_to(a)
	var target_dist := unit_shape.center.distance_to(b)
	if start_dist < collision_threshold:
		# 'a' is genuinely overlapping the obstacle. 0 A.D. Geometry.cpp:280-281
		# TestRaySquare is strict binary: `a inside → return false` regardless
		# of where 'b' lies (stay-inside or deeper both unblock). This trusts
		# the push system + reactive blocked_recovery to keep units from
		# drifting toward obstacle center over multiple frames. A lab-side
		# stay-or-deeper guard violates this — it appears to "protect" against
		# overlap drift but actually blocks the per-frame motion candidate
		# whenever the segment's tangent geometry briefly heads inward, leaving
		# the unit stuck in a real overlap with no escape.
		return false
	if start_dist <= inside_threshold:
		# Boundary band (between real collision ring and vertex-graph outset).
		# The single segment-to-point check below also covers the "b deep
		# inside collision ring" case (t clamps to 1, sep collapses to
		# target_dist). Do NOT add a separate `target_dist <= collision_threshold`
		# early-return here — that wrongly blocks a per-frame motion candidate
		# whose tail is 21.84 (just inside) when start is 22.03 (just outside),
		# even though the segment overall is heading away from the obstacle.
		return _segment_to_point_dist(a, b, unit_shape.center) < collision_threshold - EDGE_EXPAND_DELTA
	# 'a' fully outside the outset ring. Standard collision check.
	if target_dist <= collision_threshold:
		return true
	return _segment_to_point_dist(a, b, unit_shape.center) < collision_threshold


static func _segment_to_point_dist(a: Vector2, b: Vector2, point: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func _segment_to_obb_dist(a: Vector2, b: Vector2, obb: SimNavObstructionShapeStatic, buffer: float) -> float:
	var enclose_radius := sqrt(obb.width * obb.width + obb.height * obb.height) * 0.5
	var center_dist := _segment_to_point_dist(a, b, obb.center)
	if center_dist >= enclose_radius + buffer:
		return center_dist - enclose_radius

	var local_a: Vector2
	var local_b: Vector2
	if absf(obb.rotation_rad) < 0.000001:
		local_a = a - obb.center
		local_b = b - obb.center
	else:
		var u := Vector2(cos(obb.rotation_rad), sin(obb.rotation_rad))
		var v := Vector2(-sin(obb.rotation_rad), cos(obb.rotation_rad))
		local_a = Vector2((a - obb.center).dot(u), (a - obb.center).dot(v))
		local_b = Vector2((b - obb.center).dot(u), (b - obb.center).dot(v))
	return _segment_to_aabb_dist(local_a, local_b, obb.width * 0.5, obb.height * 0.5)


static func _segment_to_aabb_dist(a: Vector2, b: Vector2, hw: float, hh: float) -> float:
	if absf(a.x) <= hw and absf(a.y) <= hh:
		return 0.0
	if absf(b.x) <= hw and absf(b.y) <= hh:
		return 0.0

	var t_min := 0.0
	var t_max := 1.0
	var dx := b.x - a.x
	var dy := b.y - a.y

	if absf(dx) > 0.000000001:
		var inv_dx := 1.0 / dx
		var tx1 := (-hw - a.x) * inv_dx
		var tx2 := (hw - a.x) * inv_dx
		if tx1 > tx2:
			var tmp_x := tx1
			tx1 = tx2
			tx2 = tmp_x
		t_min = maxf(t_min, tx1)
		t_max = minf(t_max, tx2)
	elif a.x < -hw or a.x > hw:
		return _segment_aabb_no_intersect_dist(a, b, hw, hh)

	if absf(dy) > 0.000000001:
		var inv_dy := 1.0 / dy
		var ty1 := (-hh - a.y) * inv_dy
		var ty2 := (hh - a.y) * inv_dy
		if ty1 > ty2:
			var tmp_y := ty1
			ty1 = ty2
			ty2 = tmp_y
		t_min = maxf(t_min, ty1)
		t_max = minf(t_max, ty2)
	elif a.y < -hh or a.y > hh:
		return _segment_aabb_no_intersect_dist(a, b, hw, hh)

	if t_min <= t_max:
		return 0.0
	return _segment_aabb_no_intersect_dist(a, b, hw, hh)


static func _segment_aabb_no_intersect_dist(a: Vector2, b: Vector2, hw: float, hh: float) -> float:
	var dxa := maxf(absf(a.x) - hw, 0.0)
	var dya := maxf(absf(a.y) - hh, 0.0)
	var min_dist := sqrt(dxa * dxa + dya * dya)

	var dxb := maxf(absf(b.x) - hw, 0.0)
	var dyb := maxf(absf(b.y) - hh, 0.0)
	min_dist = minf(min_dist, sqrt(dxb * dxb + dyb * dyb))

	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(-hw, -hh)))
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(hw, -hh)))
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(hw, hh)))
	min_dist = minf(min_dist, _segment_to_point_dist(a, b, Vector2(-hw, hh)))
	return min_dist
