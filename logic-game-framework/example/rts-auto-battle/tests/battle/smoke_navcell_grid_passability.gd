## RtsNavcellGrid + RtsPassabilityClassRegistry acceptance smoke (M1.5 — AC1 + AC2 + AC8)
##
## 验证以下断言:
##
## AC1 — Registry 落地:
##   - register("default") + register("air") → bit_index 自动分配 0/1
##   - get_mask("default") == 0x1
##   - get_mask("air") == 0x2
##   - duplicate register 触发 assert_crash (本 smoke 不验 crash 路径; 留单元测试)
##   - get_mask("unknown") == 0 (未注册返 0)
##
## AC2 — RtsNavcellGrid 落地:
##   - 初始 is_passable 全 true (清状态)
##   - or_data 设 bit → is_passable 该 mask 视角变 false
##   - and_data 清 bit → is_passable 该 mask 视角又 true
##   - 边界外 is_passable 返 false (i<0 / i>=w / j<0 / j>=h)
##   - get_data 边界外返 -1
##
## AC8 — Multi-class 不互相干扰:
##   - 在 (5, 5) 写 default bit → default 视角阻挡, air 视角仍可通过
##   - 在 (10, 10) 写 air bit → air 视角阻挡, default 视角仍可通过
##
## 不依赖 RtsBattleGrid / GameWorld / procedure — 纯数据结构单元 smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	# 必须 GameWorld.init 因为 Log 等 autoload 依赖之 (即使本 smoke 不用 actor)
	GameWorld.init()

	_test_registry_basic()
	_test_navcell_basic()
	_test_navcell_or_and_data()
	_test_navcell_boundary()
	_test_multi_class_isolation()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - navcell grid passability — AC1+AC2+AC8 all assertions OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Test cases ==========

func _test_registry_basic() -> void:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var air_cfg := RtsPassabilityClassConfig.new()
	air_cfg.class_name_id = "air"
	air_cfg.clearance = 8.0
	registry.register(air_cfg)

	# AC1: bit_index 自动分配 0 / 1
	if ground_cfg.bit_index != 0:
		_failures.append("default bit_index expected 0 got %d" % ground_cfg.bit_index)
	if air_cfg.bit_index != 1:
		_failures.append("air bit_index expected 1 got %d" % air_cfg.bit_index)

	# AC1: get_mask 数字
	if registry.get_mask("default") != 0x1:
		_failures.append("get_mask(default) expected 0x1 got 0x%X" % registry.get_mask("default"))
	if registry.get_mask("air") != 0x2:
		_failures.append("get_mask(air) expected 0x2 got 0x%X" % registry.get_mask("air"))

	# AC1: 未注册 class 返 0
	if registry.get_mask("unknown") != 0:
		_failures.append("get_mask(unknown) expected 0 got %d" % registry.get_mask("unknown"))

	# AC1: max_clearance = max(14.0, 8.0)
	if not is_equal_approx(registry.max_clearance(), 14.0):
		_failures.append("max_clearance expected 14.0 got %f" % registry.max_clearance())

	# AC1: size
	if registry.size() != 2:
		_failures.append("registry size expected 2 got %d" % registry.size())


func _test_navcell_basic() -> void:
	var grid := RtsNavcellGrid.new(10, 10)
	# AC2: 初始 clean → is_passable 任何 mask 都 true
	if not grid.is_passable(0, 0, 0x1):
		_failures.append("clean (0,0) is_passable(default) expected true")
	if not grid.is_passable(5, 5, 0x2):
		_failures.append("clean (5,5) is_passable(air) expected true")
	# AC2: width / height
	if grid.width() != 10 or grid.height() != 10:
		_failures.append("width/height expected 10/10 got %d/%d" % [grid.width(), grid.height()])
	# AC2: get_data 初始 0
	if grid.get_data(3, 3) != 0:
		_failures.append("clean (3,3) get_data expected 0 got %d" % grid.get_data(3, 3))


