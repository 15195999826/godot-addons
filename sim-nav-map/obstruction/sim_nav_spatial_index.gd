class_name SimNavSpatialIndex
extends RefCounted


var cell_size: float = 64.0

var _cells: Dictionary = {}
var _bounds_by_tag: Dictionary = {}


func _init(p_cell_size: float = 64.0) -> void:
	cell_size = maxf(1.0, p_cell_size)


func clear() -> void:
	_cells.clear()
	_bounds_by_tag.clear()


func add(tag: int, min_pos: Vector2, max_pos: Vector2) -> void:
	if tag <= 0:
		return
	if _bounds_by_tag.has(tag):
		remove(tag)
	var rect := _make_rect(min_pos, max_pos)
	_bounds_by_tag[tag] = rect
	for cell in _cells_for_rect(rect):
		var bucket: Array = _cells.get(cell, [])
		var pos := bucket.bsearch(tag)
		if pos >= bucket.size() or bucket[pos] != tag:
			bucket.insert(pos, tag)
		_cells[cell] = bucket


func remove(tag: int) -> bool:
	if not _bounds_by_tag.has(tag):
		return false
	var rect := _bounds_by_tag[tag] as Rect2
	for cell in _cells_for_rect(rect):
		var bucket: Array = _cells.get(cell, [])
		var pos := bucket.bsearch(tag)
		if pos < bucket.size() and bucket[pos] == tag:
			bucket.remove_at(pos)
		if bucket.is_empty():
			_cells.erase(cell)
		else:
			_cells[cell] = bucket
	_bounds_by_tag.erase(tag)
	return true


func move(tag: int, min_pos: Vector2, max_pos: Vector2) -> bool:
	if not _bounds_by_tag.has(tag):
		return false
	remove(tag)
	add(tag, min_pos, max_pos)
	return true


func query(min_pos: Vector2, max_pos: Vector2) -> Array[int]:
	var rect := _make_rect(min_pos, max_pos)
	var seen: Dictionary = {}
	var result: Array[int] = []
	for cell in _cells_for_rect(rect):
		var bucket: Array = _cells.get(cell, [])
		for tag in bucket:
			var typed_tag := int(tag)
			if seen.has(typed_tag):
				continue
			var bounds := _bounds_by_tag.get(typed_tag, Rect2()) as Rect2
			if not bounds.intersects(rect, true):
				continue
			seen[typed_tag] = true
			result.append(typed_tag)
	result.sort()
	return result


func has_tag(tag: int) -> bool:
	return _bounds_by_tag.has(tag)


func size() -> int:
	return _bounds_by_tag.size()


func _make_rect(min_pos: Vector2, max_pos: Vector2) -> Rect2:
	var left := minf(min_pos.x, max_pos.x)
	var top := minf(min_pos.y, max_pos.y)
	var right := maxf(min_pos.x, max_pos.x)
	var bottom := maxf(min_pos.y, max_pos.y)
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _cells_for_rect(rect: Rect2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var min_cell := _world_to_cell(rect.position)
	var max_cell := _world_to_cell(rect.position + rect.size)
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			cells.append(Vector2i(x, y))
	return cells


func _world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floorf(pos.x / cell_size)), int(floorf(pos.y / cell_size)))
