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
## **M6c facade wire 范围**:加 `_vertex` 字段 + `compute_short_path_immediate` API,委托给
## `RtsVertexPathfinder.compute_short_path_immediate(req, obstr_mgr)`。**production callsite
## 暂不消费**(activity / nav_agent / move_units_command 仍走 LongPath)— M7 UnitMotion
## 整合双轨时才接 production,届时 baseline 漂(short path 字段从占位 -1 变实填,P1 接受)。
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


# ========== 初始化 ==========

func _init(
	p_grid: RtsNavcellGrid,
	p_hierarchical: RtsHierarchicalPathfinder,
	p_long: RtsLongPathfinder,
	p_vertex: RtsVertexPathfinder = null,
) -> void:
	Log.assert_crash(p_grid != null, "RtsPathfinderFacade", "_init: grid is null")
	Log.assert_crash(p_hierarchical != null, "RtsPathfinderFacade", "_init: hierarchical is null")
	Log.assert_crash(p_long != null, "RtsPathfinderFacade", "_init: long is null")
	# WHY: vertex 默认 null 兼容 M5 callsite (RtsAutoBattleProcedure 旧构造);M6c 起 procedure 应传 vertex
	# 实例,后续 M7 production callsite 调 compute_short_path_immediate 时强制非空。
	_grid = p_grid
	_hierarchical = p_hierarchical
	_long = p_long
	_vertex = p_vertex


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
	# Hierarchical 还没 recompute 过(procedure step 6.7 lazy 触发前)→ 跳过 canonicalize
	# 直接走 A*。常见于战斗第一 tick before procedure 跑过。
	if _hierarchical.is_recomputed():
		_hierarchical.make_goal_reachable_pathgoal(start_world, goal, pass_mask)
	return _long.compute_path_immediate(start_world, goal, pass_mask)


## 纯查询:goal 是否跟 start 同 GlobalRegion(整图可达)。**不 mutate goal**。
##
## start 在 impassable navcell → false(不做 fallback,跟 hierarchical.is_goal_reachable_point
## 同行为)。
func is_goal_reachable(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> bool:
	if not _hierarchical.is_recomputed():
		return false
	return _hierarchical.is_goal_reachable_point(start_world, goal.center, pass_mask)


## 显式 canonicalize:mutate goal 到 navcell 中心 POINT,返回 reachable bool。
##
## 跟 compute_path_immediate 区别:本 method 不跑 A*,callsite 拿到 canonicalized goal 后可
## 自己决定下一步(e.g. M6 vertex pathfinder direct goal)。
func make_goal_reachable(start_world: Vector2, goal: RtsPathGoal, pass_mask: int) -> bool:
	if not _hierarchical.is_recomputed():
		return false
	return _hierarchical.make_goal_reachable_pathgoal(start_world, goal, pass_mask)


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
	Log.assert_crash(_vertex != null, "RtsPathfinderFacade", "compute_short_path_immediate: vertex pathfinder not wired (_init 时 p_vertex 传 null);M7 整合双轨前 caller 不应调此 API")
	return _vertex.compute_short_path_immediate(req, obstr_mgr)


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
	return _long.compute_path_immediate(start_world, goal, pass_mask)
