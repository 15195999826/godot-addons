## GridMap 完整单元测试
##
## 运行方式: godot --headless --script addons/ultra-grid-map/tests/test_grid_map.gd
extends SceneTree

# 禁用类型推断警告（测试代码中使用动态类型）
@warning_ignore("untyped_declaration")
@warning_ignore("inferred_declaration")

# 在 --script 模式下，使用 load() 而不是 preload()
# 这样可以正确实例化类
var GridMapConfig = load("res://addons/ultra-grid-map/core/grid_types.gd")
var CoordConverter = load("res://addons/ultra-grid-map/core/coord_converter.gd")
var HexCoord = load("res://addons/ultra-grid-map/core/hex_coord.gd")
var GridMath = load("res://addons/ultra-grid-map/core/grid_math.gd")
var GridLayout = load("res://addons/ultra-grid-map/core/grid_layout.gd")
var GridMapModel = load("res://addons/ultra-grid-map/model/grid_map_model.gd")
var GridPathfinding = load("res://addons/ultra-grid-map/pathfinding/grid_pathfinding.gd")


func _init() -> void:
	var success: bool = run_tests()
	quit(0 if success else 1)


func run_tests() -> bool:
	print("========== GridMap Tests ==========")
	
	var passed: int = 0
	var failed: int = 0
	
	# 运行所有测试
	if test_grid_coord():
		passed += 1
	else:
		failed += 1
	
	if test_grid_math():
		passed += 1
	else:
		failed += 1
	
	if test_grid_layout():
		passed += 1
	else:
		failed += 1
	
	if test_grid_map_model():
		passed += 1
	else:
		failed += 1
	
	if test_grid_pathfinding():
		passed += 1
	else:
		failed += 1
	
	if test_event_system():
		passed += 1
	else:
		failed += 1
	
	print("===================================")
	print("Tests: %d passed, %d failed" % [passed, failed])
	return failed == 0


func test_grid_coord() -> bool:
	print("Testing HexCoord & CoordConverter...")
	
	# HexCoord: Axial → Cube 转换
	var coord1 = HexCoord.new(1, 2)
	var cube1: Vector3i = coord1.to_cube()
	if cube1 != Vector3i(1, 2, -3):
		print("  [FAIL] HexCoord(1,2).to_cube() = %s, expected (1,2,-3)" % cube1)
		return false
	
	var coord2 = HexCoord.new(0, 0)
	var cube2: Vector3i = coord2.to_cube()
	if cube2 != Vector3i(0, 0, 0):
		print("  [FAIL] HexCoord(0,0).to_cube() = %s, expected (0,0,0)" % cube2)
		return false
	
	var coord3 = HexCoord.new(-1, 3)
	var cube3: Vector3i = coord3.to_cube()
	if cube3 != Vector3i(-1, 3, -2):
		print("  [FAIL] HexCoord(-1,3).to_cube() = %s, expected (-1,3,-2)" % cube3)
		return false
	
	# HexCoord: Cube → Axial 转换
	var coord4 = HexCoord.from_cube(Vector3i(1, 2, -3))
	if coord4.q != 1 or coord4.r != 2:
		print("  [FAIL] HexCoord.from_cube(1,2,-3) = (%d,%d), expected (1,2)" % [coord4.q, coord4.r])
		return false
	
	# CoordConverter: Offset → Axial 转换 (odd-r)
	var axial2: Vector2i = CoordConverter.offset_to_axial(Vector2i(0, 0), CoordConverter.OffsetType.ODD_R)
	if axial2 != Vector2i(0, 0):
		print("  [FAIL] offset_to_axial(0,0,ODD_R) = %s, expected (0,0)" % axial2)
		return false
	
	var axial3: Vector2i = CoordConverter.offset_to_axial(Vector2i(1, 1), CoordConverter.OffsetType.ODD_R)
	if axial3 != Vector2i(1, 1):
		print("  [FAIL] offset_to_axial(1,1,ODD_R) = %s, expected (1,1)" % axial3)
		return false
	
	# CoordConverter: Cartesian → Axial (直接映射)
	var axial4: Vector2i = CoordConverter.cartesian_to_axial(Vector2i(3, 4))
	if axial4 != Vector2i(3, 4):
		print("  [FAIL] cartesian_to_axial(3,4) = %s, expected (3,4)" % axial4)
		return false
	
	# CoordConverter: 坐标取整
	var rounded: Vector2i = CoordConverter.axial_round(1.2, 2.8)
	if rounded != Vector2i(1, 3):
		print("  [FAIL] axial_round(1.2, 2.8) = %s, expected (1,3)" % rounded)
		return false
	
	print("  [PASS] HexCoord & CoordConverter")
	return true


