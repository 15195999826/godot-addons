## RtsObstructionManager - Obstruction shape 数据库 + 空间查询 + rasterize 单例 (M2 引入)
##
## 0 A.D. `simulation2/components/CCmpObstructionManager.cpp` 的 GDScript 复刻 — 持所有 obstruction
## shape (UnitShape 圆 + StaticShape OBB), 提供:
##   - 注册 / 修改 / 注销 (add_unit_shape / add_static_shape / move_shape / set_*flag / remove_shape)
##   - 范围查询 (get_obstructions_in_range / test_unit_shape / test_static_shape)
##   - 距离 (distance_to_point / distance_to_target)
##   - rasterize (把 BLOCK_PATHFINDING shape 写到 NavcellGrid 对应 class bit)
##
## **生命周期** (H1 决策 A): RefCounted, 挂 RtsWorldGameplayInstance.obstruction_manager;
## 由 RtsAutoBattleProcedure._init 末尾构造 (传 navcell_grid + registry); 战斗结束 procedure
## 销毁时 manager 也随之 GC。**不**做 autoload (避免污染全局).
##
## **Determinism**:
##   - `_next_tag` 从 1 单调递增 **永不复用** (R5 P1 决策; tag 0 = invalid 哨兵)
##   - `get_obstructions_in_range` 走 spatial_index.query_circle (内部 sort by tag) → 升序
##   - `rasterize` 遍历 _shapes Dictionary 前先收 keys + sort (Dictionary 迭代序非 deterministic)
##   - **dirty lifecycle 不在 rasterize 内 clear_dirty()** (R5 P1-2 修订, stop runner 第 8 条):
##     rasterize 只读 dirtiness 不清;RtsWorld.tick step 7 末端统一 clear_dirty。
##
## **M2 阶段范围** (spec §1.1 / §1.2):
##   - 单位 shape = 圆 (clearance 取自 RtsUnitClassConfig.collision_radius); M3 引入 per-class buffer
##   - 建筑 shape = OBB (rotation_rad = 0; M2 还没旋转 placement)
##   - 单 class rasterize (default); M3 加 air class rasterize
##   - dirty_only=true 时仍全 shape 重刷, M3 引入真增量 dirty
##
## **0 A.D. 对照**:
##   - `ICmpObstructionManager.h` AddUnitShape / AddStaticShape / MoveShape / RemoveShape /
##     TestUnitShape / TestStaticShape / DistanceToPoint / DistanceToTarget / Rasterize
##   - SAT OBB-OBB 重叠测试: `helpers/Pathfinding.cpp:TestObstructionsAgainstSquare`
##
## **决策来源**:
##   - data-structures.md §2.3 (字段定义)
##   - interfaces.md §2 (公开 API)
##   - milestones/M2-obstruction-manager.md §M2.3 (实现步骤) + §H1 (RefCounted vs Autoload) +
##     §H4 (M2 单 class rasterize) + §H5 (distance_to_target 简化版) + §6 R1 (SAT 完整实现)
class_name RtsObstructionManager
extends RefCounted


# ========== 字段 ==========

## tag (int) → RtsObstructionShape (Unit 圆 / Static OBB 子类)。
var _shapes: Dictionary = {}

## 下一个分配的 tag; 1 起单调递增, 永不复用 (R5 决策)。tag 0 = invalid。
var _next_tag: int = 1

## Spatial index (uniform grid bucket 256 px); M2.2 引入。
var _spatial_index: RtsSpatialIndex

## Navcell grid 引用 (rasterize 写入 + mark_dirty 来源)。
var _navcell_grid: RtsNavcellGrid

## Passability registry 引用 (rasterize 时取 class bit_index;test_*_shape 取 max_clearance)。
var _passability_registry: RtsPassabilityClassRegistry


# ========== 初始化 ==========

func _init(grid: RtsNavcellGrid, registry: RtsPassabilityClassRegistry) -> void:
	Log.assert_crash(grid != null, "RtsObstructionManager", "_init: grid is null")
	Log.assert_crash(registry != null, "RtsObstructionManager", "_init: registry is null")
	_spatial_index = RtsSpatialIndex.new()
	_navcell_grid = grid
	_passability_registry = registry


# ========== 注册 / 注销 ==========

