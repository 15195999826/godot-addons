## RtsPathfinderFacade - 顶层寻路 facade (M5 引入)
##
## 0 A.D. `helpers/PathfinderFacade` 风格 — 把 hierarchical(可达性)+ LongPath(全图 A*)+
## (M6+ VertexPath 短路径)+ recompute / dirty 调度统一到一个 Refcounted 入口。callsite
## 不需要知道哪层做了什么,直接 `facade.compute_path_immediate(start, goal, mask)`。
##
## **M5 阶段功能**:
##   1. `compute_path_immediate(start, goal, mask)` = `make_goal_reachable_pathgoal` →
##      `RtsLongPathfinder.compute_path_immediate`(总是先 canonicalize goal 到 navcell 中心 POINT,
##       再 A*)
##   2. `is_goal_reachable(start, goal, mask)` 纯查询(不 mutate goal)
##   3. `make_goal_reachable(start, goal, mask)` 显式 canonicalize 入口
##
## **M5 阶段不做**:
##   - VertexPath 短路径(M6 加)
##   - check_movement / line-of-sight(M6 加)
##   - tick / update(grid, dirty)增量(M4c CANCEL,M5 阶段 procedure step 6.7 仍走 M4a lazy
##     recompute,facade tick 不持 hierarchical update 入口)
##
## **决策来源**:
##   - milestones/M5-long-pathfinder.md §M5.3 facade 雏形
##   - data-structures.md §7 PathfinderFacade
##   - M4-hierarchical.md §M4b.3 deferred (M5 解锁条件:canonicalize 切到"总是 navcell 中心")
class_name RtsPathfinderFacade
extends RefCounted


# ========== 字段 ==========

## NavcellGrid 引用(canonicalize / A* 都需要)。
var _grid: RtsNavcellGrid = null

## Hierarchical pathfinder(canonicalize + 可达性)。
var _hierarchical: RtsHierarchicalPathfinder = null

## LongPath A*(M5)。
var _long: RtsLongPathfinder = null


# ========== 初始化 ==========

func _init(
	p_grid: RtsNavcellGrid,
	p_hierarchical: RtsHierarchicalPathfinder,
	p_long: RtsLongPathfinder,
) -> void:
	Log.assert_crash(p_grid != null, "RtsPathfinderFacade", "_init: grid is null")
	Log.assert_crash(p_hierarchical != null, "RtsPathfinderFacade", "_init: hierarchical is null")
	Log.assert_crash(p_long != null, "RtsPathfinderFacade", "_init: long is null")
	_grid = p_grid
	_hierarchical = p_hierarchical
	_long = p_long


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
