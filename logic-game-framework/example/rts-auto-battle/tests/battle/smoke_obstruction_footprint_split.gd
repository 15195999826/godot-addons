## RTS Obstruction / Footprint shape 拆分 acceptance smoke (M0.7 — AC5 + AC8)
##
## 验证 5 项核心断言 (M0.md §M0.7 step 1):
##   1. position_2d 不变 (sprite 锚点不动, F4 决策 A)
##   2. obstruction_shape.center == position_2d + 自定义 offset (factory 默认 ZERO, 此 smoke 故意 mutate)
##   3. get_footprint_cells 用 obstruction.center 当中心 (cells 围绕 obstruction.center, 不是 position_2d)
##   4. footprint_shape.contains(position_2d, position_2d) == true (玩家点 sprite 中心能选中)
##   5. AC8: Set A (ghost preview cells via compute_footprint_cells_from_shape) ==
##           Set B (actor.get_footprint_cells = placed cells) 且
##           (B ∩ Set C unit 寻路走过 cells) == ∅
##
## 设计:
##   - 干净 320×320 grid (10×10 cells, 无 RtsBattleMap 内置 obstacle)
##   - 在 (160, 160) 放一个 barracks, footprint=(2,2) → cell_size=32, 占 4 cells
##   - 故意 mutate obstruction_shape.center = position_2d + (32, 32) = (192, 192)
##     → 旧算法 cells 围绕 cell(5,5), 新算法 cells 围绕 cell(6,6) — 不同 → 拆分有效
##   - spawn 单位 (60, 192) → (260, 192), A* 必绕过 obstruction cells
##   - 收集 unit 每 tick 所在 cell, 验证不跟 obstruction cells 重叠
##
## 与既有 smoke 的差异: 不依赖 RtsBattleMap (无内置 obstacle), 不走 RtsAutoBattleProcedure
## (smoke 直接构造 grid + actor + agent, 隔离寻路 + footprint 算法; 不验证战斗胜负).
extends Node


const TICK_INTERVAL_MS: float = 50.0
const TICK_DT_SEC: float = TICK_INTERVAL_MS / 1000.0
const MAX_SECONDS: float = 12.0
const ConfigCls := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")


var _world: RtsWorldGameplayInstance = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null


