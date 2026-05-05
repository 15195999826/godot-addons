class_name SimNavPathGoal
extends RefCounted


const _EPSILON: float = 0.0001

enum Type {
	POINT,
	CIRCLE,
	INVERTED_CIRCLE,
	SQUARE,
	INVERTED_SQUARE,
}

var type: int = Type.POINT
var center: Vector2 = Vector2.ZERO
var hw: float = 0.0
var hh: float = 0.0
var u: Vector2 = Vector2(1.0, 0.0)
var v: Vector2 = Vector2(0.0, 1.0)
var maxdist: float = 0.0


func _init(p_type: int = Type.POINT, p_center: Vector2 = Vector2.ZERO) -> void:
	type = p_type
	center = p_center


func navcell_contains_goal(nav_map: SimNavMap, coord: Vector2i) -> bool:
	if nav_map == null or not nav_map.is_valid_navcell(coord):
		return false
	var min_pos := nav_map.origin + Vector2(float(coord.x), float(coord.y)) * nav_map.navcell_size
	var max_pos := min_pos + Vector2(nav_map.navcell_size, nav_map.navcell_size)
	match type:
		Type.POINT:
			return nav_map.world_to_navcell(center) == coord
		Type.CIRCLE:
			return _navcell_contains_circle(min_pos, max_pos, true)
		Type.INVERTED_CIRCLE:
			return _navcell_contains_circle(min_pos, max_pos, false)
		Type.SQUARE:
			return _navcell_contains_square(min_pos, max_pos, true)
		Type.INVERTED_SQUARE:
			return _navcell_contains_square(min_pos, max_pos, false)
	return false


func contains_point(point: Vector2) -> bool:
	match type:
		Type.POINT:
			return point.distance_squared_to(center) < 0.0001
		Type.CIRCLE:
			return point.distance_to(center) <= hw
		Type.INVERTED_CIRCLE:
			return point.distance_to(center) >= hw
		Type.SQUARE:
			return _point_is_in_square(point)
		Type.INVERTED_SQUARE:
			return not _point_is_in_square(point)
	return false


func distance_to_point(point: Vector2) -> float:
	var delta := point - center
	match type:
		Type.POINT:
			return delta.length()
		Type.CIRCLE:
			return maxf(0.0, delta.length() - hw)
		Type.INVERTED_CIRCLE:
			return maxf(0.0, hw - delta.length())
		Type.SQUARE:
			return _distance_to_square(point, false)
		Type.INVERTED_SQUARE:
			return _distance_to_square(point, true)
	return 0.0


func nearest_point_on_goal(point: Vector2) -> Vector2:
	var delta := point - center
	match type:
		Type.POINT:
			return center
		Type.CIRCLE:
			if delta.length() <= hw:
				return point
			return center + _safe_direction(delta) * hw
		Type.INVERTED_CIRCLE:
			if delta.length() >= hw:
				return point
			return center + _safe_direction(delta) * hw
		Type.SQUARE:
			if _point_is_in_square(point):
				return point
			return _nearest_point_on_square(point)
		Type.INVERTED_SQUARE:
			if not _point_is_in_square(point):
				return point
			return _nearest_point_on_square_edge(point)
	return point


func clone() -> SimNavPathGoal:
	var cloned_goal := SimNavPathGoal.new(type, center)
	cloned_goal.hw = hw
	cloned_goal.hh = hh
	cloned_goal.u = u
	cloned_goal.v = v
	cloned_goal.maxdist = maxdist
	return cloned_goal


func copy_from(other: SimNavPathGoal) -> void:
	if other == null:
		return
	type = other.type
	center = other.center
	hw = other.hw
	hh = other.hh
	u = other.u
	v = other.v
	maxdist = other.maxdist


static func point(p_center: Vector2) -> SimNavPathGoal:
	return SimNavPathGoal.new(Type.POINT, p_center)


static func circle(p_center: Vector2, radius: float) -> SimNavPathGoal:
	var goal := SimNavPathGoal.new(Type.CIRCLE, p_center)
	goal.hw = maxf(0.0, radius)
	goal.hh = goal.hw
	return goal


