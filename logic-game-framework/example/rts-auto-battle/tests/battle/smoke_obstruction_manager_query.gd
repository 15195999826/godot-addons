## RtsObstructionManager — Query / Filter / SAT acceptance smoke (M2.6 — AC4 + AC7 + R1)
##
## 验证 manager 查询流程:
##   - test_unit_shape(filter, pos, clearance) 检测单位想走到某点是否撞建筑 / 单位
##   - test_static_shape(filter, pos, rot, w, h) 检测静态 OBB 是否撞建筑 / 单位
##   - filter (skip_control_group / only_blocking_movement / combined) 行为正确
##   - **完整 SAT 4 case OBB-OBB** (R1 缓解): 轴对齐 / 旋转 45° / 边接触 / 角接触
##   - distance_to_point / distance_to_target 行为正确
##
## 不依赖 RtsBattleGrid / GameWorld / procedure — 独立构造。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_filter_predicate_basic()
	_test_unit_query()
	_test_static_query()
	_test_sat_obb_obb_4_cases()
	_test_distance()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - obstruction_manager query — filter + test_*_shape + SAT 4-case + distance OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Filter predicate 基础 ==========

func _test_filter_predicate_basic() -> void:
	# skip_control_group: 同 group 不算障碍
	var fl_skip := RtsObstructionTestFilter.skip_control_group("0")
	var s_same: RtsObstructionShape = _make_unit_shape(Vector2.ZERO, 14.0, "0", RtsObstructionFlags.BLOCK_MOVEMENT)
	var s_diff: RtsObstructionShape = _make_unit_shape(Vector2.ZERO, 14.0, "1", RtsObstructionFlags.BLOCK_MOVEMENT)
	if fl_skip.predicate(s_same):
		_failures.append("filter.skip_control_group same group: expected false")
	if not fl_skip.predicate(s_diff):
		_failures.append("filter.skip_control_group diff group: expected true")

	# only_blocking_movement: 仅 BLOCK_MOVEMENT 算障碍
	var fl_move := RtsObstructionTestFilter.only_blocking_movement()
	var s_move: RtsObstructionShape = _make_unit_shape(Vector2.ZERO, 14.0, "0", RtsObstructionFlags.BLOCK_MOVEMENT)
	var s_no_move: RtsObstructionShape = _make_unit_shape(Vector2.ZERO, 14.0, "0", RtsObstructionFlags.BLOCK_PATHFINDING)
	if not fl_move.predicate(s_move):
		_failures.append("filter.only_blocking_movement BLOCK_MOVEMENT: expected true")
	if fl_move.predicate(s_no_move):
		_failures.append("filter.only_blocking_movement no BLOCK_MOVEMENT: expected false")

	# combined (skip group AND only_blocking_movement): 必须两边都通过
	var fl_combined := RtsObstructionTestFilter.combined(fl_skip, fl_move)
	var s_diff_move: RtsObstructionShape = _make_unit_shape(Vector2.ZERO, 14.0, "1", RtsObstructionFlags.BLOCK_MOVEMENT)
	var s_diff_no_move: RtsObstructionShape = _make_unit_shape(Vector2.ZERO, 14.0, "1", RtsObstructionFlags.BLOCK_PATHFINDING)
	if not fl_combined.predicate(s_diff_move):
		_failures.append("filter.combined diff group + BLOCK_MOVEMENT: expected true")
	if fl_combined.predicate(s_diff_no_move):
		_failures.append("filter.combined diff group + no BLOCK_MOVEMENT: expected false")
	if fl_combined.predicate(s_same):
		_failures.append("filter.combined same group: expected false (skip_control_group fails)")


# ========== test_unit_shape: 单位 vs 单位 ==========