func _ready() -> void:
	GameWorld.init()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(320.0, 320.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# ========== Phase 1 — 创建 barracks + mutate 非默认 offset ==========
	var barracks := RtsBuildings.create_barracks()
	barracks.set_team_id(0)
	_world.add_actor(barracks)
	barracks.position_2d = Vector2(160.0, 160.0)
	# 模拟非默认 obstruction_offset = (32, 32) — 直接 mutate center, 等价于 sync 时 stats.offset=(32,32)
	# (smoke 不改全局 config, 走 mutate 隔离测试拆分; 生产路径靠 stats.obstruction_offset + sync 完成)
	barracks.obstruction_shape.center = barracks.position_2d + Vector2(32.0, 32.0)
	barracks.obstruction_shape.entity_id = barracks.get_id()
	barracks.obstruction_shape.control_group = str(barracks.team_id)

	# ========== Assertion 1 — position_2d 不变 (sprite 锚点 F4-A) ==========
	if barracks.position_2d != Vector2(160.0, 160.0):
		_fail("position_2d 被 mutate obstruction 改了: 期望 (160, 160), 实际 %s" % barracks.position_2d)
		return

	# ========== Assertion 2 — obstruction.center == position_2d + offset ==========
	var expected_center := Vector2(192.0, 192.0)
	if barracks.obstruction_shape.center != expected_center:
		_fail("obstruction.center 错: 期望 %s, 实际 %s" % [expected_center, barracks.obstruction_shape.center])
		return

	# ========== 计算 Set A (ghost preview) + Set B (actor.get_footprint_cells) ==========
	var set_a: Array = RtsBuildingPlacement.compute_footprint_cells_from_shape(
		barracks.obstruction_shape, _grid)
	var set_b: Array = barracks.get_footprint_cells(_grid)

	# ========== Assertion 3 — get_footprint_cells 中心在 obstruction.center 而非 position_2d ==========
	# obstruction.center=(192,192) → cell(6,6); position_2d=(160,160) → cell(5,5)
	# 偶数 footprint=(2,2) 左上偏置: 围绕 cell(6,6) 应得 [(5,5),(6,5),(5,6),(6,6)]
	# 围绕 cell(5,5) 应得 [(4,4),(5,4),(4,5),(5,5)]
	# 故 set_b 必含 cell(6,6) (新算法), 且必不含 cell(4,4) (旧算法独有)
	var center_cell_obstr: HexCoord = _grid.world_to_coord(expected_center)
	var center_cell_pos2d: HexCoord = _grid.world_to_coord(barracks.position_2d)
	if center_cell_obstr.q == center_cell_pos2d.q and center_cell_obstr.r == center_cell_pos2d.r:
		_fail("test 失效: offset 太小, obstruction center 跟 position_2d 落同 cell (q=%d r=%d)" % [
			center_cell_obstr.q, center_cell_obstr.r,
		])
		return
	if not _cells_contain(set_b, center_cell_obstr):
		_fail("set_b 不含 obstruction.center cell (q=%d r=%d), 新算法未生效" % [
			center_cell_obstr.q, center_cell_obstr.r,
		])
		return
	# 旧算法独占 cell (position_2d 中心 (5,5) 偶数偏左上 → (4,4)); 该 cell 不应在 set_b
	var old_only_cell := HexCoord.new(center_cell_pos2d.q - 1, center_cell_pos2d.r - 1)
	if _cells_contain(set_b, old_only_cell):
		_fail("set_b 错含旧算法独占 cell (q=%d r=%d), 拆分未生效" % [old_only_cell.q, old_only_cell.r])
		return

	# ========== AC8 part 1 — Set A == Set B ==========
	if not _cells_equal(set_a, set_b):
		_fail("set_a (ghost preview) != set_b (placed): %s vs %s" % [
			_cells_to_str(set_a), _cells_to_str(set_b),
		])
		return

	# ========== Assertion 4 — footprint.contains(原位置, 原位置) ==========
	# footprint_shape.contains(world_pos, owner_pos): owner_pos == position_2d, world_pos = 玩家点击点;
	# 默认 center_offset=ZERO → local = (0, 0), CIRCLE/SQUARE 都 contains 原点 = true
	if not barracks.footprint_shape.contains(barracks.position_2d, barracks.position_2d):
		_fail("footprint.contains(原位置, 原位置) == false (玩家无法点中 sprite 中心)")
		return

	# ========== Phase 2 — 实际 place_building + spawn unit 验证 (B ∩ C) == ∅ ==========
	_grid.place_building(barracks.get_id(), set_b)

	var unit := RtsUnitActor.new(ConfigCls.UnitClass.MELEE)
	unit.set_team_id(0)
	unit.set_id("test_unit_pathing")
	# 起点跟终点同 y=192 (与 obstruction.center.y 同行), 直线必撞 obstruction cells
	unit.position_2d = Vector2(60.0, 192.0)

	var agent := RtsNavAgent.new()
	_host.add_child(agent)
	agent.bind_actor(unit, _grid)
	agent.set_target(Vector2(280.0, 192.0))

	if agent._path.is_empty():
		_fail("unit pathfinding 未找到 path (barracks 应阻挡直线却没绕路)")
		return

	# 收集 Set C: unit 走过的 cells (含起点 / 终点; key by HexCoord.to_key 与主仓 grid 反向索引一致)
	var set_c: Dictionary = {}
	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		var coord: HexCoord = _grid.world_to_coord(unit.position_2d)
		set_c[coord.to_key()] = coord
		agent.tick(TICK_DT_SEC)
		if agent.is_arrived():
			coord = _grid.world_to_coord(unit.position_2d)
			set_c[coord.to_key()] = coord
			break

	if not agent.is_arrived():
		_fail("unit 未抵达终点: 走 %d ticks, dist_remain=%.2f" % [
			max_ticks, unit.position_2d.distance_to(Vector2(280.0, 192.0)),
		])
		return

	# AC8 part 2: (B ∩ C) == ∅
	var b_keys: Dictionary = {}
	for c in set_b:
		b_keys[(c as HexCoord).to_key()] = true
	var intersection: Array = []
	for k in set_c.keys():
		if b_keys.has(k):
			intersection.append(k)
	if not intersection.is_empty():
		_fail("(B ∩ C) 非空: unit 路过 obstruction cells %s — A* 未正确绕开" % str(intersection))
		return

	# ========== 全过 ==========
	print("obstruction_footprint_split smoke: position_2d=(160,160) obstruction.center=(192,192)")
	print("  set_b cells (placed): %s" % _cells_to_str(set_b))
	print("  set_c cells (unit path, %d unique): %s" % [set_c.size(), _cells_to_str(set_c.values())])
	print("  ghost==placed: yes; (placed ∩ unit_path)==∅")

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - obstruction/footprint shape split, ghost==placed, unit avoids placed cells")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)


func _cells_contain(cells: Array, target: HexCoord) -> bool:
	for c in cells:
		if (c as HexCoord).equals(target):
			return true
	return false


func _cells_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var a_keys: Dictionary = {}
	for c in a:
		a_keys[(c as HexCoord).to_key()] = true
	for c in b:
		if not a_keys.has((c as HexCoord).to_key()):
			return false
	return true


func _cells_to_str(cells: Array) -> String:
	var parts: Array = []
	for c in cells:
		var coord := c as HexCoord
		parts.append("(%d,%d)" % [coord.q, coord.r])
	return "[" + ", ".join(parts) + "]"
