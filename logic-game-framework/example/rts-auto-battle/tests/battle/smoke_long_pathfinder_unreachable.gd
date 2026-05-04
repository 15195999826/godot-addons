## RtsLongPathfinder unreachable + facade canonicalize integration smoke (M5 — AC4 + ✋2)
##
## 验证 M5 facade + LongPath + Hierarchical canonicalize 联调:
##
## **AC4.1 — facade.compute_path_immediate canonicalize 可达 → 走 navcell 中心 POINT goal**:
##   全可通 grid + start (10, 10) → goal (50, 50) → canonicalize 把 goal mutate 到 navcell 中心
##   POINT,LongPath A* 找到 path 到 navcell 中心(不是原任意小数 world 点)
##
## **AC4.2 — facade.compute_path_immediate canonicalize 不可达 → 走外缘 navcell**:
##   中间隔死 + start 在左半 + goal 在右半墙后 → canonicalize 把 goal mutate 到 start 同
##   GlobalRegion 离 goal 最近的 navcell(墙左侧外缘)→ unit 走过去站住,不死循环
##
## **AC4.3 — facade.compute_path_direct 不过 canonicalize + 终点 impassable → direct-path
## fallback**:goal 落 impassable navcell → LongPath A* 找不到 path → 返回单 waypoint =
## 原 goal.center,callsite 直接朝目标走过去(harvest/attack/drop 用此 fallback 让 unit 走到
## actor 中心 in-range)
##
## **AC4.4 — facade.is_goal_reachable 纯查询(不 mutate goal)**:
##   reachable 返回 true,unreachable 返回 false;goal 字段不变(对比前后 goal.center 一致)
##
## **✋2 体验点 headless mock**:玩家点墙后不可达点 → facade canonicalize → unit 走最近
##   reachable navcell,不死循环(用 path 长度 + 终点 navcell 验证)
##
## 不依赖 procedure / world / actor — 直接 NavcellGrid + Hierarchical + Long + Facade smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_facade_canonicalize_reachable_to_navcell_center()
	_test_facade_canonicalize_unreachable_to_outer_navcell()
	_test_facade_direct_impassable_returns_direct_path()
	_test_facade_is_goal_reachable_pure_query()
	_test_user_experience_2_player_clicks_unreachable_point()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - long_pathfinder_unreachable — AC4 + ✋2 all OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_registry() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	return registry


func _make_facade(grid: RtsNavcellGrid, registry: RtsPassabilityClassRegistry) -> Dictionary:
	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(grid, registry.get_classes())
	var lp := RtsLongPathfinder.new(grid)
	var facade := RtsPathfinderFacade.new(grid, hp, lp)
	return {"facade": facade, "hp": hp, "lp": lp}


func _block_rect(grid: RtsNavcellGrid, i0: int, j0: int, i1: int, j1: int, mask: int) -> void:
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			grid.or_data(i, j, mask)


# ========== Test cases ==========

func _test_facade_canonicalize_reachable_to_navcell_center() -> void:
	# 96² grid (1 chunk) 全可通,start (10, 10) navcell, goal world (50.7, 50.3) (任意 offset)
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := _make_registry()
	var mask: int = registry.get_mask("default")
	var bundle := _make_facade(grid, registry)
	var facade: RtsPathfinderFacade = bundle["facade"]

	var start_world := grid.navcell_center_world(10, 10)
	# goal 任意小数 world 坐标,canonicalize 应 mutate 到 nearest navcell 中心
	var goal_arbitrary := Vector2(50.7 * 32 + 7.3, 50.3 * 32 + 3.1)
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, goal_arbitrary)
	var path: RtsWaypointPath = facade.compute_path_immediate(start_world, goal, mask)

	# 验:goal 被 mutate 到 navcell 中心(canonicalize 总是 mutate 即使 reachable)
	var expected_navcell: Vector2i = grid.nearest_navcell(goal_arbitrary)
	var expected_center: Vector2 = grid.navcell_center_world(expected_navcell.x, expected_navcell.y)
	if goal.center.distance_to(expected_center) > 0.01:
		_failures.append("canon-reachable: goal.center should be mutated to navcell center, got %s expected %s" % [str(goal.center), str(expected_center)])

	# 验:path 非空,goal_world 在 path[0]
	if path.is_empty():
		_failures.append("canon-reachable: path empty (should reach navcell center)")
		return
	if path.waypoints[0] != expected_center:
		_failures.append("canon-reachable: path[0] expected goal navcell center %s, got %s" % [str(expected_center), str(path.waypoints[0])])