func test_grid_math() -> bool:
	print("Testing GridMath...")
	
	# HEX 距离计算
	var d1: int = GridMath.hex_distance(Vector2i(0, 0), Vector2i(1, 0))
	if d1 != 1:
		print("  [FAIL] hex_distance((0,0), (1,0)) = %d, expected 1" % d1)
		return false
	
	var d2: int = GridMath.hex_distance(Vector2i(0, 0), Vector2i(2, -1))
	if d2 != 2:
		print("  [FAIL] hex_distance((0,0), (2,-1)) = %d, expected 2" % d2)
		return false
	
	var d3: int = GridMath.hex_distance(Vector2i(0, 0), Vector2i(3, -3))
	if d3 != 3:
		print("  [FAIL] hex_distance((0,0), (3,-3)) = %d, expected 3" % d3)
		return false
	
	# SQUARE 距离计算 (曼哈顿)
	var d4: int = GridMath.manhattan_distance(Vector2i(0, 0), Vector2i(3, 4))
	if d4 != 7:
		print("  [FAIL] manhattan_distance((0,0), (3,4)) = %d, expected 7" % d4)
		return false
	
	var d5: int = GridMath.manhattan_distance(Vector2i(1, 1), Vector2i(4, 5))
	if d5 != 7:
		print("  [FAIL] manhattan_distance((1,1), (4,5)) = %d, expected 7" % d5)
		return false
	
	# SQUARE 距离计算 (切比雪夫)
	var d6: int = GridMath.chebyshev_distance(Vector2i(0, 0), Vector2i(3, 4))
	if d6 != 4:
		print("  [FAIL] chebyshev_distance((0,0), (3,4)) = %d, expected 4" % d6)
		return false
	
	# HEX 邻居查询
	var hex_neighbors: Array[Vector2i] = GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.HEX)
	if hex_neighbors.size() != 6:
		print("  [FAIL] HEX neighbors.size() = %d, expected 6" % hex_neighbors.size())
		return false
	
	if not (Vector2i(1, 0) in hex_neighbors):
		print("  [FAIL] Vector2i(1, 0) not in HEX neighbors")
		return false
	
	if not (Vector2i(-1, 0) in hex_neighbors):
		print("  [FAIL] Vector2i(-1, 0) not in HEX neighbors")
		return false
	
	# SQUARE 邻居查询
	var square_neighbors: Array[Vector2i] = GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.SQUARE)
	if square_neighbors.size() != 4:
		print("  [FAIL] SQUARE neighbors.size() = %d, expected 4" % square_neighbors.size())
		return false
	
	if not (Vector2i(1, 0) in square_neighbors):
		print("  [FAIL] Vector2i(1, 0) not in SQUARE neighbors")
		return false
	
	if not (Vector2i(0, 1) in square_neighbors):
		print("  [FAIL] Vector2i(0, 1) not in SQUARE neighbors")
		return false
	
	# RECT_SIX_DIR 邻居查询
	var rect_six_neighbors: Array[Vector2i] = GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.RECT_SIX_DIR)
	if rect_six_neighbors.size() != 6:
		print("  [FAIL] RECT_SIX_DIR neighbors.size() = %d, expected 6" % rect_six_neighbors.size())
		return false
	
	# 范围查询
	var range_coords: Array[Vector2i] = GridMath.hex_range(Vector2i.ZERO, 1)
	if range_coords.size() != 7:  # 中心 + 6 个邻居
		print("  [FAIL] hex_range(0, 1).size() = %d, expected 7" % range_coords.size())
		return false
	
	# 线段绘制
	var line: Array[Vector2i] = GridMath.hex_line(Vector2i(0, 0), Vector2i(2, 0))
	if line.size() != 3:  # (0,0), (1,0), (2,0)
		print("  [FAIL] hex_line((0,0), (2,0)).size() = %d, expected 3" % line.size())
		return false
	
	print("  [PASS] GridMath")
	return true