static func inverted_circle(p_center: Vector2, radius: float) -> SimNavPathGoal:
	var goal := SimNavPathGoal.new(Type.INVERTED_CIRCLE, p_center)
	goal.hw = maxf(0.0, radius)
	goal.hh = goal.hw
	return goal


static func square(p_center: Vector2, half_width: float, half_height: float, rotation_rad: float = 0.0) -> SimNavPathGoal:
	var goal := SimNavPathGoal.new(Type.SQUARE, p_center)
	goal._set_square_axes(half_width, half_height, rotation_rad)
	return goal


static func inverted_square(p_center: Vector2, half_width: float, half_height: float, rotation_rad: float = 0.0) -> SimNavPathGoal:
	var goal := SimNavPathGoal.new(Type.INVERTED_SQUARE, p_center)
	goal._set_square_axes(half_width, half_height, rotation_rad)
	return goal


func _navcell_contains_circle(min_pos: Vector2, max_pos: Vector2, inside: bool) -> bool:
	if inside:
		var nearest := Vector2(clampf(center.x, min_pos.x, max_pos.x), clampf(center.y, min_pos.y, max_pos.y))
		return nearest.distance_to(center) <= hw
	var corners := _rect_corners(min_pos, max_pos)
	for corner in corners:
		if corner.distance_to(center) >= hw:
			return true
	return false


func _navcell_contains_square(min_pos: Vector2, max_pos: Vector2, inside: bool) -> bool:
	if inside:
		var nearest := Vector2(clampf(center.x, min_pos.x, max_pos.x), clampf(center.y, min_pos.y, max_pos.y))
		return _point_is_in_square(nearest)
	var corners := _rect_corners(min_pos, max_pos)
	for corner in corners:
		if not _point_is_in_square(corner):
			return true
	return false


func _rect_corners(min_pos: Vector2, max_pos: Vector2) -> Array[Vector2]:
	return [
		Vector2(min_pos.x, min_pos.y),
		Vector2(max_pos.x, min_pos.y),
		Vector2(min_pos.x, max_pos.y),
		Vector2(max_pos.x, max_pos.y),
	]


func _point_is_in_square(point: Vector2) -> bool:
	var delta := point - center
	return absf(delta.dot(u)) <= hw + _EPSILON and absf(delta.dot(v)) <= hh + _EPSILON


func _distance_to_square(point: Vector2, inverted: bool) -> float:
	var delta := point - center
	var local_x := delta.dot(u)
	var local_y := delta.dot(v)
	var outside_x := maxf(absf(local_x) - hw, 0.0)
	var outside_y := maxf(absf(local_y) - hh, 0.0)
	if not inverted:
		return Vector2(outside_x, outside_y).length()
	if outside_x > 0.0 or outside_y > 0.0:
		return 0.0
	return minf(hw - absf(local_x), hh - absf(local_y))


func _nearest_point_on_square(point: Vector2) -> Vector2:
	var delta := point - center
	var local_x := clampf(delta.dot(u), -hw, hw)
	var local_y := clampf(delta.dot(v), -hh, hh)
	return center + u * local_x + v * local_y


func _nearest_point_on_square_edge(point: Vector2) -> Vector2:
	var delta := point - center
	var local_x := clampf(delta.dot(u), -hw, hw)
	var local_y := clampf(delta.dot(v), -hh, hh)
	var dist_x := hw - absf(local_x)
	var dist_y := hh - absf(local_y)
	if dist_x <= dist_y:
		local_x = signf(local_x) * hw
		if absf(local_x) < 0.0001:
			local_x = hw
	else:
		local_y = signf(local_y) * hh
		if absf(local_y) < 0.0001:
			local_y = hh
	return center + u * local_x + v * local_y


func _set_square_axes(half_width: float, half_height: float, rotation_rad: float) -> void:
	hw = maxf(0.0, half_width)
	hh = maxf(0.0, half_height)
	u = Vector2(cos(rotation_rad), sin(rotation_rad)).normalized()
	v = Vector2(-u.y, u.x)


func _safe_direction(delta: Vector2) -> Vector2:
	if delta.length_squared() < 0.0001:
		return Vector2(1.0, 0.0)
	return delta.normalized()
