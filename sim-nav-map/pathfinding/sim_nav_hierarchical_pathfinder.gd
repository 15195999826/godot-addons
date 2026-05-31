class_name SimNavHierarchicalPathfinder
extends RefCounted


const _NEIGHBOR_DI: Array[int] = [1, -1, 0, 0]
const _NEIGHBOR_DJ: Array[int] = [0, 0, 1, -1]
const _MAX_NEAREST_RADIUS: int = 256
const _FAST_NEAREST_RADIUS: int = 8

var _chunks_w: int = 0
var _chunks_h: int = 0
var _chunks: Dictionary = {}
var _edges: Dictionary = {}
var _global_regions: Dictionary = {}
var _next_global_region: Dictionary = {}
var _nav_map: SimNavMap = null


func recompute(nav_map: SimNavMap, passability_masks: Array[int]) -> void:
	if nav_map == null:
		push_error("[SimNavHierarchicalPathfinder] recompute: nav_map is null")
		return
	_nav_map = nav_map
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	_chunks_w = (nav_map.width + chunk_size - 1) / chunk_size
	_chunks_h = (nav_map.height + chunk_size - 1) / chunk_size
	_chunks.clear()
	_edges.clear()
	_global_regions.clear()
	_next_global_region.clear()

	for pass_mask in passability_masks:
		var chunks: Array[SimNavHierarchicalChunk] = []
		chunks.resize(_chunks_w * _chunks_h)
		for cj in range(_chunks_h):
			for ci in range(_chunks_w):
				chunks[cj * _chunks_w + ci] = _build_chunk(nav_map, ci, cj, pass_mask)
		_chunks[pass_mask] = chunks
		_build_edges(pass_mask, chunks)
		_compute_global_regions(pass_mask)


func recompute_dirty(nav_map: SimNavMap, passability_masks: Array[int]) -> int:
	if nav_map == null:
		push_error("[SimNavHierarchicalPathfinder] recompute_dirty: nav_map is null")
		return 0
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	var expected_chunks_w: int = (nav_map.width + chunk_size - 1) / chunk_size
	var expected_chunks_h: int = (nav_map.height + chunk_size - 1) / chunk_size
	if not is_recomputed() or _chunks_w != expected_chunks_w or _chunks_h != expected_chunks_h:
		recompute(nav_map, passability_masks)
		return expected_chunks_w * expected_chunks_h

	_nav_map = nav_map
	var dirty_chunks := _collect_dirty_chunks(nav_map)
	if dirty_chunks.is_empty():
		return 0

	for pass_mask in passability_masks:
		var chunks: Array = _chunks.get(pass_mask, [])
		if chunks.size() != _chunks_w * _chunks_h:
			recompute(nav_map, passability_masks)
			return expected_chunks_w * expected_chunks_h
		for chunk_key in dirty_chunks.keys():
			var chunk_coord := chunk_key as Vector2i
			chunks[chunk_coord.y * _chunks_w + chunk_coord.x] = _build_chunk(nav_map, chunk_coord.x, chunk_coord.y, pass_mask)
		_chunks[pass_mask] = chunks
		_build_edges(pass_mask, chunks)
		_compute_global_regions(pass_mask)
	return dirty_chunks.size()


func is_recomputed() -> bool:
	return _nav_map != null and _chunks_w > 0


func get_region(coord: Vector2i, pass_mask: int) -> int:
	if _nav_map == null or not _nav_map.is_valid_navcell(coord):
		return SimNavRegionIdHelper.INVALID
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	@warning_ignore("integer_division")
	var ci: int = coord.x / chunk_size
	@warning_ignore("integer_division")
	var cj: int = coord.y / chunk_size
	var chunk := get_chunk(ci, cj, pass_mask)
	if chunk == null:
		return SimNavRegionIdHelper.INVALID
	var local_i := coord.x % chunk_size
	var local_j := coord.y % chunk_size
	var local_r := chunk.get_region(local_i, local_j)
	if local_r == 0:
		return SimNavRegionIdHelper.INVALID
	return SimNavRegionIdHelper.pack(ci, cj, local_r)


func get_global_region(coord: Vector2i, pass_mask: int) -> int:
	var rid := get_region(coord, pass_mask)
	if SimNavRegionIdHelper.is_invalid(rid):
		return 0
	return int(_global_regions.get(pass_mask, {}).get(rid, 0))


func is_navcell_reachable(start: Vector2i, goal: Vector2i, pass_mask: int) -> bool:
	var start_global := get_global_region(start, pass_mask)
	if start_global == 0:
		return false
	return get_global_region(goal, pass_mask) == start_global


