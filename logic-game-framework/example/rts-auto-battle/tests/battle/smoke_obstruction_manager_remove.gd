## RtsObstructionManager — Remove + idempotency acceptance smoke (M2.6 — AC4 + AC7)
##
## 验证 manager 删除流程:
##   - add → remove → manager.size() 减少, get_shape(tag) 返 null
##   - remove 不存在的 tag 不 crash (幂等)
##   - move_shape 不存在的 tag 不 crash (幂等)
##   - 删完所有 shape 后 _shapes / _spatial_index 清空 (size == 0)
##   - 删后 query 不返回已删 shape
##
## 不依赖 RtsBattleGrid / GameWorld / procedure — 独立构造。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_remove_basic()
	_test_remove_idempotent()
	_test_remove_query_consistency()
	_test_remove_all_then_readd()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - obstruction_manager remove — basic + idempotent + query-consistent + readd OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_remove_basic() -> void:
	var manager: RtsObstructionManager = _build_manager()

	# Add 3 unit + 2 static
	var t1: int = manager.add_unit_shape("u1", Vector2(100.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	var t2: int = manager.add_unit_shape("u2", Vector2(150.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	manager.add_unit_shape("u3", Vector2(200.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	manager.add_static_shape("s1", Vector2(300.0, 300.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "1")
	manager.add_static_shape("s2", Vector2(400.0, 300.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "1")

	if manager.size() != 5:
		_failures.append("after 5 add: size expected 5 got %d" % manager.size())

	# Remove tag t1 → size 4, get_shape(t1) = null, t2 仍可查
	manager.remove_shape(t1)
	if manager.size() != 4:
		_failures.append("after remove t1: size expected 4 got %d" % manager.size())
	if manager.get_shape(t1) != null:
		_failures.append("after remove t1: get_shape(t1) expected null")
	if manager.get_shape(t2) == null:
		_failures.append("after remove t1: get_shape(t2) should still exist")


func _test_remove_idempotent() -> void:
	var manager: RtsObstructionManager = _build_manager()
	var tag: int = manager.add_unit_shape("u1", Vector2(100.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")

	# Remove 一次 → 成功
	manager.remove_shape(tag)
	if manager.size() != 0:
		_failures.append("after first remove: size expected 0 got %d" % manager.size())

	# Remove 同 tag 第二次 → 静默 no-op (不 crash)
	manager.remove_shape(tag)
	if manager.size() != 0:
		_failures.append("after duplicate remove: size still 0 expected, got %d" % manager.size())

	# Remove 完全不存在的 tag → 静默 no-op
	manager.remove_shape(99999)
	if manager.size() != 0:
		_failures.append("after remove(99999): size still 0 expected, got %d" % manager.size())

	# move_shape 不存在的 tag → 静默 no-op
	manager.move_shape(99999, Vector2(500.0, 500.0))
	# 没断言, 只要不 crash

	# set_unit_moving_flag 不存在的 tag → no-op
	manager.set_unit_moving_flag(99999, true)


func _test_remove_query_consistency() -> void:
	var manager: RtsObstructionManager = _build_manager()
	var t1: int = manager.add_unit_shape("u1", Vector2(100.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	var t2: int = manager.add_unit_shape("u2", Vector2(110.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	var t3: int = manager.add_unit_shape("u3", Vector2(120.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")

	# Query before remove: 3 个
	var before: Array = manager.get_obstructions_in_range(Vector2(110.0, 100.0), 100.0)
	if before.size() != 3:
		_failures.append("query before remove: expected 3 got %d" % before.size())

	# Remove t2 → query 只剩 2
	manager.remove_shape(t2)
	var after: Array = manager.get_obstructions_in_range(Vector2(110.0, 100.0), 100.0)
	if after.size() != 2:
		_failures.append("query after remove t2: expected 2 got %d" % after.size())
	# t2 不在 result 中 (按 tag 升序: 应是 t1, t3)
	for s in after:
		var shape: RtsObstructionShape = s as RtsObstructionShape
		if shape.tag == t2:
			_failures.append("query after remove t2: result still contains t2 shape")


func _test_remove_all_then_readd() -> void:
	var manager: RtsObstructionManager = _build_manager()

	# Add 3 个
	var tags: Array[int] = []
	for i in range(3):
		tags.append(manager.add_unit_shape("u%d" % i, Vector2(100.0 + float(i) * 30.0, 100.0), 14.0,
			RtsObstructionFlags.BLOCK_MOVEMENT, "0"))

	# Remove 全部
	for t in tags:
		manager.remove_shape(t)
	if manager.size() != 0:
		_failures.append("after remove all 3: size expected 0 got %d" % manager.size())

	# Re-add: tag 应继续从 _next_tag (= 4) 开始, 不复用
	var new_tag: int = manager.add_unit_shape("u_new", Vector2(500.0, 500.0), 14.0,
		RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	if new_tag != 4:
		_failures.append("after remove all + re-add: tag expected 4 (no reuse) got %d" % new_tag)
	if manager.size() != 1:
		_failures.append("after remove all + re-add: size expected 1 got %d" % manager.size())


func _build_manager() -> RtsObstructionManager:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var grid := RtsNavcellGrid.new(50, 50)
	return RtsObstructionManager.new(grid, registry)
