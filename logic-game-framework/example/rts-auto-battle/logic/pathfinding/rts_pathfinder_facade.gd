## RtsPathfinderFacade - 顶层寻路 facade (M5 引入,M6c 加 short path API)
##
## 0 A.D. `helpers/PathfinderFacade` 风格 — 把 hierarchical(可达性)+ LongPath(全图 A*)+
## VertexPath(短路径)+ recompute / dirty 调度统一到一个 Refcounted 入口。callsite
## 不需要知道哪层做了什么,直接调统一 API。
##
## **API 列表**:
##   1. `compute_path_immediate(start, goal, mask)` — LongPath A* + canonicalize(M5)
##   2. `compute_path_direct(start, goal, mask)` — LongPath A* 不过 canonicalize(M5)
##   3. `is_goal_reachable(start, goal, mask)` — 纯查询(M5)
##   4. `make_goal_reachable(start, goal, mask)` — 显式 canonicalize(M5)
##   5. `compute_short_path_immediate(req, obstr_mgr)` — VertexPath visibility graph A*(M6c)
##
## **P7 sim-nav-map migration**: public API remains RTS-shaped for production call sites,
## but implementation delegates to `addons/sim-nav-map` core. Old RTS pathfinder classes are
## still accepted by the constructor for compatibility and low-level fixture smokes.
##
## **决策来源**:
##   - milestones/M5-long-pathfinder.md §M5.3 facade 雏形
##   - milestones/M6-vertex-pathfinder.md §M6c.4 (短路径 facade wire 仅 API,production 不接)
##   - data-structures.md §7 PathfinderFacade
class_name RtsPathfinderFacade
extends RefCounted


# ========== 字段 ==========

## NavcellGrid 引用(canonicalize / A* 都需要)。
var _grid: RtsNavcellGrid = null

## Hierarchical pathfinder(canonicalize + 可达性)。
var _hierarchical: RtsHierarchicalPathfinder = null

## LongPath A*(M5)。
var _long: RtsLongPathfinder = null

## VertexPath visibility graph A*(M6c 引入;facade wire 仅 API,production callsite 暂不消费)。
var _vertex: RtsVertexPathfinder = null

## Production reachability gate. Procedure flips this after rasterize step 6.6, preserving the
## old "canonicalize only after derived path grid is ready" timing without constructing the old
## RTS hierarchical pathfinder in production.
var _reachability_ready: bool = false


# ========== 初始化 ==========

func _init(
	p_grid: RtsNavcellGrid,
	p_hierarchical: RtsHierarchicalPathfinder = null,
	p_long: RtsLongPathfinder = null,
	p_vertex: RtsVertexPathfinder = null,
) -> void:
	Log.assert_crash(p_grid != null, "RtsPathfinderFacade", "_init: grid is null")
	_grid = p_grid
	_hierarchical = p_hierarchical
	_long = p_long
	_vertex = p_vertex
	_reachability_ready = p_hierarchical != null and p_hierarchical.is_recomputed()


# ========== 公开 API ==========