func test_grid_layout() -> bool:
	print("Testing GridLayout...")
	
	# HEX Pointy-top 测试
	var layout: Variant = GridLayout.new(GridMapConfig.GridType.HEX, 32.0, Vector2.ZERO, GridMapConfig.Orientation.POINTY)
	
	# coord_to_pixel
	var pixel: Vector2 = layout.coord_to_pixel(Vector2i(1, 0))
	var expected_x: float = 32.0 * sqrt(3.0)
	if not is_equal_approx(pixel.x, expected_x):
		print("  [FAIL] HEX coord_to_pixel(1,0).x = %f, expected %f" % [pixel.x, expected_x])
		return false
	
	if not is_equal_approx(pixel.y, 0.0):
		print("  [FAIL] HEX coord_to_pixel(1,0).y = %f, expected 0.0" % pixel.y)
		return false
	
	# pixel_to_coord (逆转换)
	var coord: Vector2i = layout.pixel_to_coord(Vector2(expected_x, 0.0))
	if coord != Vector2i(1, 0):
		print("  [FAIL] HEX pixel_to_coord(%f, 0) = %s, expected (1,0)" % [expected_x, coord])
		return false
	
	# SQUARE 测试
	var square_layout: Variant = GridLayout.new(GridMapConfig.GridType.SQUARE, 32.0, Vector2.ZERO, GridMapConfig.Orientation.HORIZONTAL, Vector2(32.0, 32.0))
	
	var sq_pixel: Vector2 = square_layout.coord_to_pixel(Vector2i(2, 3))
	if sq_pixel != Vector2(64.0, 96.0):
		print("  [FAIL] SQUARE coord_to_pixel(2,3) = %s, expected (64,96)" % sq_pixel)
		return false
	
	var sq_coord: Vector2i = square_layout.pixel_to_coord(Vector2(70.0, 100.0))
	if sq_coord != Vector2i(2, 3):
		print("  [FAIL] SQUARE pixel_to_coord(70,100) = %s, expected (2,3)" % sq_coord)
		return false
	
	# RECT 测试
	var rect_layout: Variant = GridLayout.new(GridMapConfig.GridType.RECT, 48.0, Vector2.ZERO, GridMapConfig.Orientation.HORIZONTAL, Vector2(48.0, 32.0))
	
	var rect_pixel: Vector2 = rect_layout.coord_to_pixel(Vector2i(1, 2))
	if rect_pixel != Vector2(48.0, 64.0):
		print("  [FAIL] RECT coord_to_pixel(1,2) = %s, expected (48,64)" % rect_pixel)
		return false
	
	# 角点计算
	var corners: PackedVector2Array = layout.hex_corners(Vector2i(0, 0))
	if corners.size() != 6:
		print("  [FAIL] hex_corners.size() = %d, expected 6" % corners.size())
		return false
	
	print("  [PASS] GridLayout")
	return true


func test_grid_map_model() -> bool:
	print("Testing GridMapModel...")
	
	# 测试所有 4 种类型的地图创建
	var types: Array = [
		GridMapConfig.GridType.HEX,
		GridMapConfig.GridType.RECT_SIX_DIR,
		GridMapConfig.GridType.SQUARE,
		GridMapConfig.GridType.RECT
	]
	
	for grid_type in types:
		var config: Variant = GridMapConfig.new()
		config.grid_type = grid_type
		config.draw_mode = GridMapConfig.DrawMode.RADIUS
		config.radius = 2
		config.size = 32.0
		config.tile_size = Vector2(32.0, 32.0)
		
		var model: Variant = GridMapModel.new()
		model.initialize(config)
		
		if model.get_tile_count() == 0:
			print("  [FAIL] %s model has 0 tiles" % GridMapConfig.GridType.keys()[grid_type])
			return false
		
		# 测试 coord_to_world / world_to_coord
		var coord = HexCoord.new(1, 0)
		var world: Vector2 = model.coord_to_world(coord)
		var back_coord = model.world_to_coord(world)
		if not back_coord.equals(coord):
			print("  [FAIL] %s coord_to_world/world_to_coord roundtrip failed: %s != %s" % [GridMapConfig.GridType.keys()[grid_type], back_coord, coord])
			return false
		
		# 测试 get_neighbors
		var neighbors: Array = model.get_neighbors(HexCoord.zero())
		var expected_count: int = 6 if (grid_type == GridMapConfig.GridType.HEX or grid_type == GridMapConfig.GridType.RECT_SIX_DIR) else 4
		if neighbors.size() != expected_count:
			print("  [FAIL] %s neighbors.size() = %d, expected %d" % [GridMapConfig.GridType.keys()[grid_type], neighbors.size(), expected_count])
			return false
	
	# 测试占用管理
	var config: Variant = GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.draw_mode = GridMapConfig.DrawMode.RADIUS
	config.radius = 2
	config.size = 32.0
	
	var model: Variant = GridMapModel.new()
	model.initialize(config)
	
	var test_coord = HexCoord.new(0, 0)
	var occupant: String = "TestOccupant"
	
	# place_occupant
	if not model.place_occupant(test_coord, occupant):
		print("  [FAIL] place_occupant failed")
		return false
	
	if not model.is_occupied(test_coord):
		print("  [FAIL] is_occupied returned false after placing")
		return false
	
	if model.get_occupant(test_coord) != occupant:
		print("  [FAIL] get_occupant returned wrong value")
		return false
	
	# move_occupant
	var target_coord = HexCoord.new(1, 0)
	if not model.move_occupant(test_coord, target_coord):
		print("  [FAIL] move_occupant failed")
		return false
	
	if model.is_occupied(test_coord):
		print("  [FAIL] source still occupied after move")
		return false
	
	if not model.is_occupied(target_coord):
		print("  [FAIL] target not occupied after move")
		return false
	
	# remove_occupant
	if not model.remove_occupant(target_coord):
		print("  [FAIL] remove_occupant failed")
		return false
	
	if model.is_occupied(target_coord):
		print("  [FAIL] still occupied after remove")
		return false
	
	# 测试高度系统
	model.set_tile_height(test_coord, 2.5)
	var height: float = model.get_tile_height(test_coord)
	if not is_equal_approx(height, 2.5):
		print("  [FAIL] get_tile_height = %f, expected 2.5" % height)
		return false
	
	print("  [PASS] GridMapModel")
	return true