func query_goal_reachability(
	start: Vector2i,
	goal: SimNavPathGoal,
	pass_mask: int,
	passability_class_name: String = ""
) -> SimNavReachabilityResult:
	var result := SimNavReachabilityResult.new()
	result.configure_query(start, goal, pass_mask, passability_class_name)
	if _nav_map == null or not is_recomputed() or not _chunks.has(pass_mask):
		result.set_failure(SimNavReachabilityResult.FAILURE_NOT_RECOMPUTED)
		return result
	if goal == null or pass_mask == 0:
		result.set_failure(SimNavReachabilityResult.FAILURE_INVALID_QUERY)
		return result

	var effective_start := start
	var start_global := get_global_region(effective_start, pass_mask)
	if start_global == 0:
		effective_start = find_nearest_passable_navcell(start, pass_mask)
		if effective_start == Vector2i(-1, -1):
			result.set_failure(SimNavReachabilityResult.FAILURE_NO_START_REGION)
			return result
		start_global = get_global_region(effective_start, pass_mask)
		if start_global == 0:
			result.set_failure(SimNavReachabilityResult.FAILURE_NO_START_REGION)
			return result
	result.effective_start_navcell = effective_start
	result.start_global_region = start_global

	var anchor := _goal_anchor_navcell(goal)
	var reachable_goal := _find_nearest_goal_navcell(anchor, goal, start_global, pass_mask)
	if reachable_goal != Vector2i(-1, -1):
		result.set_reachable(goal, reachable_goal, start_global, get_global_region(reachable_goal, pass_mask))
		return result

	var fallback := _find_nearest_in_global_region(anchor, start_global, pass_mask)
	if fallback == Vector2i(-1, -1):
		result.set_failure(SimNavReachabilityResult.FAILURE_NO_REACHABLE_GOAL)
		result.start_global_region = start_global
		result.effective_start_navcell = effective_start
		return result

	result.set_canonicalized(
		SimNavPathGoal.point(_nav_map.navcell_center_world(fallback)),
		fallback,
		start_global,
		get_global_region(fallback, pass_mask)
	)
	return result


func make_goal_reachable_navcell(start: Vector2i, goal: Vector2i, pass_mask: int) -> Vector2i:
	if _nav_map == null:
		return goal
	var result := query_goal_reachability(start, SimNavPathGoal.point(_nav_map.navcell_center_world(goal)), pass_mask)
	if result.has_canonical_goal():
		return result.canonical_navcell
	return goal


func find_nearest_passable_navcell(start: Vector2i, pass_mask: int) -> Vector2i:
	if _nav_map == null:
		return Vector2i(-1, -1)
	if _nav_map.is_passable_navcell(start, pass_mask):
		return start
	# Fast path: small ring scan covers the common "blocked by a single cell"
	# fallback without walking the region graph.
	for radius in range(1, _FAST_NEAREST_RADIUS + 1):
		var found := _scan_ring_for_passable(start, radius, pass_mask)
		if found != Vector2i(-1, -1):
			return found
	# Fallback: traverse every region of pass_mask via the chunk grid. Bounded
	# by total navcells of the registered passability class instead of by
	# Manhattan radius (the prior fixed _MAX_NEAREST_RADIUS = 256 made cells
	# more than 256 navcells away unreachable even when a valid component
	# existed via the region graph).
	return _find_nearest_in_any_region(start, pass_mask)


func get_chunk(ci: int, cj: int, pass_mask: int) -> SimNavHierarchicalChunk:
	if ci < 0 or cj < 0 or ci >= _chunks_w or cj >= _chunks_h:
		return null
	var arr: Array = _chunks.get(pass_mask, [])
	if arr.is_empty():
		return null
	return arr[cj * _chunks_w + ci] as SimNavHierarchicalChunk


func get_global_regions(pass_mask: int) -> Dictionary:
	return _global_regions.get(pass_mask, {})


func next_global_region(pass_mask: int) -> int:
	return int(_next_global_region.get(pass_mask, 1))


