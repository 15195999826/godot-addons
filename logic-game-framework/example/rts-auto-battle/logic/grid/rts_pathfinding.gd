## RtsPathfinding - RTS 寻路工具(包 ultra-grid-map plugin 的 GridPathfinding.astar)
##
## 决策来源:
##   - D3-B (2D grid + A*)
##   - D3-D / D3-F (layer-aware passable callback, 飞行单位 layer = AIR 接口预留)
##
## 入口: find_path(grid, from_world, to_world, layer) → Array[Vector2]
##   - 返回的 waypoint 列表是 world 坐标 (像素), cell 中心 + 末尾替换为精确 to_world
##   - 第一个 cell (单位当前所在 cell) 不进 waypoint, 单位直接朝 path[1] 走
##   - 找不到路径返回空 array (调方可保持原地或 fail-safe 直接走目标)
##
## 不变量:
##   - astar 调用 grid.is_passable_for_layer(coord, layer) 做 callback, 不读 grid 私有字段
##   - 不修改 ultra-grid-map plugin (D3-F)
class_name RtsPathfinding
extends RefCounted


## 走 A* 找路, 返回 world 坐标 waypoint 列表。
##
## @param grid: RtsBattleGrid wrapper
## @param from_world: 起点 world 坐标
## @param to_world: 终点 world 坐标
## @param layer: 移动 layer (MovementLayer.Layer.GROUND / AIR)
## @return: Array[Vector2] waypoint 列表; 找不到路径返回空 array
static func find_path(
	grid: RtsBattleGrid,
	from_world: Vector2,
	to_world: Vector2,
	layer: int = MovementLayer.Layer.GROUND,
) -> Array[Vector2]:
	if grid == null or grid.model == null:
		return []

	# P2.8: AIR 单位绕开 A* — grid.is_passable_for_layer(AIR) 永远 true, A* 跑出来都是直线邻 cell,
	# 不如直接 direct_path 让飞行走斜对角到目标 (穿地面建筑 footprint)。也省 A* 调用开销。
	if layer == MovementLayer.Layer.AIR:
		return _direct_path(to_world)

	var from_coord := grid.world_to_coord(from_world)
	var to_coord := grid.world_to_coord(to_world)

	# 起点 cell 不存在 / 不可通行 — 多发生在单位被推到地图外 / 起点恰好被 building 标 blocking。
	# Phase 1 不做"贪心邻 cell 修正"; 直接退化为单一 waypoint = to_world(让单位直奔目标)。
	if not grid.has_tile(from_coord) or not grid.has_tile(to_coord):
		return _direct_path(to_world)

	# 同 cell — 单位距 to_world 不足一个 cell, 直接给 to_world 一个 waypoint 即可。
	if from_coord.equals(to_coord):
		return _direct_path(to_world)

	var is_passable := func(c: HexCoord) -> bool:
		return grid.is_passable_for_layer(c, layer)

	# 起点本身可能 blocking(被推进 building 内); A* 起点 always allowed, 由 plugin 实现保证
	# (它从 start 加入 frontier 不查 is_passable; 仅查 neighbor)。但保险起见检查终点。
	if not grid.is_passable_for_layer(to_coord, layer):
		return _direct_path(to_world)

	var result := GridPathfinding.astar(grid.model, from_coord, to_coord, is_passable)
	if not result.found:
		return []

	var waypoints: Array[Vector2] = []
	# Skip path[0] (起点单位已在); 从 path[1] 开始记 cell 中心
	for i in range(1, result.path.size()):
		waypoints.append(grid.coord_to_world(result.path[i]))
	if waypoints.is_empty():
		waypoints.append(to_world)
	else:
		# 把最后一个 waypoint(目标 cell 中心)替换为精确 to_world, 让单位精确抵达目标。
		waypoints[waypoints.size() - 1] = to_world
	return waypoints


# ========== 内部 ==========

static func _direct_path(to_world: Vector2) -> Array[Vector2]:
	var path: Array[Vector2] = []
	path.append(to_world)
	return path