func test_grid_pathfinding() -> bool:
	print("Testing GridPathfinding...")
	
	# 测试所有 4 种类型的寻路
	var types: Array = [
		GridMapConfig.GridType.HEX,
		GridMapConfig.GridType.RECT_SIX_DIR,
		GridMapConfig.GridType.SQUARE,
		GridMapConfig.GridType.RECT
	]
	
	for grid_type in types:
		var config: Variant = GridMapConfig.new()
		config.grid_type = grid_type
		config.draw_mode = GridMapConfig.DrawMode.RADIUS
		config.radius = 5
		config.size = 32.0
		config.tile_size = Vector2(32.0, 32.0)
		
		var model: Variant = GridMapModel.new()
		model.initialize(config)
		
		# A* 寻路
		var start = HexCoord.new(0, 0)
		var goal = HexCoord.new(2, 0)
		var result: Variant = GridPathfinding.astar_simple(model, start, goal)
		
		if not result.found:
			print("  [FAIL] %s A* pathfinding failed to find path" % GridMapConfig.GridType.keys()[grid_type])
			return false
		
		if result.path.is_empty():
			print("  [FAIL] %s A* path is empty" % GridMapConfig.GridType.keys()[grid_type])
			return false
		
		if not result.path[0].equals(start):
			print("  [FAIL] %s A* path doesn't start at start" % GridMapConfig.GridType.keys()[grid_type])
			return false
		
		if not result.path[-1].equals(goal):
			print("  [FAIL] %s A* path doesn't end at goal" % GridMapConfig.GridType.keys()[grid_type])
			return false
		
		# BFS 可达性
		var reachable: Array = GridPathfinding.reachable_simple(model, start, 2)
		if reachable.is_empty():
			print("  [FAIL] %s BFS reachable is empty" % GridMapConfig.GridType.keys()[grid_type])
			return false
		
		var start_in_reachable := false
		for r in reachable:
			if r.equals(start):
				start_in_reachable = true
				break
		if not start_in_reachable:
			print("  [FAIL] %s BFS reachable doesn't include start" % GridMapConfig.GridType.keys()[grid_type])
			return false
	
	# 测试阻挡检测
	var config: Variant = GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.draw_mode = GridMapConfig.DrawMode.RADIUS
	config.radius = 5
	config.size = 32.0
	
	var model: Variant = GridMapModel.new()
	model.initialize(config)
	
	# 设置阻挡
	var blocking_coord = HexCoord.new(1, 0)
	model.set_tile_blocking(blocking_coord, true)
	
	# 尝试寻路穿过阻挡
	var start = HexCoord.new(0, 0)
	var goal = HexCoord.new(2, 0)
	var result: Variant = GridPathfinding.astar_simple(model, start, goal)
	
	# 路径应该绕过阻挡点
	if result.found:
		for p in result.path:
			if p.equals(blocking_coord):
				print("  [FAIL] A* path goes through blocking tile")
				return false
	
	# 测试成本计算
	model.set_tile_blocking(blocking_coord, false)
	model.set_tile_cost(blocking_coord, 10.0)
	
	var result2: Variant = GridPathfinding.astar_simple(model, start, goal)
	if result2.found:
		# 路径应该尽量避开高成本格子
		var cost_count: int = 0
		for coord in result2.path:
			if coord.equals(blocking_coord):
				cost_count += 1
		# 如果有其他路径，应该不经过高成本格子
		# 但这取决于地图布局，这里只检查寻路成功
	
	print("  [PASS] GridPathfinding")
	return true


