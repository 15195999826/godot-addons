## RtsBuildingPlacement - 建筑放置合法性校验 (P2.6)
##
## 给 RtsPlaceBuildingCommand 调用, 在实际 add_actor 之前判断 placement 是否合法:
##   1. 玩家阵营的 build_zone 包含中心点 (无限制 build_zone 视为通过)
##   2. footprint cells 全在地图内 (grid.has_tile)
##   3. footprint cells 全不阻挡 (无别的建筑占用; obstacle 不允许)
##   4. team 资源充足 (cost ≤ remaining)
##   5. 没有现存单位 / 建筑在 footprint cells 上 (检 grid 反向索引)
##
## 不修改任何状态 — 纯校验; 调方负责在通过后实际 add_actor + place_building + 扣资源。
##
## 决策来源: phase-2-core-systems.md §P2.6 "logic/commands/rts_building_placement.gd
## (合法性: 建造区 / 占用 cells / 资金)"
class_name RtsBuildingPlacement
extends RefCounted


# ========== 静态校验入口 ==========

## 校验在 (world_pos, building_kind) 放置一栋 team_id 阵营的建筑是否合法。
##
## 参数:
##   grid: RtsBattleGrid
##   team_config: RtsTeamConfig (build_zone / starting_resources)
##   team_remaining: int 当前阵营剩余资源
##   building_kind: String (RtsBuildingConfig.KIND_*)
##   world_pos: Vector2 (建筑中心)
##
## 返回 dict:
##   { "success": bool, "reason": String, "footprint": Array[HexCoord] (success=true 时填) }
##
## reason 枚举:
##   "team_mismatch"            : team_id 不在 team_config 里
##   "out_of_build_zone"        : world_pos 不在 build_zone 内
##   "out_of_map"               : 任一 footprint cell 不存在 (地图边界外)
##   "cells_blocked"            : 任一 footprint cell 是 obstacle 或已被建筑占用
##   "cells_occupied_by_actors" : footprint cells 内有现存单位 / 建筑
##   "not_enough_resources"     : team_remaining < cost
static func validate(
	grid: RtsBattleGrid,
	team_config: RtsTeamConfig,
	team_remaining: int,
	building_kind: String,
	world_pos: Vector2,
) -> Dictionary:
	if grid == null or team_config == null:
		return { "success": false, "reason": "missing_grid_or_team_config" }

	# 1. build_zone
	if not team_config.contains_position(world_pos):
		return { "success": false, "reason": "out_of_build_zone" }

	# 2. footprint cells 全部在地图内
	var stats := RtsBuildingConfig.get_stats(building_kind)
	var center := grid.world_to_coord(world_pos)
	var footprint := _compute_footprint_cells(center, stats.footprint_size)
	for c in footprint:
		var coord := c as HexCoord
		if not grid.has_tile(coord):
			return { "success": false, "reason": "out_of_map" }

	# 3. footprint cells 全不阻挡
	for c in footprint:
		var coord := c as HexCoord
		if grid.model.is_tile_blocking(coord):
			return { "success": false, "reason": "cells_blocked" }

	# 4. footprint cells 内无现存 actor (反向索引)
	for c in footprint:
		var coord := c as HexCoord
		var occupants := grid.get_occupants_at(coord)
		if not occupants.is_empty():
			return { "success": false, "reason": "cells_occupied_by_actors" }

	# 5. 资源充足
	var cost: int = stats.cost
	if team_remaining < cost:
		return {
			"success": false,
			"reason": "not_enough_resources",
			"details": { "needed": cost, "available": team_remaining },
		}

	return {
		"success": true,
		"reason": "ok",
		"footprint": footprint,
		"cost": cost,
	}


# ========== 内部 ==========

## 与 RtsBuildingActor.get_footprint_cells 同算法 — 但走 center coord + footprint_size,
## 让校验阶段不依赖 actor 实例 (placement 失败时不应 new actor)。
##
## 偶数尺寸左上偏置, 奇数居中, 与 RtsBuildingActor.get_footprint_cells 完全一致。
static func _compute_footprint_cells(center: HexCoord, footprint_size: Vector2i) -> Array:
	if footprint_size.x <= 1 and footprint_size.y <= 1:
		return [center]
	var half_x_lo: int = footprint_size.x / 2
	var half_x_hi: int = footprint_size.x - 1 - half_x_lo
	var half_y_lo: int = footprint_size.y / 2
	var half_y_hi: int = footprint_size.y - 1 - half_y_lo
	var result: Array = []
	for dy in range(-half_y_lo, half_y_hi + 1):
		for dx in range(-half_x_lo, half_x_hi + 1):
			var coord := HexCoord.new(center.q + dx, center.r + dy)
			result.append(coord)
	return result