func _test_navcell_or_and_data() -> void:
	var grid := RtsNavcellGrid.new(10, 10)
	# AC2: or_data 设 bit
	grid.or_data(5, 5, 0x1)
	if grid.is_passable(5, 5, 0x1):
		_failures.append("after or_data(5,5,0x1) is_passable(0x1) expected false")
	if grid.get_data(5, 5) != 0x1:
		_failures.append("after or_data(5,5,0x1) get_data expected 0x1 got 0x%X" % grid.get_data(5, 5))
	# AC2: dirty 标记
	if not grid.is_dirty(5, 5):
		_failures.append("after or_data dirtiness expected true")

	# AC2: and_data 清 bit
	grid.and_data(5, 5, 0x1)
	if not grid.is_passable(5, 5, 0x1):
		_failures.append("after and_data(5,5,0x1) is_passable(0x1) expected true")
	if grid.get_data(5, 5) != 0:
		_failures.append("after and_data(5,5,0x1) get_data expected 0 got 0x%X" % grid.get_data(5, 5))

	# AC2: clear_dirty
	grid.clear_dirty()
	if grid.is_dirty(5, 5):
		_failures.append("after clear_dirty is_dirty expected false")


func _test_navcell_boundary() -> void:
	var grid := RtsNavcellGrid.new(10, 10)
	# AC2: 边界外 is_passable 返 false
	if grid.is_passable(-1, 0, 0x1):
		_failures.append("is_passable(-1,0) expected false (out of bounds)")
	if grid.is_passable(0, -1, 0x1):
		_failures.append("is_passable(0,-1) expected false")
	if grid.is_passable(10, 0, 0x1):
		_failures.append("is_passable(10,0) expected false (i==width)")
	if grid.is_passable(0, 10, 0x1):
		_failures.append("is_passable(0,10) expected false (j==height)")
	if grid.is_passable(100, 100, 0x1):
		_failures.append("is_passable(100,100) expected false")

	# AC2: get_data 边界外返 -1
	if grid.get_data(-1, 0) != -1:
		_failures.append("get_data(-1,0) expected -1")
	if grid.get_data(100, 0) != -1:
		_failures.append("get_data(100,0) expected -1")


func _test_multi_class_isolation() -> void:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	var air_cfg := RtsPassabilityClassConfig.new()
	air_cfg.class_name_id = "air"
	air_cfg.clearance = 8.0
	registry.register(air_cfg)
	var default_mask: int = registry.get_mask("default")  # 0x1
	var air_mask: int = registry.get_mask("air")  # 0x2

	var grid := RtsNavcellGrid.new(20, 20)

	# AC8: 在 (5, 5) 写 default bit → default 视角阻挡, air 视角仍可通过
	grid.or_data(5, 5, default_mask)
	if grid.is_passable(5, 5, default_mask):
		_failures.append("AC8 (5,5) default mask after or: expected blocked")
	if not grid.is_passable(5, 5, air_mask):
		_failures.append("AC8 (5,5) air mask after default-or: expected passable (multi-class isolation)")

	# AC8: 在 (10, 10) 写 air bit → air 视角阻挡, default 视角仍可通过
	grid.or_data(10, 10, air_mask)
	if grid.is_passable(10, 10, air_mask):
		_failures.append("AC8 (10,10) air mask after or: expected blocked")
	if not grid.is_passable(10, 10, default_mask):
		_failures.append("AC8 (10,10) default mask after air-or: expected passable (multi-class isolation)")

	# 双 bit 同 cell: (15, 15) 同时写 default + air
	grid.or_data(15, 15, default_mask)
	grid.or_data(15, 15, air_mask)
	if grid.is_passable(15, 15, default_mask):
		_failures.append("AC8 (15,15) default mask after dual-or: expected blocked")
	if grid.is_passable(15, 15, air_mask):
		_failures.append("AC8 (15,15) air mask after dual-or: expected blocked")
	# 清掉 default bit, air 仍阻挡
	grid.and_data(15, 15, default_mask)
	if not grid.is_passable(15, 15, default_mask):
		_failures.append("AC8 (15,15) default mask after and: expected passable")
	if grid.is_passable(15, 15, air_mask):
		_failures.append("AC8 (15,15) air mask after only-default-and: expected blocked (air bit untouched)")
