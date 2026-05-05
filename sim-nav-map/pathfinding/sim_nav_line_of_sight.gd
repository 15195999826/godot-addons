class_name SimNavLineOfSight


static func segment_clear(a: Vector2, b: Vector2, shapes: Array, buffer: float) -> bool:
	for shape in shapes:
		if shape is SimNavObstructionShapeUnit:
			var unit_shape := shape as SimNavObstructionShapeUnit
			var threshold := unit_shape.clearance + buffer
			if _segment_to_point_dist(a, b, unit_shape.center) < threshold:
				return false
		elif shape is SimNavObstructionShapeStatic:
			if _segment_to_obb_dist(a, b, shape as SimNavObstructionShapeStatic, buffer) < buffer:
				return false
	return true


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
