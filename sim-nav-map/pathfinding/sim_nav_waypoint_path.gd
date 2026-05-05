class_name SimNavWaypointPath
extends RefCounted


var waypoints: PackedVector2Array = PackedVector2Array()


func size() -> int:
	return waypoints.size()


func is_empty() -> bool:
	return waypoints.is_empty()


func back() -> Vector2:
	if waypoints.is_empty():
		push_error("[SimNavWaypointPath] back() called on empty path")
		return Vector2.ZERO
	return waypoints[waypoints.size() - 1]


func pop_back() -> Vector2:
	if waypoints.is_empty():
		push_error("[SimNavWaypointPath] pop_back() called on empty path")
		return Vector2.ZERO
	var point := waypoints[waypoints.size() - 1]
	waypoints.remove_at(waypoints.size() - 1)
	return point


func push_back(point: Vector2) -> void:
	waypoints.append(point)


func clear() -> void:
	waypoints = PackedVector2Array()
