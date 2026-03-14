## GridPathfinding - 通用网格寻路和视野算法
##
## 提供:
## - A* 寻路
## - BFS 可达性分析
## - 视野 (FOV) 计算
## - 简单射线可见性
## - 洪水填充
##
## 支持所有网格类型: HEX, RECT_SIX_DIR, SQUARE, RECT
## 所有方法使用 GridMapModel 来获取邻居和距离信息
##
## 参考: HexPathfinding (旧实现)
class_name GridPathfinding
extends RefCounted




# ========== A* 寻路结果 ==========

## A* 寻路结果
class PathResult:
	var path: Array[HexCoord] = []  ## 路径 (包含起点和终点)
	var cost: float = 0.0           ## 总代价
	var found: bool = false         ## 是否找到路径
	
	func _init(p_path: Array[HexCoord] = [], p_cost: float = 0.0, p_found: bool = false) -> void:
		path = p_path
		cost = p_cost
		found = p_found


# ========== A* 寻路 ==========

## A* 寻路
##
## @param model: 网格地图模型
## @param start: 起点
## @param goal: 终点
## @param is_passable: 判断格子是否可通行的回调 func(coord: HexCoord) -> bool
## @param cost_func: 移动代价回调 func(from: HexCoord, to: HexCoord) -> float (可选，默认为1)
## @param max_cost: 最大搜索代价 (可选，防止无限搜索)
## @return: PathResult
static func astar(
	model: GridMapModel,
	start: HexCoord,
	goal: HexCoord,
	is_passable: Callable,
	cost_func: Callable = Callable(),
	max_cost: float = INF
) -> PathResult:
	var start_key: String = start.to_key()
	var goal_key: String = goal.to_key()
	
	# 优先队列: [priority, coord]
	var frontier: Array = []
	_heap_push(frontier, [0.0, start])
	
	var came_from: Dictionary = { start_key: null }
	var cost_so_far: Dictionary = { start_key: 0.0 }
	
	while not frontier.is_empty():
		var current: HexCoord = _heap_pop(frontier)[1]
		var current_key: String = current.to_key()
		
		if current.equals(goal):
			# 重建路径
			var result_path := _reconstruct_path(came_from, start, goal)
			return PathResult.new(result_path, cost_so_far[goal_key], true)
		
		# 使用 model 获取邻居
		for neighbor in model.get_neighbors(current):
			if not is_passable.call(neighbor):
				continue
			
			var move_cost := 1.0
			if cost_func.is_valid():
				move_cost = cost_func.call(current, neighbor)
			
			var new_cost: float = cost_so_far[current_key] + move_cost
			
			if new_cost > max_cost:
				continue
			
			var neighbor_key: String = neighbor.to_key()
			if neighbor_key not in cost_so_far or new_cost < cost_so_far[neighbor_key]:
				cost_so_far[neighbor_key] = new_cost
				# 使用 model 计算启发式距离
				var priority := new_cost + float(model.get_distance(neighbor, goal))
				_heap_push(frontier, [priority, neighbor])
				came_from[neighbor_key] = current
	
	# 未找到路径
	return PathResult.new([], 0.0, false)


## A* 寻路 (简化版，使用 model 的默认可通行判断)
##
## @param model: 网格地图模型
## @param start: 起点
## @param goal: 终点
## @param max_cost: 最大搜索代价 (可选)
## @return: PathResult
static func astar_simple(
	model: GridMapModel,
	start: HexCoord,
	goal: HexCoord,
	max_cost: float = INF
) -> PathResult:
	var is_passable := func(coord: HexCoord) -> bool:
		return model.is_passable(coord)
	
	var cost_func := func(from: HexCoord, to: HexCoord) -> float:
		return model.get_tile_cost(to)
	
	return astar(model, start, goal, is_passable, cost_func, max_cost)


## 重建路径
static func _reconstruct_path(
	came_from: Dictionary,
	start: HexCoord,
	goal: HexCoord
) -> Array[HexCoord]:
	var path: Array[HexCoord] = []
	var current: HexCoord = goal
	
	while not current.equals(start):
		path.append(current)
		current = came_from[current.to_key()]
	
	path.append(start)
	path.reverse()
	return path


# ========== 简单堆实现 ==========

static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	_heap_sift_up(heap, heap.size() - 1)


static func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Variant = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		_heap_sift_down(heap, 0)
	return result