func _test_facade_canonicalize_unreachable_to_outer_navcell() -> void:
	# 96² grid + 中间整列 i=48 墙(2 列 inflate)隔死;start 左半 (20, 50), goal 右半 (75, 50)
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := _make_registry()
	var mask: int = registry.get_mask("default")
	for j in range(96):
		grid.or_data(48, j, mask)
		grid.or_data(49, j, mask)
	var bundle := _make_facade(grid, registry)
	var facade: RtsPathfinderFacade = bundle["facade"]
	var hp: RtsHierarchicalPathfinder = bundle["hp"]

	var start_world := grid.navcell_center_world(20, 50)
	var goal_world := grid.navcell_center_world(75, 50)
	var start_g: int = hp.get_global_region(20, 50, mask)
	var goal_g: int = hp.get_global_region(75, 50, mask)

	if start_g == goal_g or start_g == 0 or goal_g == 0:
		_failures.append("canon-unreachable: prerequisite — start_g (%d) != goal_g (%d) both non-zero failed" % [start_g, goal_g])
		return

	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, goal_world)
	var path: RtsWaypointPath = facade.compute_path_immediate(start_world, goal, mask)

	# 验:goal mutate 到 start 同 GlobalRegion 内的 navcell 中心(墙左侧)
	var canon_navcell: Vector2i = grid.nearest_navcell(goal.center)
	var canon_g: int = hp.get_global_region(canon_navcell.x, canon_navcell.y, mask)
	if canon_g != start_g:
		_failures.append("canon-unreachable: canon (%s, g=%d) should ∈ start_g (%d)" % [str(canon_navcell), canon_g, start_g])
	# 墙左侧 i < 48
	if canon_navcell.x >= 48:
		_failures.append("canon-unreachable: canon should be left of wall (i<48), got i=%d" % canon_navcell.x)
	# Path 非空 — A* 能从 start 走到 canon
	if path.is_empty():
		_failures.append("canon-unreachable: path empty (should reach canon navcell on left side)")


func _test_facade_direct_impassable_returns_direct_path() -> void:
	# 96² grid + (40..45, 40..45) 5×5 obstacle 块;start (20, 20), goal 落 obstacle 内 (42, 42)
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := _make_registry()
	var mask: int = registry.get_mask("default")
	_block_rect(grid, 40, 40, 45, 45, mask)
	var bundle := _make_facade(grid, registry)
	var facade: RtsPathfinderFacade = bundle["facade"]

	var start_world := grid.navcell_center_world(20, 20)
	var goal_world := grid.navcell_center_world(42, 42)   # 落 impassable obstacle 内
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, goal_world)
	# compute_path_direct 不过 canonicalize → A* 终点 impassable → direct-path fallback
	var path: RtsWaypointPath = facade.compute_path_direct(start_world, goal, mask)

	# Direct-path fallback:返回单 waypoint = 原 goal.center(不 mutate goal)
	if path.size() != 1:
		_failures.append("direct-impassable: expected single waypoint (direct-path fallback), got size=%d" % path.size())
		return
	if path.waypoints[0] != goal_world:
		_failures.append("direct-impassable: waypoint should be original goal_world %s, got %s" % [str(goal_world), str(path.waypoints[0])])
	# goal 不 mutate(compute_path_direct 不过 canonicalize)
	if goal.center != goal_world:
		_failures.append("direct-impassable: goal.center should NOT be mutated by compute_path_direct, got %s" % str(goal.center))


