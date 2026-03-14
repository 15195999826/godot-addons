## GridMath 单元测试
##
## 运行方式: 在 Godot 编辑器中运行此场景
extends SceneTree


func _init() -> void:
	print("========== GridMath Tests ==========")
	
	var passed: int = 0
	var failed: int = 0
	
	# 测试六边形距离
	if _test_hex_distance():
		passed += 1
		print("[PASS] HEX Distance")
	else:
		failed += 1
		print("[FAIL] HEX Distance")
	
	# 测试曼哈顿距离
	if _test_manhattan_distance():
		passed += 1
		print("[PASS] Manhattan Distance")
	else:
		failed += 1
		print("[FAIL] Manhattan Distance")
	
	# 测试切比雪夫距离
	if _test_chebyshev_distance():
		passed += 1
		print("[PASS] Chebyshev Distance")
	else:
		failed += 1
		print("[FAIL] Chebyshev Distance")
	
	# 测试六边形邻居
	if _test_hex_neighbors():
		passed += 1
		print("[PASS] HEX Neighbors")
	else:
		failed += 1
		print("[FAIL] HEX Neighbors")
	
	# 测试正方形邻居
	if _test_square_neighbors():
		passed += 1
		print("[PASS] SQUARE Neighbors")
	else:
		failed += 1
		print("[FAIL] SQUARE Neighbors")
	
	# 测试 RECT_SIX_DIR 邻居
	if _test_rect_six_dir_neighbors():
		passed += 1
		print("[PASS] RECT_SIX_DIR Neighbors")
	else:
		failed += 1
		print("[FAIL] RECT_SIX_DIR Neighbors")
	
	# 测试通用 get_neighbors
	if _test_get_neighbors():
		passed += 1
		print("[PASS] get_neighbors()")
	else:
		failed += 1
		print("[FAIL] get_neighbors()")
	
	print("====================================")
	print("Passed: %d, Failed: %d" % [passed, failed])
	
	if failed > 0:
		print("TESTS FAILED!")
		quit(1)
	else:
		print("ALL TESTS PASSED!")
		quit(0)


func _test_hex_distance() -> bool:
	# Concrete Test Cases
	# assert(GridMath.hex_distance(Vector2i(0, 0), Vector2i(1, 0)) == 1)
	var d1 := GridMath.hex_distance(Vector2i(0, 0), Vector2i(1, 0))
	if d1 != 1:
		print("  hex_distance((0,0), (1,0)) = %d, expected 1" % d1)
		return false
	
	# assert(GridMath.hex_distance(Vector2i(0, 0), Vector2i(2, -1)) == 2)
	var d2 := GridMath.hex_distance(Vector2i(0, 0), Vector2i(2, -1))
	if d2 != 2:
		print("  hex_distance((0,0), (2,-1)) = %d, expected 2" % d2)
		return false
	
	# assert(GridMath.hex_distance(Vector2i(0, 0), Vector2i(3, -3)) == 3)
	var d3 := GridMath.hex_distance(Vector2i(0, 0), Vector2i(3, -3))
	if d3 != 3:
		print("  hex_distance((0,0), (3,-3)) = %d, expected 3" % d3)
		return false
	
	return true


func _test_manhattan_distance() -> bool:
	# Concrete Test Cases
	# assert(GridMath.manhattan_distance(Vector2i(0, 0), Vector2i(3, 4)) == 7)
	var d1 := GridMath.manhattan_distance(Vector2i(0, 0), Vector2i(3, 4))
	if d1 != 7:
		print("  manhattan_distance((0,0), (3,4)) = %d, expected 7" % d1)
		return false
	
	# assert(GridMath.manhattan_distance(Vector2i(1, 1), Vector2i(4, 5)) == 7)
	var d2 := GridMath.manhattan_distance(Vector2i(1, 1), Vector2i(4, 5))
	if d2 != 7:
		print("  manhattan_distance((1,1), (4,5)) = %d, expected 7" % d2)
		return false
	
	return true


func _test_chebyshev_distance() -> bool:
	# Concrete Test Cases
	# assert(GridMath.chebyshev_distance(Vector2i(0, 0), Vector2i(3, 4)) == 4)
	var d1 := GridMath.chebyshev_distance(Vector2i(0, 0), Vector2i(3, 4))
	if d1 != 4:
		print("  chebyshev_distance((0,0), (3,4)) = %d, expected 4" % d1)
		return false
	
	return true