func export_connectivity(pass_mask: int, passability_class_name: String = "") -> Dictionary:
	var regions := PackedInt32Array()
	if _nav_map == null or not is_recomputed() or not _chunks.has(pass_mask):
		return {
			"pass_mask": pass_mask,
			"passability_class_name": passability_class_name,
			"width": 0,
			"height": 0,
			"chunk_size": SimNavHierarchicalChunk.CHUNK_SIZE,
			"chunks_w": _chunks_w,
			"chunks_h": _chunks_h,
			"global_region_count": 0,
			"regions": regions,
		}
	regions.resize(_nav_map.width * _nav_map.height)
	for y in range(_nav_map.height):
		for x in range(_nav_map.width):
			var coord := Vector2i(x, y)
			regions[y * _nav_map.width + x] = get_global_region(coord, pass_mask)
	return {
		"pass_mask": pass_mask,
		"passability_class_name": passability_class_name,
		"width": _nav_map.width,
		"height": _nav_map.height,
		"chunk_size": SimNavHierarchicalChunk.CHUNK_SIZE,
		"chunks_w": _chunks_w,
		"chunks_h": _chunks_h,
		"global_region_count": maxi(0, next_global_region(pass_mask) - 1),
		"regions": regions,
	}


func get_diagnostics(passability_masks: Array[int] = []) -> Dictionary:
	var connectivity: Array[Dictionary] = []
	for pass_mask in passability_masks:
		connectivity.append(export_connectivity(pass_mask))
	return {
		"is_recomputed": is_recomputed(),
		"chunks_w": _chunks_w,
		"chunks_h": _chunks_h,
		"passability_mask_count": _chunks.size(),
		"connectivity": connectivity,
	}


func _build_chunk(nav_map: SimNavMap, ci: int, cj: int, pass_mask: int) -> SimNavHierarchicalChunk:
	var chunk := SimNavHierarchicalChunk.new(ci, cj)
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	var next_local_region := 1
	for local_j in range(chunk_size):
		var row_base := local_j * chunk_size
		for local_i in range(chunk_size):
			var idx := row_base + local_i
			if chunk.regions[idx] != 0:
				continue
			var coord := Vector2i(ci * chunk_size + local_i, cj * chunk_size + local_j)
			if not nav_map.is_passable_navcell(coord, pass_mask):
				continue
			_flood_fill_chunk(nav_map, chunk, coord, next_local_region, pass_mask)
			chunk.regions_id.append(next_local_region)
			next_local_region += 1
	return chunk


func _flood_fill_chunk(
	nav_map: SimNavMap,
	chunk: SimNavHierarchicalChunk,
	start_coord: Vector2i,
	local_region: int,
	pass_mask: int
) -> void:
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	var queue := PackedInt32Array()
	var start_local_i := start_coord.x - chunk.ci * chunk_size
	var start_local_j := start_coord.y - chunk.cj * chunk_size
	queue.append(start_local_j * chunk_size + start_local_i)
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		if chunk.regions[idx] != 0:
			continue
		chunk.regions[idx] = local_region
		var local_i := idx % chunk_size
		@warning_ignore("integer_division")
		var local_j: int = idx / chunk_size
		for direction_idx in range(4):
			var next_local_i := local_i + _NEIGHBOR_DI[direction_idx]
			var next_local_j := local_j + _NEIGHBOR_DJ[direction_idx]
			if next_local_i < 0 or next_local_j < 0 or next_local_i >= chunk_size or next_local_j >= chunk_size:
				continue
			var next_coord := Vector2i(chunk.ci * chunk_size + next_local_i, chunk.cj * chunk_size + next_local_j)
			if not nav_map.is_passable_navcell(next_coord, pass_mask):
				continue
			var next_idx := next_local_j * chunk_size + next_local_i
			if chunk.regions[next_idx] != 0:
				continue
			queue.append(next_idx)


func _build_edges(pass_mask: int, chunks: Array[SimNavHierarchicalChunk]) -> void:
	var edges: Dictionary = {}
	for cj in range(_chunks_h):
		for ci in range(_chunks_w):
			var chunk: SimNavHierarchicalChunk = chunks[cj * _chunks_w + ci]
			if ci + 1 < _chunks_w:
				_add_vertical_edges(chunk, chunks[cj * _chunks_w + ci + 1], edges)
			if cj + 1 < _chunks_h:
				_add_horizontal_edges(chunk, chunks[(cj + 1) * _chunks_w + ci], edges)
	_edges[pass_mask] = edges


func _add_vertical_edges(left: SimNavHierarchicalChunk, right: SimNavHierarchicalChunk, edges: Dictionary) -> void:
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	for local_j in range(chunk_size):
		_add_pair_if_passable(
			left,
			right,
			left.get_region(chunk_size - 1, local_j),
			right.get_region(0, local_j),
			edges
		)