func _test_facade_is_goal_reachable_pure_query() -> void:
	var grid := RtsNavcellGrid.new(96, 96)
	grid.set_origin_world(Vector2.ZERO)
	var registry := _make_registry()
	var mask: int = registry.get_mask("default")
	for j in range(96):
		grid.or_data(48, j, mask)
		grid.or_data(49, j, mask)
	var bundle := _make_facade(grid, registry)
	var facade: RtsPathfinderFacade = bundle["facade"]

	# Reachable: 同侧
	var start_world := grid.navcell_center_world(20, 50)
	var goal_same_side := RtsPathGoal.new(RtsPathGoal.Type.POINT, grid.navcell_center_world(30, 70))
	var orig_center := goal_same_side.center
	if not facade.is_goal_reachable(start_world, goal_same_side, mask):
		_failures.append("pure-query: same side should be reachable")
	if goal_same_side.center != orig_center:
		_failures.append("pure-query: is_goal_reachable should NOT mutate goal, got %s vs orig %s" % [str(goal_same_side.center), str(orig_center)])

	# Unreachable: 墙后
	var goal_other_side := RtsPathGoal.new(RtsPathGoal.Type.POINT, grid.navcell_center_world(75, 50))
	var orig_center2 := goal_other_side.center
	if facade.is_goal_reachable(start_world, goal_other_side, mask):
		_failures.append("pure-query: other side of wall should be unreachable")
	if goal_other_side.center != orig_center2:
		_failures.append("pure-query: unreachable case should also NOT mutate goal")


func _test_user_experience_2_player_clicks_unreachable_point() -> void:
	# **✋2 体验点 mock**:玩家点墙后不可达点 → facade canonicalize → unit 走最近 reachable
	# navcell,不死循环。
	# 192² grid(2x2 chunks)中间整列墙(i=96, 97) + start 左 (50, 50) + 玩家 click 右半 (150, 50)
	var grid := RtsNavcellGrid.new(192, 192)
	grid.set_origin_world(Vector2.ZERO)
	var registry := _make_registry()
	var mask: int = registry.get_mask("default")
	for j in range(192):
		grid.or_data(96, j, mask)
		grid.or_data(97, j, mask)
	var bundle := _make_facade(grid, registry)
	var facade: RtsPathfinderFacade = bundle["facade"]
	var hp: RtsHierarchicalPathfinder = bundle["hp"]

	var unit_world := grid.navcell_center_world(50, 50)
	var click_world := grid.navcell_center_world(150, 50)   # 玩家点不可达点

	# 模拟玩家 click move command:facade.compute_path_immediate
	var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, click_world)
	var path: RtsWaypointPath = facade.compute_path_immediate(unit_world, goal, mask)

	# 验:path 非空 — unit 不死循环
	if path.is_empty():
		_failures.append("✋2: path empty for unreachable click (should canonicalize to nearest reachable)")
		return
	# 验:path 终点(waypoints[0])在 start 同 GlobalRegion 内
	var goal_navcell: Vector2i = grid.nearest_navcell(goal.center)
	var canon_g: int = hp.get_global_region(goal_navcell.x, goal_navcell.y, mask)
	var start_g: int = hp.get_global_region(50, 50, mask)
	if canon_g != start_g or canon_g == 0:
		_failures.append("✋2: canon should ∈ start_g, got canon_g=%d start_g=%d" % [canon_g, start_g])
	# 验:path back() (next step) 是 start 的邻居 navcell 之一
	var next_step: Vector2 = path.back()
	var dx := absf(next_step.x - unit_world.x)
	var dy := absf(next_step.y - unit_world.y)
	if dx > 33 or dy > 33:   # 1 navcell distance allowance
		_failures.append("✋2: next step should be 8-neighbor of unit, got dx=%f dy=%f" % [dx, dy])
	# 验:goal mutate 到墙左侧(i < 96) — 不能跳墙
	if goal_navcell.x >= 96:
		_failures.append("✋2: canon should be left of wall (i<96), got i=%d" % goal_navcell.x)
