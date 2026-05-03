## RtsObstructionManager — Register acceptance smoke (M2.6 — AC4 + AC7)
##
## 验证 manager 注册流程:
##   - add_unit_shape × 5 + add_static_shape × 3 → tag 1..8 单调递增
##   - manager.size() == 8 (0 = invalid 哨兵, 不计入)
##   - get_obstructions_in_range(中心, 大半径) 返回 8 shape, 按 tag 升序 (§12.4 determinism)
##   - get_shape(tag) 反查正确
##
## 不依赖 RtsBattleGrid / GameWorld / procedure — 独立构造 grid + registry + manager。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_register_basic()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - obstruction_manager register — 8 shapes registered, tags 1..8, sorted query OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_register_basic() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(50, 50)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	# 注册 5 个 unit shape (圆) — 散布在 (100, 100) 周围
	var unit_tags: Array[int] = []
	for i in range(5):
		var pos := Vector2(100.0 + float(i) * 30.0, 100.0)
		var tag: int = manager.add_unit_shape("unit_%d" % i, pos, 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
		unit_tags.append(tag)

	# 注册 3 个 static shape (OBB 建筑) — 在 (300, 300) 区域
	var static_tags: Array[int] = []
	for i in range(3):
		var pos := Vector2(300.0 + float(i) * 80.0, 300.0)
		var tag: int = manager.add_static_shape("building_%d" % i, pos, 0.0, 64.0, 64.0, RtsObstructionFlags.BLOCK_PATHFINDING | RtsObstructionFlags.BLOCK_FOUNDATION, "1")
		static_tags.append(tag)

	# tag 1..5 + 6..8 单调递增 (R5 决策: _next_tag 永不复用)
	for i in range(5):
		if unit_tags[i] != i + 1:
			_failures.append("unit_tags[%d] expected %d got %d" % [i, i + 1, unit_tags[i]])
	for i in range(3):
		if static_tags[i] != 6 + i:
			_failures.append("static_tags[%d] expected %d got %d" % [i, 6 + i, static_tags[i]])

	# manager.size() == 8
	if manager.size() != 8:
		_failures.append("manager.size() expected 8 got %d" % manager.size())

	# next_tag() == 9 (1..8 已分配, 下一个是 9)
	if manager.next_tag() != 9:
		_failures.append("manager.next_tag() expected 9 got %d" % manager.next_tag())

	# get_shape(tag) 反查正确
	var s1: RtsObstructionShape = manager.get_shape(1)
	if s1 == null or not (s1 is RtsObstructionShapeUnit) or s1.entity_id != "unit_0":
		_failures.append("get_shape(1) expected unit_0 unit, got %s" % str(s1))
	var s6: RtsObstructionShape = manager.get_shape(6)
	if s6 == null or not (s6 is RtsObstructionShapeStatic) or s6.entity_id != "building_0":
		_failures.append("get_shape(6) expected building_0 static, got %s" % str(s6))
	if manager.get_shape(99) != null:
		_failures.append("get_shape(99) for unregistered tag expected null")

	# get_obstructions_in_range(中心, 大半径) 返回所有 8 shape, 按 tag 升序
	var all_shapes: Array = manager.get_obstructions_in_range(Vector2(200.0, 200.0), 1000.0)
	if all_shapes.size() != 8:
		_failures.append("get_obstructions_in_range(big radius) expected 8 shapes, got %d" % all_shapes.size())
	# 验证升序 (§12.4 determinism)
	var prev_tag: int = 0
	for s in all_shapes:
		var shape: RtsObstructionShape = s as RtsObstructionShape
		if shape.tag <= prev_tag:
			_failures.append("get_obstructions_in_range tags not monotonic ascending: prev=%d cur=%d" % [prev_tag, shape.tag])
		prev_tag = shape.tag

	# 半径范围查询 (只命中 (100, 100) 周围 5 unit, 不命中 (300, 300) 区域)
	var nearby_units: Array = manager.get_obstructions_in_range(Vector2(160.0, 100.0), 100.0)
	# 5 unit 在 (100, 130, 160, 190, 220, 100), spatial bucket size 256, query 半径 100 → AABB 覆盖 1-2 桶,
	# 5 个 unit 全部应进 query 候选 (粗筛, 不精确相交)
	if nearby_units.size() < 5:
		_failures.append("get_obstructions_in_range(160,100, 100) expected ≥5 unit, got %d" % nearby_units.size())


func _build_registry() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var air_cfg := RtsPassabilityClassConfig.new()
	air_cfg.class_name_id = "air"
	air_cfg.clearance = 8.0
	registry.register(air_cfg)
	return registry