static func _heap_sift_up(heap: Array, idx: int) -> void:
	while idx > 0:
		var parent: int = (idx - 1) / 2
		if heap[idx][0] < heap[parent][0]:
			var tmp: Array = heap[idx]
			heap[idx] = heap[parent]
			heap[parent] = tmp
			idx = parent
		else:
			break


static func _heap_sift_down(heap: Array, idx: int) -> void:
	var arr_size: int = heap.size()
	while true:
		var smallest: int = idx
		var left: int = 2 * idx + 1
		var right: int = 2 * idx + 2
		
		if left < arr_size and heap[left][0] < heap[smallest][0]:
			smallest = left
		if right < arr_size and heap[right][0] < heap[smallest][0]:
			smallest = right
		
		if smallest != idx:
			var tmp: Array = heap[idx]
			heap[idx] = heap[smallest]
			heap[smallest] = tmp
			idx = smallest
		else:
			break


# ========== BFS 可达性 ==========

## BFS 可达性分析
##
## @param model: 网格地图模型
## @param start: 起点 (HexCoord)
## @param max_movement: 最大移动距离 (步数)
## @param is_passable: 判断格子是否可通行的回调
## @return: 所有可达格子的集合 (HexCoord 数组)
static func reachable(
	model: GridMapModel,
	start: HexCoord,
	max_movement: int,
	is_passable: Callable
) -> Array[HexCoord]:
	var start_key: String = start.to_key()
	var visited: Dictionary = { start_key: start }
	var fringes: Array[Array] = [[start]]
	
	for k in range(1, max_movement + 1):
		fringes.append([])
		for coord in fringes[k - 1]:
			for neighbor in model.get_neighbors(coord):
				var neighbor_key: String = neighbor.to_key()
				if neighbor_key not in visited and is_passable.call(neighbor):
					visited[neighbor_key] = neighbor
					fringes[k].append(neighbor)
	
	var result: Array[HexCoord] = []
	for coord in visited.values():
		result.append(coord)
	return result


## BFS 可达性分析 (简化版，使用 model 的默认可通行判断)
static func reachable_simple(
	model: GridMapModel,
	start: HexCoord,
	max_movement: int
) -> Array[HexCoord]:
	var is_passable := func(coord: HexCoord) -> bool:
		return model.is_passable(coord)
	return reachable(model, start, max_movement, is_passable)


## BFS 可达性分析 (带代价)
##
## @param model: 网格地图模型
## @param start: 起点 (HexCoord)
## @param max_cost: 最大移动代价
## @param is_passable: 判断格子是否可通行的回调
## @param cost_func: 移动代价回调
## @return: Dictionary { key: { "coord": HexCoord, "cost": float } }
static func reachable_with_cost(
	model: GridMapModel,
	start: HexCoord,
	max_cost: float,
	is_passable: Callable,
	cost_func: Callable = Callable()
) -> Dictionary:
	var start_key: String = start.to_key()
	var visited: Dictionary = { start_key: { "coord": start, "cost": 0.0 } }
	var frontier: Array[HexCoord] = [start]
	
	while not frontier.is_empty():
		var current: HexCoord = frontier.pop_front()
		var current_key: String = current.to_key()
		var current_cost: float = visited[current_key]["cost"]
		
		for neighbor in model.get_neighbors(current):
			if not is_passable.call(neighbor):
				continue
			
			var move_cost := 1.0
			if cost_func.is_valid():
				move_cost = cost_func.call(current, neighbor)
			
			var new_cost := current_cost + move_cost
			
			if new_cost > max_cost:
				continue
			
			var neighbor_key: String = neighbor.to_key()
			if neighbor_key not in visited or new_cost < visited[neighbor_key]["cost"]:
				visited[neighbor_key] = { "coord": neighbor, "cost": new_cost }
				frontier.append(neighbor)
	
	return visited


## BFS 可达性分析 (带代价，简化版)
static func reachable_with_cost_simple(
	model: GridMapModel,
	start: HexCoord,
	max_cost: float
) -> Dictionary:
	var is_passable := func(coord: HexCoord) -> bool:
		return model.is_passable(coord)
	var cost_func := func(from: HexCoord, to: HexCoord) -> float:
		return model.get_tile_cost(to)
	return reachable_with_cost(model, start, max_cost, is_passable, cost_func)


# ========== 线段绘制 ==========