## 注册一个单位 obstruction shape (圆); 返回分配的 tag。
##
## **典型 flags**: `RtsObstructionFlags.BLOCK_MOVEMENT` (单位间互避; 不进 NavcellGrid bit)。
##
## **R5 缓解**: tag 单调递增不复用; 调方应把 tag 存到 actor.obstruction_tag 字段, 死亡时调
##              remove_shape(tag) 再 erase actor。
func add_unit_shape(entity_id: String, pos: Vector2, clearance: float, flags: int, group: String) -> int:
	var s := RtsObstructionShapeUnit.new()
	s.entity_id = entity_id
	s.center = pos
	s.clearance = clearance
	s.flags = flags
	s.control_group = group
	s.tag = _next_tag
	_next_tag += 1
	_shapes[s.tag] = s
	_spatial_index.insert(s.tag, pos, clearance)
	_mark_navcell_dirty(pos, clearance)
	return s.tag


## 注册一个静态 obstruction shape (OBB); 返回分配的 tag。
##
## **典型 flags**: `RtsObstructionFlags.BLOCK_PATHFINDING | RtsObstructionFlags.BLOCK_FOUNDATION`。
##
## **OBB 包围圆**: enclose_radius = sqrt(w² + h²) / 2 — spatial_index 用此粗筛。
func add_static_shape(entity_id: String, pos: Vector2, rotation: float, w: float, h: float, flags: int, group: String, group2: String = "") -> int:
	var s := RtsObstructionShapeStatic.new()
	s.entity_id = entity_id
	s.center = pos
	s.rotation_rad = rotation
	s.width = w
	s.height = h
	s.flags = flags
	s.control_group = group
	s.control_group_2 = group2
	s.tag = _next_tag
	_next_tag += 1
	_shapes[s.tag] = s
	var enclose_radius: float = _enclose_radius(s)
	_spatial_index.insert(s.tag, pos, enclose_radius)
	_mark_navcell_dirty(pos, enclose_radius)
	return s.tag


## 移动 shape: 旧位置 + 新位置都 mark navcell dirty, spatial index update。
##
## tag 不存在视为 no-op (M2.5 unit death 链路 + safety net)。
func move_shape(tag: int, pos: Vector2, rotation: float = 0.0) -> void:
	if not _shapes.has(tag):
		return
	var s = _shapes[tag]
	var old_pos: Vector2 = s.center
	var radius: float = _enclose_radius(s)
	_mark_navcell_dirty(old_pos, radius)
	s.center = pos
	if s is RtsObstructionShapeStatic:
		s.rotation_rad = rotation
	_spatial_index.update(tag, old_pos, pos, radius)
	_mark_navcell_dirty(pos, radius)


## 切单位 MOVING flag (跟 base.flags 双写 unit.moving 字段)。
func set_unit_moving_flag(tag: int, moving: bool) -> void:
	if not _shapes.has(tag):
		return
	var s = _shapes[tag]
	if not (s is RtsObstructionShapeUnit):
		return
	if moving:
		s.flags = s.flags | RtsObstructionFlags.MOVING
		s.moving = true
	else:
		s.flags = s.flags & ~RtsObstructionFlags.MOVING
		s.moving = false


func set_unit_control_group(tag: int, group: String) -> void:
	if _shapes.has(tag):
		_shapes[tag].control_group = group


func set_static_control_group(tag: int, group: String, group2: String = "") -> void:
	if _shapes.has(tag):
		var s = _shapes[tag]
		s.control_group = group
		s.control_group_2 = group2


## 注销 shape: spatial_index remove + _shapes erase + mark navcell dirty (旧位置)。
##
## tag 不存在 no-op (幂等)。
func remove_shape(tag: int) -> void:
	if not _shapes.has(tag):
		return
	var s = _shapes[tag]
	var radius: float = _enclose_radius(s)
	_spatial_index.remove(tag, s.center, radius)
	_mark_navcell_dirty(s.center, radius)
	_shapes.erase(tag)


# ========== 查询 ==========

func get_shape(tag: int) -> RtsObstructionShape:
	return _shapes.get(tag, null)


## 范围查询: 返回所有中心在 (pos ± query_range) AABB 内 (经 spatial_index 粗筛) 的 shape。
##
## **Determinism**: spatial_index.query_circle 末已 sort by tag, 此函数返回的 Array 也按 tag 升序。
##
## **粗筛 vs 精确**: 此函数仅返回 spatial bucket 命中, **不**做 circle 精确相交 — 调方 (test_*_shape /
## activity 距离判定) 拿到 shape list 后自行精确判。
func get_obstructions_in_range(pos: Vector2, query_range: float) -> Array:
	var tags: Array[int] = _spatial_index.query_circle(pos, query_range)
	var result: Array = []
	for t in tags:
		result.append(_shapes[t])
	return result


