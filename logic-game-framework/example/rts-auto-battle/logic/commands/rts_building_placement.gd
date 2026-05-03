## RtsBuildingPlacement - 建筑放置合法性校验 (P2.6)
##
## 给 RtsPlaceBuildingCommand 调用, 在实际 add_actor 之前判断 placement 是否合法:
##   1. 玩家阵营的 build_zone 包含中心点 (无限制 build_zone 视为通过)
##   2. footprint cells 全在地图内 (grid.has_tile)
##   3. footprint cells 全不阻挡 (无别的建筑占用; obstacle 不允许)
##   4. 没有现存单位 / 建筑在 footprint cells 上 (检 grid 反向索引)
##   5. M2.1 Phase A — team 多资源充足 (逐 key check; 任一不足 → reason="not_enough_<kind>")
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
##   team_remaining: Dictionary[String, int] 当前阵营剩余资源 (key = "gold" / "wood")
##   building_kind: String (RtsBuildingConfig.KIND_*)
##   world_pos: Vector2 (建筑中心)
##
## 返回 dict:
##   { "success": bool, "reason": String, "footprint": Array[HexCoord] (success=true 时填),
##     "cost": Dictionary[String, int] (success=true 时填) }
##
## reason 枚举:
##   "team_mismatch"            : team_id 不在 team_config 里
##   "out_of_build_zone"        : world_pos 不在 build_zone 内
##   "out_of_map"               : 任一 footprint cell 不存在 (地图边界外)
##   "cells_blocked"            : 任一 footprint cell 是 obstacle 或已被建筑占用
##   "cells_occupied_by_actors" : footprint cells 内有现存单位 / 建筑
##   "not_enough_<kind>"        : 任一资源 (key) 余额不足 — 例 "not_enough_gold" / "not_enough_wood"
##                                (M2.1 Phase A 取代旧 "not_enough_resources")
static func validate(
	grid: RtsBattleGrid,
	team_config: RtsTeamConfig,
	team_remaining: Dictionary,
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

	# 5. M2.1 Phase A — 多资源充足 check (逐 key); 任一不足 → reason="not_enough_<kind>"。
	#    cost 缺 key / value=0 跳过 (该资源不要求); team_remaining 缺 key 视为 0。
	for kind in stats.cost:
		var needed: int = int(stats.cost[kind])
		if needed <= 0:
			continue
		var available: int = int(team_remaining.get(kind, 0))
		if available < needed:
			return {
				"success": false,
				"reason": "not_enough_" + str(kind),
				"details": { "kind": str(kind), "needed": needed, "available": available },
			}

	return {
		"success": true,
		"reason": "ok",
		"footprint": footprint,
		"cost": stats.cost,
	}


# ========== 内部 ==========

## 与 RtsBuildingActor.get_footprint_cells 同算法 — 但走 center coord + footprint_size,
## 让校验阶段不依赖 actor 实例 (placement 失败时不应 new actor)。
##
## 偶数尺寸左上偏置, 奇数居中, 与 RtsBuildingActor.get_footprint_cells 完全一致。
##
## **M0.5**: 内部抽出 _compute_footprint_cells_core, actor / placement / ghost preview 共享
## (data-structures.md §M0.5 — 避免双份算法漂移).
static func _compute_footprint_cells(center: HexCoord, footprint_size: Vector2i) -> Array:
	return _compute_footprint_cells_core(center, footprint_size.x, footprint_size.y)


## M0.5 — 从 RtsObstructionShapeStatic 算 footprint cells (新算法; 用 obstruction_shape.center
## 当中心, w/h ÷ cell_size 推 cells_w/h). 跟 RtsBuildingActor.get_footprint_cells 新路径
## 走同一 core helper, 无双份算法漂移.
##
## 用于:
##   - placement 校验时 (validate 入口尚未引, 现走 footprint_size 路径; M0.6 ghost preview 切此)
##   - frontend ghost preview 渲染 (M0.6 落地)
static func _compute_footprint_cells_from_shape(shape: RtsObstructionShapeStatic, grid: RtsBattleGrid) -> Array:
	if shape == null or grid == null:
		return []
	var center: HexCoord = grid.world_to_coord(shape.center)
	# int(round(...)) 显式整数化, 避免浮点精度漂移 (与 actor.get_footprint_cells 一致, M0.4 风险 R2)
	var cells_w: int = int(round(shape.width / grid.cell_size))
	var cells_h: int = int(round(shape.height / grid.cell_size))
	return _compute_footprint_cells_core(center, cells_w, cells_h)


## M0.5 — Core AABB cells 算法, 偶数尺寸"左上偏置" (上半左半), 奇数居中.
## actor.get_footprint_cells / _compute_footprint_cells / _compute_footprint_cells_from_shape
## 共享, 严格保留旧偏置方向 (codex P1 #1).
static func _compute_footprint_cells_core(center: HexCoord, cells_w: int, cells_h: int) -> Array:
	if cells_w <= 1 and cells_h <= 1:
		return [center]
	var half_x_lo: int = cells_w / 2
	var half_x_hi: int = cells_w - 1 - half_x_lo
	var half_y_lo: int = cells_h / 2
	var half_y_hi: int = cells_h - 1 - half_y_lo
	var result: Array = []
	for dy in range(-half_y_lo, half_y_hi + 1):
		for dx in range(-half_x_lo, half_x_hi + 1):
			var coord := HexCoord.new(center.q + dx, center.r + dy)
			result.append(coord)
	return result