func _add_horizontal_edges(top: SimNavHierarchicalChunk, bottom: SimNavHierarchicalChunk, edges: Dictionary) -> void:
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	for local_i in range(chunk_size):
		_add_pair_if_passable(
			top,
			bottom,
			top.get_region(local_i, chunk_size - 1),
			bottom.get_region(local_i, 0),
			edges
		)


func _add_pair_if_passable(
	chunk_a: SimNavHierarchicalChunk,
	chunk_b: SimNavHierarchicalChunk,
	region_a: int,
	region_b: int,
	edges: Dictionary
) -> void:
	if region_a == 0 or region_b == 0:
		return
	_add_undirected_edge(
		edges,
		SimNavRegionIdHelper.pack(chunk_a.ci, chunk_a.cj, region_a),
		SimNavRegionIdHelper.pack(chunk_b.ci, chunk_b.cj, region_b)
	)


func _add_undirected_edge(edges: Dictionary, a: int, b: int) -> void:
	if a == b:
		return
	_insert_sorted_unique(edges, a, b)
	_insert_sorted_unique(edges, b, a)


func _insert_sorted_unique(edges: Dictionary, key: int, value: int) -> void:
	var arr: Array = edges.get(key, [])
	var pos := arr.bsearch(value)
	if pos < arr.size() and arr[pos] == value:
		return
	arr.insert(pos, value)
	edges[key] = arr


func _compute_global_regions(pass_mask: int) -> void:
	var edges: Dictionary = _edges.get(pass_mask, {})
	var chunks: Array = _chunks.get(pass_mask, [])
	var all_region_ids: Array[int] = []
	for chunk in chunks:
		var nav_chunk := chunk as SimNavHierarchicalChunk
		for local_region in nav_chunk.regions_id:
			all_region_ids.append(SimNavRegionIdHelper.pack(nav_chunk.ci, nav_chunk.cj, local_region))
	all_region_ids.sort()

	var global: Dictionary = {}
	var next_global := 1
	var queue := PackedInt64Array()
	for rid in all_region_ids:
		if global.has(rid):
			continue
		queue.clear()
		queue.append(rid)
		var head := 0
		while head < queue.size():
			var current := int(queue[head])
			head += 1
			if global.has(current):
				continue
			global[current] = next_global
			for neighbor in edges.get(current, []):
				if not global.has(neighbor):
					queue.append(neighbor)
		next_global += 1
	_global_regions[pass_mask] = global
	_next_global_region[pass_mask] = next_global


func _collect_dirty_chunks(nav_map: SimNavMap) -> Dictionary:
	var dirty_chunks: Dictionary = {}
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	for coord in nav_map.collect_dirty_navcells():
		@warning_ignore("integer_division")
		var ci: int = coord.x / chunk_size
		@warning_ignore("integer_division")
		var cj: int = coord.y / chunk_size
		if ci >= 0 and cj >= 0 and ci < _chunks_w and cj < _chunks_h:
			dirty_chunks[Vector2i(ci, cj)] = true
	return dirty_chunks


func _find_nearest_in_global_region(start: Vector2i, target_global: int, pass_mask: int) -> Vector2i:
	if target_global == 0:
		return Vector2i(-1, -1)
	if get_global_region(start, pass_mask) == target_global:
		return start
	# Fast path: try a small ring scan for the common "right next to the
	# target region" canonicalization. Anything farther falls through to the
	# region-graph walk so we never bail out at a fixed Manhattan radius.
	for radius in range(1, _FAST_NEAREST_RADIUS + 1):
		var found := _scan_ring_for_global(start, radius, pass_mask, target_global)
		if found != Vector2i(-1, -1):
			return found
	return _find_nearest_in_global_region_via_graph(start, target_global, pass_mask)


func _find_nearest_goal_navcell(
	start: Vector2i,
	goal: SimNavPathGoal,
	target_global: int,
	pass_mask: int
) -> Vector2i:
	if target_global == 0 or goal == null:
		return Vector2i(-1, -1)
	if goal.type == SimNavPathGoal.Type.POINT:
		if get_global_region(start, pass_mask) == target_global:
			return start
		return Vector2i(-1, -1)
	if goal.navcell_contains_goal(_nav_map, start) and get_global_region(start, pass_mask) == target_global:
		return start
	var max_radius := _goal_navcell_search_radius(goal)
	for radius in range(1, max_radius + 1):
		var found := _scan_ring_for_goal_global(start, radius, pass_mask, target_global, goal)
		if found != Vector2i(-1, -1):
			return found
	return Vector2i(-1, -1)