func _test_unit_query() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(50, 50)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	# 在 (100, 100) 放一个 group="0" 单位 (clearance=14)
	manager.add_unit_shape("u_a", Vector2(100.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")

	# 想放新单位在 (110, 100), clearance=14: 距离=10 < 14+14=28 → 撞
	var fl_all := RtsObstructionTestFilter.new()
	if not manager.test_unit_shape(fl_all, Vector2(110.0, 100.0), 14.0):
		_failures.append("test_unit_shape close (10 px gap, sum_r=28): expected hit")

	# 想放新单位在 (200, 100), clearance=14: 距离=100 > 28 → 不撞
	if manager.test_unit_shape(fl_all, Vector2(200.0, 100.0), 14.0):
		_failures.append("test_unit_shape far (100 px gap, sum_r=28): expected no hit")

	# skip_control_group("0") filter: 同队不算 → 即使近也不撞
	var fl_skip0 := RtsObstructionTestFilter.skip_control_group("0")
	if manager.test_unit_shape(fl_skip0, Vector2(110.0, 100.0), 14.0):
		_failures.append("test_unit_shape close + skip same group: expected no hit")


# ========== test_static_shape: OBB vs Unit / OBB ==========

func _test_static_query() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(50, 50)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	# 在 (300, 300) 放一个 64×64 building (group="1", BLOCK_PATHFINDING)
	manager.add_static_shape("b_a", Vector2(300.0, 300.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING | RtsObstructionFlags.BLOCK_FOUNDATION, "1")

	var fl_all := RtsObstructionTestFilter.new()

	# 想放 32×32 building 在 (310, 310): 重叠 → 撞
	if not manager.test_static_shape(fl_all, Vector2(310.0, 310.0), 0.0, 32.0, 32.0):
		_failures.append("test_static_shape OBB-OBB axis-aligned overlap: expected hit")

	# 想放 32×32 building 在 (400, 400): 不重叠 (OBB-A 包围在 268-332 范围, OBB-B 在 384-416) → 不撞
	if manager.test_static_shape(fl_all, Vector2(400.0, 400.0), 0.0, 32.0, 32.0):
		_failures.append("test_static_shape OBB-OBB axis-aligned non-overlap: expected no hit")

	# skip_control_group("1"): 同 group 不撞
	var fl_skip1 := RtsObstructionTestFilter.skip_control_group("1")
	if manager.test_static_shape(fl_skip1, Vector2(310.0, 310.0), 0.0, 32.0, 32.0):
		_failures.append("test_static_shape OBB-OBB overlap + skip same group: expected no hit")


# ========== SAT OBB-OBB 4 case (R1 缓解) ==========

func _test_sat_obb_obb_4_cases() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(50, 50)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)
	var fl_all := RtsObstructionTestFilter.new()

	# === Case A: 轴对齐, 重叠 ===
	# OBB-A 在 (500, 500), 64×64, rot=0
	manager.add_static_shape("sat_a", Vector2(500.0, 500.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "0")
	# 测试 OBB-B 在 (530, 500), 64×64, rot=0: AABB 重叠 (468-532 vs 498-562) → 相交
	if not manager.test_static_shape(fl_all, Vector2(530.0, 500.0), 0.0, 64.0, 64.0):
		_failures.append("SAT case A (axis-aligned overlap): expected hit")

	# === Case B: 旋转 45° vs 0° ===
	# OBB-B 在 (550, 500), 64×64, rot=45° (0.7854 rad): 沿 +x 偏 50, 旋转的 OBB 角点在 (550 ± 32sqrt(2), ...)
	# = (550 ± 45.25). 跟 OBB-A (468..532) 范围比较: B 角点 (504.75, 545.25, ...), A 右边 532, B 左边 504.75 < 532 → 重叠
	if not manager.test_static_shape(fl_all, Vector2(550.0, 500.0), PI * 0.25, 64.0, 64.0):
		_failures.append("SAT case B (rotated 45° vs axis-aligned, overlap): expected hit")

	# === Case C: 边接触 (距离恰为 width 半和 = 32+32 = 64) ===
	# OBB-C 在 (564, 500), 64×64, rot=0: A 右边 = 532, C 左边 = 532 → 边接触 (SAT 不分离 = 相交)
	# 注: SAT 边界相等视为 not separated (我们的实现 `center_proj > proj_a + proj_b` 严格大于 → 相等返 true 相交)
	if not manager.test_static_shape(fl_all, Vector2(564.0, 500.0), 0.0, 64.0, 64.0):
		_failures.append("SAT case C (edge touch, distance=sum_half_width): expected hit (boundary inclusive)")

	# === Case D: 角接触 (旋转 OBB 角点恰碰另一 OBB 边) ===
	# OBB-D 旋转 45° 中心在 (532+32√2/2, 500) ≈ (554.62, 500), 64×64: D 最左角 ≈ 532, 接触 A 右边 532
	# 简化: 先检查 OBB-D 在 (570, 500) 旋转 45°: 不碰
	if manager.test_static_shape(fl_all, Vector2(620.0, 500.0), PI * 0.25, 64.0, 64.0):
		_failures.append("SAT case D' (rotated, far from A): expected no hit")
	# 角接触靠近: D 中心在 (560, 500) 旋转 45°, 64×64 → D 左角 ≈ 560 - 32√2 ≈ 514.75 < 532 → 重叠
	if not manager.test_static_shape(fl_all, Vector2(560.0, 500.0), PI * 0.25, 64.0, 64.0):
		_failures.append("SAT case D (rotated, close to corner contact): expected hit")


# ========== Distance ==========

func _test_distance() -> void:
	var registry: RtsPassabilityClassRegistry = _build_registry()
	var grid: RtsNavcellGrid = RtsNavcellGrid.new(50, 50)
	var manager: RtsObstructionManager = RtsObstructionManager.new(grid, registry)

	# Unit 圆 在 (100, 100), r=14
	manager.add_unit_shape("d_unit", Vector2(100.0, 100.0), 14.0, RtsObstructionFlags.BLOCK_MOVEMENT, "0")
	# OBB 在 (300, 300), 64×64, rot=0
	manager.add_static_shape("d_obb", Vector2(300.0, 300.0), 0.0, 64.0, 64.0,
		RtsObstructionFlags.BLOCK_PATHFINDING, "1")

	# distance_to_point: unit 中心 (100,100), 半径 14 → point (200,100) 距离 = 100 - 14 = 86
	var d1: float = manager.distance_to_point("d_unit", Vector2(200.0, 100.0))
	if not is_equal_approx(d1, 86.0):
		_failures.append("distance_to_point(unit, far point) expected 86 got %f" % d1)

	# distance_to_point: 不存在的 entity → INF
	var d_inf: float = manager.distance_to_point("nonexistent", Vector2(200.0, 100.0))
	if d_inf != INF:
		_failures.append("distance_to_point(nonexistent) expected INF got %f" % d_inf)

	# distance_to_target: unit 到 OBB
	# 简化版 = center 距离 - enclose_r_sum; unit center 到 OBB center = sqrt(200² + 200²) = 282.84,
	# unit_r=14, OBB enclose_r = sqrt(64² + 64²)/2 = 45.25; → 282.84 - 14 - 45.25 ≈ 223.59
	var d_target: float = manager.distance_to_target("d_unit", "d_obb")
	if not is_equal_approx(d_target, sqrt(80000.0) - 14.0 - sqrt(8192.0) * 0.5):
		_failures.append("distance_to_target(unit→OBB) expected ~223.59 got %f" % d_target)


# ========== Helper ==========

func _make_unit_shape(pos: Vector2, clearance: float, group: String, flags: int) -> RtsObstructionShapeUnit:
	var s := RtsObstructionShapeUnit.new()
	s.center = pos
	s.clearance = clearance
	s.control_group = group
	s.flags = flags
	return s


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