func _test_hex_neighbors() -> bool:
	# Concrete Test Cases
	# var hex_neighbors := GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.HEX)
	# assert(hex_neighbors.size() == 6)
	var neighbors := GridMath.get_hex_neighbors(Vector2i(0, 0))
	if neighbors.size() != 6:
		print("  hex_neighbors.size() = %d, expected 6" % neighbors.size())
		return false
	
	# assert(Vector2i(1, 0) in hex_neighbors)   # 右
	if not (Vector2i(1, 0) in neighbors):
		print("  Vector2i(1, 0) not in hex_neighbors")
		return false
	
	# assert(Vector2i(-1, 0) in hex_neighbors)  # 左
	if not (Vector2i(-1, 0) in neighbors):
		print("  Vector2i(-1, 0) not in hex_neighbors")
		return false
	
	return true


func _test_square_neighbors() -> bool:
	# Concrete Test Cases
	# var square_neighbors := GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.SQUARE)
	# assert(square_neighbors.size() == 4)
	var neighbors := GridMath.get_square_neighbors(Vector2i(0, 0))
	if neighbors.size() != 4:
		print("  square_neighbors.size() = %d, expected 4" % neighbors.size())
		return false
	
	# assert(Vector2i(1, 0) in square_neighbors)   # 右
	if not (Vector2i(1, 0) in neighbors):
		print("  Vector2i(1, 0) not in square_neighbors")
		return false
	
	# assert(Vector2i(0, 1) in square_neighbors)   # 下
	if not (Vector2i(0, 1) in neighbors):
		print("  Vector2i(0, 1) not in square_neighbors")
		return false
	
	return true


func _test_rect_six_dir_neighbors() -> bool:
	# 测试偶数行
	var even_neighbors := GridMath.get_rect_six_dir_neighbors(Vector2i(0, 0))
	if even_neighbors.size() != 6:
		print("  rect_six_dir even row neighbors.size() = %d, expected 6" % even_neighbors.size())
		return false
	
	# 测试奇数行
	var odd_neighbors := GridMath.get_rect_six_dir_neighbors(Vector2i(0, 1))
	if odd_neighbors.size() != 6:
		print("  rect_six_dir odd row neighbors.size() = %d, expected 6" % odd_neighbors.size())
		return false
	
	# 验证偶数行和奇数行的邻居不同
	var even_set: Dictionary = {}
	for n in even_neighbors:
		even_set[n] = true
	
	var odd_set: Dictionary = {}
	for n in odd_neighbors:
		odd_set[n] = true
	
	# 偶数行和奇数行应该有不同的邻居模式
	# 偶数行 (0,0) 的邻居应该包含 (-1, -1) 左上
	if not (Vector2i(-1, -1) in even_set):
		print("  Vector2i(-1, -1) not in even row neighbors")
		return false
	
	# 奇数行 (0,1) 的邻居应该包含 (1, 0) 右上 (相对于 (0,1))
	# 实际上是 (0,1) + (1,-1) = (1, 0)
	if not (Vector2i(1, 0) in odd_set):
		print("  Vector2i(1, 0) not in odd row neighbors")
		return false
	
	return true


func _test_get_neighbors() -> bool:
	# 测试通用 get_neighbors 接口
	var hex_neighbors := GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.HEX)
	if hex_neighbors.size() != 6:
		print("  get_neighbors(HEX).size() = %d, expected 6" % hex_neighbors.size())
		return false
	
	var square_neighbors := GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.SQUARE)
	if square_neighbors.size() != 4:
		print("  get_neighbors(SQUARE).size() = %d, expected 4" % square_neighbors.size())
		return false
	
	var rect_neighbors := GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.RECT)
	if rect_neighbors.size() != 4:
		print("  get_neighbors(RECT).size() = %d, expected 4" % rect_neighbors.size())
		return false
	
	var rect_six_neighbors := GridMath.get_neighbors(Vector2i(0, 0), GridMapConfig.GridType.RECT_SIX_DIR)
	if rect_six_neighbors.size() != 6:
		print("  get_neighbors(RECT_SIX_DIR).size() = %d, expected 6" % rect_six_neighbors.size())
		return false
	
	return true