## 绘制从 from 到 to 的直线 (通用版本)
## 使用 Bresenham 算法，适用于所有网格类型
## 对于六边形网格，使用 GridMath.hex_line
##
## @param model: 网格地图模型
## @param from: 起点
## @param to: 终点
## @return: 线段上的所有格子 (包含两端点)
static func get_line(
	model: GridMapModel,
	from: HexCoord,
	to: HexCoord
) -> Array[HexCoord]:
	var grid_type := model.get_grid_type()
	var from_vec: Vector2i = from.to_axial()
	var to_vec: Vector2i = to.to_axial()
	
	# 六边形使用专用算法
	if grid_type == GridMapConfig.GridType.HEX:
		var vec_line: Array[Vector2i] = GridMath.hex_line(from_vec, to_vec)
		return _vec_array_to_hex_array(vec_line)
	
	# 其他网格类型使用 Bresenham 算法
	var vec_line: Array[Vector2i] = _bresenham_line(from_vec, to_vec)
	return _vec_array_to_hex_array(vec_line)


## 将 Vector2i 数组转换为 HexCoord 数组
static func _vec_array_to_hex_array(vec_array: Array[Vector2i]) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	for v in vec_array:
		result.append(HexCoord.new(v.x, v.y))
	return result


## Bresenham 直线算法
static func _bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx - dy
	
	var x := from.x
	var y := from.y
	
	while true:
		result.append(Vector2i(x, y))
		
		if x == to.x and y == to.y:
			break
		
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	
	return result


# ========== 视野 (FOV) ==========

## 简单射线可见性检测
##
## @param model: 网格地图模型
## @param origin: 观察点
## @param target: 目标点
## @param blocks_vision: 判断格子是否阻挡视线的回调
## @return: 目标是否可见
static func is_visible(
	model: GridMapModel,
	origin: HexCoord,
	target: HexCoord,
	blocks_vision: Callable
) -> bool:
	var line := get_line(model, origin, target)
	
	# 检查中间的格子 (排除起点和终点)
	for i in range(1, line.size() - 1):
		if blocks_vision.call(line[i]):
			return false
	
	return true


## 简单射线可见性检测 (简化版，使用 model 的阻挡判断)
static func is_visible_simple(
	model: GridMapModel,
	origin: HexCoord,
	target: HexCoord
) -> bool:
	var blocks_vision := func(coord: HexCoord) -> bool:
		return model.is_tile_blocking(coord)
	return is_visible(model, origin, target, blocks_vision)


## 计算视野范围内所有可见格子
##
## @param model: 网格地图模型
## @param origin: 观察点
## @param vision_range: 视野范围
## @param blocks_vision: 判断格子是否阻挡视线的回调
## @return: 所有可见格子
static func field_of_view(
	model: GridMapModel,
	origin: HexCoord,
	vision_range: int,
	blocks_vision: Callable
) -> Array[HexCoord]:
	var visible: Array[HexCoord] = [origin]
	
	for coord in model.get_range(origin, vision_range):
		if coord.equals(origin):
			continue
		if is_visible(model, origin, coord, blocks_vision):
			visible.append(coord)
	
	return visible


## 计算视野范围内所有可见格子 (简化版)
static func field_of_view_simple(
	model: GridMapModel,
	origin: HexCoord,
	vision_range: int
) -> Array[HexCoord]:
	var blocks_vision := func(coord: HexCoord) -> bool:
		return model.is_tile_blocking(coord)
	return field_of_view(model, origin, vision_range, blocks_vision)


## 计算视野范围内所有可见格子 (优化版，使用环形扫描)
##
## 从内向外扫描，如果一个格子不可见，则不再检查它后面的格子
static func field_of_view_optimized(
	model: GridMapModel,
	origin: HexCoord,
	vision_range: int,
	blocks_vision: Callable
) -> Array[HexCoord]:
	var origin_key: String = origin.to_key()
	var visible: Dictionary = { origin_key: origin }
	var blocked: Dictionary = {}
	
	# 按环从内向外扫描
	for radius in range(1, vision_range + 1):
		for coord in _get_ring(model, origin, radius):
			# 检查是否被之前的格子阻挡
			var is_blocked := false
			var line := get_line(model, origin, coord)
			
			for i in range(1, line.size() - 1):
				var line_key: String = line[i].to_key()
				if line_key in blocked:
					is_blocked = true
					break
			
			if not is_blocked:
				var coord_key: String = coord.to_key()
				visible[coord_key] = coord
				if blocks_vision.call(coord):
					blocked[coord_key] = true
	
	var result: Array[HexCoord] = []
	for coord in visible.values():
		result.append(coord)
	return result


