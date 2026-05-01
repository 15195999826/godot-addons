## RtsPlaceBuildingCommand - 玩家放置建筑命令 (P2.6)
##
## 触发流程 (procedure 在 step 2 调用 apply):
##   1. 读 procedure.get_team_config(team_id) + 当前剩余资源
##   2. RtsBuildingPlacement.validate(...) 校验合法性
##   3. 通过 → RtsBuildings.create_<kind>() 工厂创建建筑 actor + add_actor +
##      set position_2d + place_building 写 pathing map + 扣资源 +
##      若 is_crystal_tower 且 team_config.crystal_tower_id 还空, 自动绑定
##   4. 失败 → 返回 reason; 命令进 procedure._failed_commands 给 replay 反馈
##
## 设计取舍:
##   - 工厂方法只支持 KIND_BARRACKS / KIND_CRYSTAL_TOWER / KIND_ARCHER_TOWER (P2.5 的 3 种)
##     未来扩 building_kind 时 RtsBuildings 加新 factory + 此处加 match 分支
##   - 资源扣减发生在 apply 内 — 失败时不扣 (validate 内 cost 不足直接返回 reason)
##   - footprint 写 pathing map 在 apply 内 (procedure.start() 仅处理战斗起手已存在的建筑;
##     战斗中通过此命令新增的建筑由命令自己负责写 pathing map)
##
## 决策来源: phase-2-core-systems.md §P2.6 "PlaceBuildingCommand /
## UpgradeBuildingCommand / SellBuildingCommand"
class_name RtsPlaceBuildingCommand
extends RtsPlayerCommand


# ========== 字段 ==========

## 建筑 kind 字符串 (RtsBuildingConfig.KIND_BARRACKS / KIND_CRYSTAL_TOWER / KIND_ARCHER_TOWER)
var building_kind: String = ""

## 建筑中心世界坐标 (像素)
var position_2d: Vector2 = Vector2.ZERO


# ========== 初始化 ==========

func _init(
	p_tick_stamp: int,
	p_team_id: int,
	p_building_kind: String,
	p_position_2d: Vector2,
) -> void:
	tick_stamp = p_tick_stamp
	team_id = p_team_id
	building_kind = p_building_kind
	position_2d = p_position_2d


# ========== 执行 ==========

## 应用本命令。procedure 在 step 2 调用; 失败时不静默丢弃 — 返回 result dict 由 procedure
## 写入 _failed_commands 给 replay / UI 反馈。
##
## 成功 details 含 "actor_id" (新建筑 id), "footprint" (Array[HexCoord]), "cost" (int)。
func apply(procedure, world) -> Dictionary:
	if procedure == null or world == null:
		return { "success": false, "reason": "missing_procedure_or_world" }

	var rts_world := world as RtsWorldGameplayInstance
	if rts_world == null or rts_world.rts_grid == null:
		return { "success": false, "reason": "missing_rts_grid" }

	var team_config: RtsTeamConfig = procedure.get_team_config(team_id)
	if team_config == null:
		return { "success": false, "reason": "team_mismatch" }

	var team_remaining: int = procedure.get_team_resources(team_id)

	# 1. 合法性校验
	var check := RtsBuildingPlacement.validate(
		rts_world.rts_grid,
		team_config,
		team_remaining,
		building_kind,
		position_2d,
	)
	if not check.get("success", false):
		return check

	# 2. 创建建筑
	var building: RtsBuildingActor = _create_building_for_kind(building_kind)
	if building == null:
		return { "success": false, "reason": "unknown_building_kind" }
	building.set_team_id(team_id)
	rts_world.add_actor(building)
	building.position_2d = position_2d

	# 3. 写 pathing map (战斗中新建筑由命令自己负责; procedure.start 仅处理战斗起手)
	var footprint: Array = building.get_footprint_cells(rts_world.rts_grid)
	rts_world.rts_grid.place_building(building.get_id(), footprint)

	# 4. 扣资源
	var cost: int = int(check.get("cost", 0))
	procedure.spend_team_resources(team_id, cost)

	# 5. 加入 procedure 的 team 列表 (让 _check_battle_end 看见)
	procedure.add_unit_to_team(building, team_id)

	# 6. 若是水晶塔且 team_config 还没绑 crystal_tower_id, 自动绑定 (玩家命令是水晶塔的合法来源)
	if building.is_crystal_tower and team_config.crystal_tower_id == "":
		team_config.crystal_tower_id = building.get_id()

	return {
		"success": true,
		"reason": "placed",
		"actor_id": building.get_id(),
		"footprint": footprint,
		"cost": cost,
	}


# ========== 序列化 ==========

func command_type() -> String:
	return "place_building"


func serialize() -> Dictionary:
	var base := super.serialize()
	base["building_kind"] = building_kind
	base["position_2d"] = { "x": position_2d.x, "y": position_2d.y }
	return base


# ========== 内部 ==========

## 工厂分发 — 与 RtsBuildings.create_* 一一对应; 未知 kind 返回 null。
##
## 加新建筑 kind 时 (P2.8 防空塔等) 在此 match 加分支即可, 不动 validate / apply 主路径。
static func _create_building_for_kind(kind: String) -> RtsBuildingActor:
	match kind:
		RtsBuildingConfig.KIND_CRYSTAL_TOWER:
			return RtsBuildings.create_crystal_tower()
		RtsBuildingConfig.KIND_BARRACKS:
			return RtsBuildings.create_barracks()
		RtsBuildingConfig.KIND_ARCHER_TOWER:
			return RtsBuildings.create_archer_tower()
		_:
			return null