## 单位想放在 (pos, clearance) 圆上, 是否撞到任何障碍 (经 filter 过滤后)。
##
## 返回 true = 撞 / false = 通过。
func test_unit_shape(filter: RtsObstructionTestFilter, pos: Vector2, clearance: float) -> bool:
	var sweep_radius: float = clearance + _passability_registry.max_clearance()
	var nearby: Array = get_obstructions_in_range(pos, sweep_radius)
	for s in nearby:
		if not filter.predicate(s):
			continue
		if _circles_overlap_for_unit(pos, clearance, s):
			return true
	return false


## 静态 OBB 想放在 (pos, rotation, w, h), 是否撞到任何障碍。
func test_static_shape(filter: RtsObstructionTestFilter, pos: Vector2, rotation: float, w: float, h: float) -> bool:
	var enclose_radius: float = sqrt(w * w + h * h) * 0.5
	var sweep_radius: float = enclose_radius + _passability_registry.max_clearance()
	var nearby: Array = get_obstructions_in_range(pos, sweep_radius)
	for s in nearby:
		if not filter.predicate(s):
			continue
		if _obb_overlaps_with(pos, rotation, w, h, s):
			return true
	return false


## entity_id 对应 shape 到 point 的最短距离;不存在返 INF。
func distance_to_point(entity_id: String, point: Vector2) -> float:
	var s: RtsObstructionShape = _find_shape_by_entity(entity_id)
	if s == null:
		return INF
	return _shape_to_point_distance(s, point)


## 两 entity 之间最短距离 (H5 决策 A: 简化版 center-to-center 减 enclose_radius); 任一不存在返 INF。
##
## **精度**: 误差 ≤ 单位半径; activity attack 距离判定接受;M6 vertex pathfinder 若需精确版另起 helper。
func distance_to_target(entity_id_a: String, entity_id_b: String) -> float:
	var sa: RtsObstructionShape = _find_shape_by_entity(entity_id_a)
	var sb: RtsObstructionShape = _find_shape_by_entity(entity_id_b)
	if sa == null or sb == null:
		return INF
	return _shape_to_shape_distance(sa, sb)


# ========== Rasterize 进 grid ==========

## 把所有 BLOCK_PATHFINDING shape 写到 grid 的 pass_class bit 上。
##
## **dirty_only=false**: 先全图清掉该 class 的 bit, 再 rewrite (full rebuild)。
## **dirty_only=true**:  保留旧 bit 不清, 直接 OR 新 bit (M2 阶段简化版增量; M3 引入真 EDT inflate)。
##
## **R5 P1-2 修订** (stop runner 第 8 条): rasterize **不**调 grid.clear_dirty();
##   dirty 由 RtsWorld.tick step 7 末端统一清除。spec §M2.3 给的伪代码末尾的 clear_dirty()
##   是错的 — 已移除。
##
## **Determinism**: _shapes Dictionary 迭代序非 deterministic; 内部先取 sorted tag list 再
##   遍历, 确保 rasterize 写入顺序固定。
func rasterize(grid: RtsNavcellGrid, pass_class: RtsPassabilityClassConfig, dirty_only: bool) -> void:
	var class_mask: int = 1 << pass_class.bit_index
	if not dirty_only:
		var h: int = grid.height()
		var w: int = grid.width()
		for j in range(h):
			for i in range(w):
				grid.and_data(i, j, class_mask)
	# 取排好序的 tag 列表, 避免依赖 _shapes Dictionary 迭代序 (data-structures §12.4)
	var tags: Array = _shapes.keys()
	tags.sort()
	for tag in tags:
		var s = _shapes[tag]
		if (s.flags & RtsObstructionFlags.BLOCK_PATHFINDING) == 0:
			continue
		_rasterize_one_shape(grid, s, class_mask)
	# **不** clear_dirty (R5 P1-2): RtsWorld.tick step 7 负责。


# ========== 调试 / 测试辅助 ==========

func size() -> int:
	return _shapes.size()


func next_tag() -> int:
	return _next_tag


# ========== 内部 helper ==========

## shape 包围圆半径 (Unit 直接 clearance, Static 是 OBB 对角线一半)。
static func _enclose_radius(s: RtsObstructionShape) -> float:
	if s is RtsObstructionShapeUnit:
		return (s as RtsObstructionShapeUnit).clearance
	var ss := s as RtsObstructionShapeStatic
	return sqrt(ss.width * ss.width + ss.height * ss.height) * 0.5