## 获取指定半径的环形格子
static func _get_ring(model: GridMapModel, center: HexCoord, radius: int) -> Array[HexCoord]:
	var grid_type := model.get_grid_type()
	var center_vec: Vector2i = center.to_axial()
	
	# 六边形使用专用算法
	if grid_type == GridMapConfig.GridType.HEX:
		var vec_ring: Array[Vector2i] = GridMath.hex_ring(center_vec, radius)
		return _vec_array_to_hex_array(vec_ring)
	
	# 其他网格类型使用曼哈顿距离环
	var result: Array[HexCoord] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var dist := absi(x) + absi(y)
			if dist == radius:
				result.append(HexCoord.new(center_vec.x + x, center_vec.y + y))
	return result


# ========== 射线投射 ==========

## 射线投射，返回第一个阻挡的格子
##
## @param model: 网格地图模型
## @param origin: 起点
## @param direction: 方向索引 (取决于网格类型)
## @param max_distance: 最大距离
## @param blocks_ray: 判断格子是否阻挡射线的回调
## @return: 第一个阻挡的格子，如果没有则返回 HexCoord.invalid()
static func raycast(
	model: GridMapModel,
	origin: HexCoord,
	direction: int,
	max_distance: int,
	blocks_ray: Callable
) -> HexCoord:
	var current: HexCoord = origin
	
	for i in range(max_distance):
		var neighbors := model.get_neighbors(current)
		if direction < 0 or direction >= neighbors.size():
			break
		current = neighbors[direction]
		if blocks_ray.call(current):
			return current
	
	return HexCoord.invalid()


## 射线投射到目标，返回路径上第一个阻挡的格子
##
## @param model: 网格地图模型
## @param origin: 起点
## @param target: 目标点
## @param blocks_ray: 判断格子是否阻挡射线的回调
## @return: 第一个阻挡的格子，如果没有则返回 null
static func raycast_to(
	model: GridMapModel,
	origin: HexCoord,
	target: HexCoord,
	blocks_ray: Callable
) -> Variant:
	var line := get_line(model, origin, target)
	
	for i in range(1, line.size()):
		if blocks_ray.call(line[i]):
			return line[i]
	
	return null


## 射线投射到目标 (简化版)
static func raycast_to_simple(
	model: GridMapModel,
	origin: HexCoord,
	target: HexCoord
) -> Variant:
	var blocks_ray := func(coord: HexCoord) -> bool:
		return model.is_tile_blocking(coord)
	return raycast_to(model, origin, target, blocks_ray)


# ========== 洪水填充 ==========

## 洪水填充，找到所有连通的格子
##
## @param model: 网格地图模型
## @param start: 起点 (HexCoord)
## @param is_same_region: 判断格子是否属于同一区域的回调
## @param max_size: 最大区域大小 (防止无限扩展)
## @return: 所有连通的格子
static func flood_fill(
	model: GridMapModel,
	start: HexCoord,
	is_same_region: Callable,
	max_size: int = 10000
) -> Array[HexCoord]:
	if not is_same_region.call(start):
		return []
	
	var start_key: String = start.to_key()
	var visited: Dictionary = { start_key: true }
	var frontier: Array[HexCoord] = [start]
	var result: Array[HexCoord] = [start]
	
	while not frontier.is_empty() and result.size() < max_size:
		var current: HexCoord = frontier.pop_front()
		
		for neighbor in model.get_neighbors(current):
			var neighbor_key: String = neighbor.to_key()
			if neighbor_key not in visited and is_same_region.call(neighbor):
				visited[neighbor_key] = true
				frontier.append(neighbor)
				result.append(neighbor)
	
	return result


## 洪水填充 (简化版，使用 model 的瓦片存在判断)
static func flood_fill_simple(
	model: GridMapModel,
	start: HexCoord,
	max_size: int = 10000
) -> Array[HexCoord]:
	var is_same_region := func(coord: HexCoord) -> bool:
		return model.has_tile(coord) and not model.is_tile_blocking(coord)
	return flood_fill(model, start, is_same_region, max_size)