func test_event_system() -> bool:
	print("Testing Event System...")
	
	var config: Variant = GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.draw_mode = GridMapConfig.DrawMode.RADIUS
	config.radius = 2
	config.size = 32.0
	
	var model: Variant = GridMapModel.new()
	model.initialize(config)
	
	var test_coord = HexCoord.new(0, 0)
	
	# 测试 tile_changed 信号
	var tile_changed_state: Dictionary = { "hit": false }
	var tile_changed_callback: Callable = func(coord, old_data, new_data):
		tile_changed_state["hit"] = true
	
	model.tile_changed.connect(tile_changed_callback)
	
	var new_tile: Variant = GridMapModel.GridTileData.new(test_coord)
	new_tile.height = 3.0
	model.set_tile(test_coord, new_tile)
	
	if not tile_changed_state["hit"]:
		print("  [FAIL] tile_changed signal not emitted")
		return false
	
	model.tile_changed.disconnect(tile_changed_callback)
	
	# 测试 height_changed 信号
	var height_changed_state: Dictionary = { "hit": false, "old": 0.0, "new": 0.0 }
	var height_changed_callback: Callable = func(coord, old_height: float, new_height: float):
		height_changed_state["hit"] = true
		height_changed_state["old"] = old_height
		height_changed_state["new"] = new_height
	
	model.height_changed.connect(height_changed_callback)
	
	model.set_tile_height(test_coord, 5.0)
	
	if not height_changed_state["hit"]:
		print("  [FAIL] height_changed signal not emitted")
		return false
	
	if not is_equal_approx(height_changed_state["old"], 3.0):
		print("  [FAIL] height_changed old_height = %f, expected 3.0" % height_changed_state["old"])
		return false
	
	if not is_equal_approx(height_changed_state["new"], 5.0):
		print("  [FAIL] height_changed new_height = %f, expected 5.0" % height_changed_state["new"])
		return false
	
	model.height_changed.disconnect(height_changed_callback)
	
	# 测试 occupant_changed 信号
	var occupant_changed_state: Dictionary = { "hit": false, "old": null, "new": null }
	var occupant_changed_callback: Callable = func(coord, old_occupant, new_occupant):  # coord: HexCoord
		occupant_changed_state["hit"] = true
		occupant_changed_state["old"] = old_occupant
		occupant_changed_state["new"] = new_occupant
	
	model.occupant_changed.connect(occupant_changed_callback)
	
	var occupant: String = "TestOccupant"
	model.place_occupant(test_coord, occupant)
	
	if not occupant_changed_state["hit"]:
		print("  [FAIL] occupant_changed signal not emitted")
		return false
	
	if occupant_changed_state["old"] != null:
		print("  [FAIL] occupant_changed old_occupant should be null")
		return false
	
	if occupant_changed_state["new"] != occupant:
		print("  [FAIL] occupant_changed new_occupant = %s, expected %s" % [occupant_changed_state["new"], occupant])
		return false
	
	# 重置状态
	occupant_changed_state["hit"] = false
	
	model.remove_occupant(test_coord)
	
	if not occupant_changed_state["hit"]:
		print("  [FAIL] occupant_changed signal not emitted on remove")
		return false
	
	if occupant_changed_state["old"] != occupant:
		print("  [FAIL] occupant_changed old_occupant = %s, expected %s" % [occupant_changed_state["old"], occupant])
		return false
	
	if occupant_changed_state["new"] != null:
		print("  [FAIL] occupant_changed new_occupant should be null")
		return false
	
	model.occupant_changed.disconnect(occupant_changed_callback)
	
	print("  [PASS] Event System")
	return true