## 标记 navcell dirty 范围 (pos ± radius); 越界 cell 跳过。
func _mark_navcell_dirty(pos: Vector2, radius: float) -> void:
	var min_i: int = int(floorf((pos.x - radius) / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	var max_i: int = int(floorf((pos.x + radius) / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	var min_j: int = int(floorf((pos.y - radius) / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	var max_j: int = int(floorf((pos.y + radius) / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			if i >= 0 and i < _navcell_grid.width() and j >= 0 and j < _navcell_grid.height():
				_navcell_grid.mark_dirty(i, j)


## 单位圆 (pos_a, r_a) 与任意 shape (圆 / OBB) 是否相交。
func _circles_overlap_for_unit(pos_a: Vector2, r_a: float, shape_b) -> bool:
	if shape_b is RtsObstructionShapeUnit:
		var b_unit := shape_b as RtsObstructionShapeUnit
		var d2: float = pos_a.distance_squared_to(b_unit.center)
		var sum: float = r_a + b_unit.clearance
		return d2 < sum * sum
	return _circle_obb_overlap(pos_a, r_a, shape_b as RtsObstructionShapeStatic)


## 圆 (pos, r) 与 OBB 相交? 走"OBB local 坐标系投影 clamp"几何 (Real-Time Collision Detection §5.1.4)。
func _circle_obb_overlap(pos: Vector2, radius: float, obb: RtsObstructionShapeStatic) -> bool:
	var local: Vector2 = pos - obb.center
	var u: Vector2 = Vector2(cos(obb.rotation_rad), sin(obb.rotation_rad))
	var v: Vector2 = Vector2(-sin(obb.rotation_rad), cos(obb.rotation_rad))
	var lx: float = local.dot(u)
	var ly: float = local.dot(v)
	var hw: float = obb.width * 0.5
	var hh: float = obb.height * 0.5
	var dx: float = maxf(absf(lx) - hw, 0.0)
	var dy: float = maxf(absf(ly) - hh, 0.0)
	return (dx * dx + dy * dy) < radius * radius


## OBB (pos_a, rot_a, w_a, h_a) 与任意 shape (圆 / OBB) 是否相交。
func _obb_overlaps_with(pos_a: Vector2, rot_a: float, w_a: float, h_a: float, shape_b) -> bool:
	if shape_b is RtsObstructionShapeUnit:
		var b_unit := shape_b as RtsObstructionShapeUnit
		var our_obb := RtsObstructionShapeStatic.new()
		our_obb.center = pos_a
		our_obb.rotation_rad = rot_a
		our_obb.width = w_a
		our_obb.height = h_a
		return _circle_obb_overlap(b_unit.center, b_unit.clearance, our_obb)
	return _obb_obb_overlap_sat(pos_a, rot_a, w_a, h_a, shape_b as RtsObstructionShapeStatic)


## OBB-OBB SAT 完整实现 (R1 缓解; 0 A.D. helpers/Pathfinding.cpp:TestObstructionsAgainstSquare 同算法)。
##
## SAT (Separating Axis Theorem):2 个 OBB 在 4 条候选分离轴 (A 的 u/v + B 的 u/v) 上的投影若**任一**
## 不重叠则两 OBB 不相交; 全部重叠才相交。
##
## **完整 4 case 单元覆盖** (M2.6 smoke):
##   - 轴对齐 (rot=0 + rot=0)
##   - 旋转 45° vs 0° (跨 4 条轴)
##   - 边接触 (距离恰为 width 半和)
##   - 角接触 (旋转 OBB 角点接触另一 OBB 边)
func _obb_obb_overlap_sat(pos_a: Vector2, rot_a: float, w_a: float, h_a: float, obb_b: RtsObstructionShapeStatic) -> bool:
	var u_a: Vector2 = Vector2(cos(rot_a), sin(rot_a))
	var v_a: Vector2 = Vector2(-sin(rot_a), cos(rot_a))
	var u_b: Vector2 = Vector2(cos(obb_b.rotation_rad), sin(obb_b.rotation_rad))
	var v_b: Vector2 = Vector2(-sin(obb_b.rotation_rad), cos(obb_b.rotation_rad))
	var hw_a: float = w_a * 0.5
	var hh_a: float = h_a * 0.5
	var hw_b: float = obb_b.width * 0.5
	var hh_b: float = obb_b.height * 0.5
	var center_diff: Vector2 = obb_b.center - pos_a

	var axes: Array[Vector2] = [u_a, v_a, u_b, v_b]
	for axis in axes:
		# A 在 axis 上的投影半宽 = |u_a · axis| * hw_a + |v_a · axis| * hh_a
		var proj_a: float = absf(u_a.dot(axis)) * hw_a + absf(v_a.dot(axis)) * hh_a
		var proj_b: float = absf(u_b.dot(axis)) * hw_b + absf(v_b.dot(axis)) * hh_b
		var center_proj: float = absf(center_diff.dot(axis))
		if center_proj > proj_a + proj_b:
			# 找到分离轴 → 不相交
			return false
	# 4 条轴上都重叠 → 相交 (SAT 必要充分)
	return true


## 把单个 shape rasterize 进 grid (写入 class_mask bit)。
##
## - Unit shape (圆): 简化版 — 仅 center cell 写入 (M2 阶段单位通常不 BLOCK_PATHFINDING; 即使设了也只占
##   1 cell, M3 引入 clearance buffer 时会 inflate 到完整圆)
## - Static OBB: AABB 包围 → 逐 cell test "中心是否在 OBB 内" → 写入
func _rasterize_one_shape(grid: RtsNavcellGrid, s: RtsObstructionShape, class_mask: int) -> void:
	if s is RtsObstructionShapeUnit:
		var u_shape := s as RtsObstructionShapeUnit
		var ci: int = int(floorf(u_shape.center.x / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
		var cj: int = int(floorf(u_shape.center.y / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
		if ci >= 0 and ci < grid.width() and cj >= 0 and cj < grid.height():
			grid.or_data(ci, cj, class_mask)
		return
	var obb := s as RtsObstructionShapeStatic
	var corners: Array[Vector2] = obb.get_corners()
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for c in corners:
		min_x = minf(min_x, c.x)
		max_x = maxf(max_x, c.x)
		min_y = minf(min_y, c.y)
		max_y = maxf(max_y, c.y)
	var i0: int = int(floorf(min_x / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	var i1: int = int(floorf(max_x / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	var j0: int = int(floorf(min_y / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	var j1: int = int(floorf(max_y / float(RtsNavcellGrid.NAVCELL_SIZE_PX)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if i < 0 or i >= grid.width() or j < 0 or j >= grid.height():
				continue
			var center: Vector2 = grid.navcell_center_world(i, j)
			if _point_in_obb(center, obb):
				grid.or_data(i, j, class_mask)


## point 在 OBB 内? 走 OBB local 坐标系投影 clamp。
func _point_in_obb(p: Vector2, obb: RtsObstructionShapeStatic) -> bool:
	var local: Vector2 = p - obb.center
	var u: Vector2 = Vector2(cos(obb.rotation_rad), sin(obb.rotation_rad))
	var v: Vector2 = Vector2(-sin(obb.rotation_rad), cos(obb.rotation_rad))
	var lx: float = local.dot(u)
	var ly: float = local.dot(v)
	return absf(lx) <= obb.width * 0.5 and absf(ly) <= obb.height * 0.5


## 通过 entity_id 反查 shape (线性扫 _shapes; M2 阶段 entity 数 ≤ 200, O(N) 够用)。
##
## 若需 O(1) 反查可加 _by_entity Dictionary, M5+ vertex pathfinder 频繁调用时再优化。
func _find_shape_by_entity(eid: String) -> RtsObstructionShape:
	for tag in _shapes:
		var s: RtsObstructionShape = _shapes[tag] as RtsObstructionShape
		if s.entity_id == eid:
			return s
	return null


## shape 到 point 的最短距离 (Unit = center 距离 - r; OBB = local clamp 后欧氏距离)。
func _shape_to_point_distance(s: RtsObstructionShape, p: Vector2) -> float:
	if s is RtsObstructionShapeUnit:
		var u_shape := s as RtsObstructionShapeUnit
		return maxf(0.0, p.distance_to(u_shape.center) - u_shape.clearance)
	var obb := s as RtsObstructionShapeStatic
	var local: Vector2 = p - obb.center
	var u: Vector2 = Vector2(cos(obb.rotation_rad), sin(obb.rotation_rad))
	var v: Vector2 = Vector2(-sin(obb.rotation_rad), cos(obb.rotation_rad))
	var lx: float = clampf(local.dot(u), -obb.width * 0.5, obb.width * 0.5)
	var ly: float = clampf(local.dot(v), -obb.height * 0.5, obb.height * 0.5)
	var nearest: Vector2 = obb.center + u * lx + v * ly
	return p.distance_to(nearest)


## 两 shape 间最短距离 (H5 决策 A: 简化版; 误差 ≤ 单位半径)。
##
## center-to-center 减 两 enclose_radius;**精确版** (圆-圆 / 圆-OBB / OBB-OBB) 需要分类分支,
## M6 vertex pathfinder 真正需要精确时另起 helper。M2 阶段 activity attack 距离判定接受此简化。
func _shape_to_shape_distance(a: RtsObstructionShape, b: RtsObstructionShape) -> float:
	var ar: float = _enclose_radius(a)
	var br: float = _enclose_radius(b)
	return maxf(0.0, a.center.distance_to(b.center) - ar - br)