func _scan_ring_for_passable(center: Vector2i, radius: int, pass_mask: int) -> Vector2i:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) != radius:
				continue
			var coord := Vector2i(center.x + dx, center.y + dy)
			if _nav_map.is_passable_navcell(coord, pass_mask):
				return coord
	return Vector2i(-1, -1)


func _scan_ring_for_global(center: Vector2i, radius: int, pass_mask: int, target_global: int) -> Vector2i:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) != radius:
				continue
			var coord := Vector2i(center.x + dx, center.y + dy)
			if get_global_region(coord, pass_mask) == target_global:
				return coord
	return Vector2i(-1, -1)


func _find_nearest_in_global_region_via_graph(anchor: Vector2i, target_global: int, pass_mask: int) -> Vector2i:
	var chunks: Array = _chunks.get(pass_mask, [])
	if chunks.is_empty() or target_global == 0:
		return Vector2i(-1, -1)
	var globals_map: Dictionary = _global_regions.get(pass_mask, {})
	if globals_map.is_empty():
		return Vector2i(-1, -1)
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	var best_cell := Vector2i(-1, -1)
	var best_dist_sq := INF
	for cj in range(_chunks_h):
		for ci in range(_chunks_w):
			var chunk := chunks[cj * _chunks_w + ci] as SimNavHierarchicalChunk
			if chunk == null:
				continue
			for lj in range(chunk_size):
				var base_y := cj * chunk_size + lj
				if base_y >= _nav_map.height:
					break
				for li in range(chunk_size):
					var base_x := ci * chunk_size + li
					if base_x >= _nav_map.width:
						break
					var local_r := chunk.get_region(li, lj)
					if local_r == 0:
						continue
					var rid := SimNavRegionIdHelper.pack(ci, cj, local_r)
					if int(globals_map.get(rid, 0)) != target_global:
						continue
					var dx := float(base_x - anchor.x)
					var dy := float(base_y - anchor.y)
					var d := dx * dx + dy * dy
					if d < best_dist_sq:
						best_dist_sq = d
						best_cell = Vector2i(base_x, base_y)
	return best_cell


func _find_nearest_in_any_region(anchor: Vector2i, pass_mask: int) -> Vector2i:
	var chunks: Array = _chunks.get(pass_mask, [])
	if chunks.is_empty():
		return Vector2i(-1, -1)
	var chunk_size := SimNavHierarchicalChunk.CHUNK_SIZE
	var best_cell := Vector2i(-1, -1)
	var best_dist_sq := INF
	for cj in range(_chunks_h):
		for ci in range(_chunks_w):
			var chunk := chunks[cj * _chunks_w + ci] as SimNavHierarchicalChunk
			if chunk == null:
				continue
			for lj in range(chunk_size):
				var base_y := cj * chunk_size + lj
				if base_y >= _nav_map.height:
					break
				for li in range(chunk_size):
					var base_x := ci * chunk_size + li
					if base_x >= _nav_map.width:
						break
					if chunk.get_region(li, lj) == 0:
						continue
					var dx := float(base_x - anchor.x)
					var dy := float(base_y - anchor.y)
					var d := dx * dx + dy * dy
					if d < best_dist_sq:
						best_dist_sq = d
						best_cell = Vector2i(base_x, base_y)
	return best_cell


func _scan_ring_for_goal_global(
	center: Vector2i,
	radius: int,
	pass_mask: int,
	target_global: int,
	goal: SimNavPathGoal
) -> Vector2i:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) != radius:
				continue
			var coord := Vector2i(center.x + dx, center.y + dy)
			if not goal.navcell_contains_goal(_nav_map, coord):
				continue
			if get_global_region(coord, pass_mask) == target_global:
				return coord
	return Vector2i(-1, -1)


func _goal_navcell_search_radius(goal: SimNavPathGoal) -> int:
	if _nav_map == null or goal == null:
		return 0
	var extent := 0.0
	match goal.type:
		SimNavPathGoal.Type.CIRCLE, SimNavPathGoal.Type.INVERTED_CIRCLE:
			extent = goal.hw
		SimNavPathGoal.Type.SQUARE, SimNavPathGoal.Type.INVERTED_SQUARE:
			extent = goal.hw + goal.hh
		_:
			return 0
	var cell_size := maxf(_nav_map.navcell_size, 0.001)
	return mini(_MAX_NEAREST_RADIUS, int(ceil(extent / cell_size)) + 2)


func _goal_anchor_navcell(goal: SimNavPathGoal) -> Vector2i:
	if goal == null or _nav_map == null:
		return Vector2i(-1, -1)
	return _nav_map.world_to_navcell(goal.center)