## 同步寻路:canonicalize goal → A* → RtsWaypointPath。
##
## **流程**:
##   1. `_hierarchical.make_goal_reachable_pathgoal(start, goal, mask)` mutate goal 到
##      navcell 中心 POINT(reachable: 原 goal 所在 navcell;unreachable: 同 start GlobalRegion
##      离原 goal 最近 navcell);返回 reachable bool 仅作 caller 信息(不阻断 A*)
##   2. `_long.compute_path_immediate(start, goal, mask)` 朴素 A* on NavcellGrid → WaypointPath
##
## **goal in-place mutate** — caller 传入的 RtsPathGoal 实例会被改 type/center/hw/hh/u/v;
## 重复调用同一 goal 实例需要 caller 自己 reset。
##
## **空 path** — make_goal_reachable 返 false 兜底(start 找不到 fallback 等)或 LongPath
## A* 找不到时返回 RtsWaypointPath.new() 空 path,caller 用 `path.is_empty()` 判定。
func compute_path_immediate(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> RtsWaypointPath:
	var sim_map := _build_sim_nav_map_from_grid()
	var sim_goal := _to_sim_goal(goal)
	var sim_long := SimNavLongPathfinder.new(sim_map)
	var sim_hierarchical := SimNavHierarchicalPathfinder.new()
	if _reachability_ready:
		sim_hierarchical.recompute(sim_map, [pass_mask])
		var sim_facade := SimNavPathfinderFacade.new(sim_map, sim_hierarchical, sim_long)
		var sim_path := sim_facade.compute_path_immediate(start_world, sim_goal, pass_mask)
		_copy_sim_goal_to_rts(sim_goal, goal)
		return _to_rts_waypoint_path(sim_path)
	return _to_rts_waypoint_path(sim_long.compute_path_immediate(start_world, sim_goal, pass_mask))


## 纯查询:goal 是否跟 start 同 GlobalRegion(整图可达)。**不 mutate goal**。
##
## start 在 impassable navcell → false(不做 fallback,跟 hierarchical.is_goal_reachable_point
## 同行为)。
func is_goal_reachable(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> bool:
	if not _reachability_ready:
		return false
	var sim_map := _build_sim_nav_map_from_grid()
	var sim_hierarchical := SimNavHierarchicalPathfinder.new()
	sim_hierarchical.recompute(sim_map, [pass_mask])
	var start_cell := sim_map.world_to_navcell(start_world)
	var goal_cell := sim_map.world_to_navcell(goal.center)
	return sim_hierarchical.is_navcell_reachable(start_cell, goal_cell, pass_mask)


## 显式 canonicalize:mutate goal 到 navcell 中心 POINT,返回 reachable bool。
##
## 跟 compute_path_immediate 区别:本 method 不跑 A*,callsite 拿到 canonicalized goal 后可
## 自己决定下一步(e.g. M6 vertex pathfinder direct goal)。
func make_goal_reachable(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> bool:
	if not _reachability_ready:
		return false
	var sim_map := _build_sim_nav_map_from_grid()
	var sim_hierarchical := SimNavHierarchicalPathfinder.new()
	sim_hierarchical.recompute(sim_map, [pass_mask])
	var start_cell := sim_map.world_to_navcell(start_world)
	var goal_cell := sim_map.world_to_navcell(goal.center)
	var reachable: bool = sim_hierarchical.is_navcell_reachable(start_cell, goal_cell, pass_mask)
	var reachable_cell := sim_hierarchical.make_goal_reachable_navcell(start_cell, goal_cell, pass_mask)
	goal.type = RtsPathGoal.Type.POINT
	goal.center = sim_map.navcell_center_world(reachable_cell)
	goal.hw = 0.0
	goal.hh = 0.0
	goal.u = Vector2(1.0, 0.0)
	goal.v = Vector2(0.0, 1.0)
	goal.maxdist = 0.0
	return reachable


## VertexPath visibility graph A*(M6c facade wire)— 任意角度短路径,贴 obstruction 边。
##
## **跟 compute_path_immediate 区别**:
##   - compute_path_immediate = LongPath 全图 A* on navcell,8 邻居,粒度 32 px,阶梯形路径
##   - compute_short_path_immediate = Vertex visibility graph A*,任意角度直线段,贴 OBB / unit
##     边的"自然绕角"路径
##
## **req: RtsShortPathRequest** 字段:start / goal / clearance / range_px / pass_mask /
## avoid_moving_units / control_group。
##
## **空 path 语义**:start ≈ virtual_goal → 单 waypoint = virtual_goal;A* + best-so-far 都没到
## goal → 空 path,caller 用 `path.is_empty()` 判定 stuck。
##
## **production callsite 暂不消费**(M6c 范围)— M7 UnitMotion 整合双轨时接;现在调 = 发
## production read 链路兼容性 (assert_crash 防 null _vertex)。
func compute_short_path_immediate(req: RtsShortPathRequest, obstr_mgr: RtsObstructionManager) -> RtsWaypointPath:
	if req == null or req.goal == null or obstr_mgr == null:
		return RtsWaypointPath.new()
	var sim_map := _build_sim_nav_map_from_grid()
	_add_obstructions_to_sim_map(sim_map, obstr_mgr, req.start, req.range_px + req.clearance)
	var sim_request := SimNavShortPathRequest.new()
	sim_request.start = req.start
	sim_request.goal = _to_sim_goal(req.goal)
	sim_request.clearance = req.clearance
	sim_request.range_px = req.range_px
	sim_request.pass_mask = req.pass_mask
	sim_request.avoid_moving_units = req.avoid_moving_units
	sim_request.control_group = req.control_group
	return _to_rts_waypoint_path(SimNavVertexPathfinder.new(sim_map).compute_short_path_immediate(sim_request))


## 直接 A* **不过 canonicalize** — 给 AI attack-move / harvest 等"target 是 actor 中心,
## 可能落在 footprint 内"的 callsite 用。
##
## **背景** (M4b.3 wire 失败 lesson):spec §M4b.3 假设 wire 入口 = "玩家右键点目标" 的 click
## 坐标,canonicalize 到外缘 navcell 让 unit 不死循环。但 AI attack-move target = enemy actor
## 中心 — 可能落在 building footprint 内 → canonicalize 拽到 ct 旁外缘 navcell → unit 走到
## 那站住但 ct 在 attack range 外 → ai_vs_player smoke unit-to-ct attacks 7→0。
##
## **M5 解法**:玩家 click 走 `compute_path_immediate`(过 canonicalize),AI attack-move
## 走 `compute_path_direct`(不过 canonicalize,直接传 enemy 中心)。
##
## **空 path** — A* 找不到时返回空 path,callsite 用 `path.is_empty()` 判定。
func compute_path_direct(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> RtsWaypointPath:
	var sim_map := _build_sim_nav_map_from_grid()
	var sim_path := SimNavLongPathfinder.new(sim_map).compute_path_immediate(start_world, _to_sim_goal(goal), pass_mask)
	var result := _to_rts_waypoint_path(sim_path)
	if result.is_empty():
		result.push_back(goal.center)
	return result


func mark_reachability_ready() -> void:
	_reachability_ready = true


func is_reachability_ready() -> bool:
	return _reachability_ready


func _build_sim_nav_map_from_grid() -> SimNavMap:
	var sim_map := SimNavMap.new(
		_grid.width(),
		_grid.height(),
		float(RtsNavcellGrid.NAVCELL_SIZE_PX),
		_grid.origin_world(),
		1
	)
	for j in range(_grid.height()):
		for i in range(_grid.width()):
			sim_map.set_navcell_data(Vector2i(i, j), _grid.get_data(i, j))
	return sim_map


func _add_obstructions_to_sim_map(sim_map: SimNavMap, obstr_mgr: RtsObstructionManager, pos: Vector2, query_range: float) -> void:
	var shapes: Array = obstr_mgr.get_obstructions_in_range(pos, query_range)
	for shape in shapes:
		if shape is RtsObstructionShapeStatic:
			sim_map.add_static_obstruction(_to_sim_static_shape(shape as RtsObstructionShapeStatic))
		elif shape is RtsObstructionShapeUnit:
			sim_map.add_dynamic_obstruction(_to_sim_unit_shape(shape as RtsObstructionShapeUnit))


func _to_sim_static_shape(shape: RtsObstructionShapeStatic) -> SimNavObstructionShapeStatic:
	var sim_shape := SimNavObstructionShapeStatic.new()
	sim_shape.type = shape.type
	sim_shape.entity_id = shape.entity_id
	sim_shape.center = shape.center
	sim_shape.flags = shape.flags
	sim_shape.control_group = shape.control_group
	sim_shape.control_group_2 = shape.control_group_2
	sim_shape.width = shape.width
	sim_shape.height = shape.height
	sim_shape.rotation_rad = shape.rotation_rad
	return sim_shape


func _to_sim_unit_shape(shape: RtsObstructionShapeUnit) -> SimNavObstructionShapeUnit:
	var sim_shape := SimNavObstructionShapeUnit.new()
	sim_shape.type = shape.type
	sim_shape.entity_id = shape.entity_id
	sim_shape.center = shape.center
	sim_shape.flags = shape.flags
	sim_shape.control_group = shape.control_group
	sim_shape.control_group_2 = shape.control_group_2
	sim_shape.clearance = shape.clearance
	sim_shape.moving = shape.moving
	return sim_shape


func _to_sim_goal(goal: RtsPathGoal) -> SimNavPathGoal:
	var sim_goal := SimNavPathGoal.new(goal.type, goal.center)
	sim_goal.hw = goal.hw
	sim_goal.hh = goal.hh
	sim_goal.u = goal.u
	sim_goal.v = goal.v
	sim_goal.maxdist = goal.maxdist
	return sim_goal


func _copy_sim_goal_to_rts(sim_goal: SimNavPathGoal, goal: RtsPathGoal) -> void:
	goal.type = sim_goal.type
	goal.center = sim_goal.center
	goal.hw = sim_goal.hw
	goal.hh = sim_goal.hh
	goal.u = sim_goal.u
	goal.v = sim_goal.v
	goal.maxdist = sim_goal.maxdist


func _to_rts_waypoint_path(sim_path: SimNavWaypointPath) -> RtsWaypointPath:
	var path := RtsWaypointPath.new()
	if sim_path == null:
		return path
	for waypoint in sim_path.waypoints:
		path.push_back(waypoint)
	return path
