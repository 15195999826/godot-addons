## RtsTeamConfig - 阵营配置 (P2.6)
##
## 给 RtsAutoBattleProcedure 在战斗起始时配齐每一队的"宏观资源 / 建造区 / 主基地"。
## 包含 P2.6 玩家命令验证 (建造区合法性) + 资源扣减 (兵营 / 防御塔成本) + 胜负判定
## (crystal_tower_id 死亡 → 该队伍败) 所需的所有静态信息。
##
## 实例由 smoke / 调方在 procedure 起手前装配; 不可在战斗中变更 (build_zone 与
## faction_id 是静态合同)。资源消耗 / 残量在 procedure 内部 _team_resources 跟踪,
## 不写回此 config。
##
## 决策来源: phase-2-core-systems.md §P2.6 "RtsTeam 抽象 (faction_id /
## starting_resources / build_zone)"
class_name RtsTeamConfig
extends RefCounted


# ========== 字段 ==========

## 阵营 ID (0=left, 1=right; 与 RtsBattleActor.team_id 对齐)
var team_id: int = -1

## 阵营标识 (供 frontend / replay 区分; "human" / "orc" 等; M1 仅占位)
var faction_id: String = ""

## 起手资源量 (供 PlaceBuildingCommand 扣减)
var starting_resources: int = 0

## 建造区 (world 像素 Rect2; 玩家命令落在此区外的 placement 视为非法)
## 默认 Rect2(0, 0, 0, 0) 表示无限制 (旧 smoke 不破)
var build_zone: Rect2 = Rect2()

## 阵营主基地 actor id (P2.6 胜负判定 — 此 actor 死亡 → 该 team 败)
## 空字符串 = 未配置 → 退化为 Phase 1 "team 全灭" 兼容判定
var crystal_tower_id: String = ""


# ========== 工厂 ==========

## 全部默认值快速实例化 (旧 smoke 不传 team_configs 时, procedure 内用此 ctor 填占位)
static func unconfigured(p_team_id: int) -> RtsTeamConfig:
	var cfg := RtsTeamConfig.new()
	cfg.team_id = p_team_id
	return cfg


## P2.6 smoke / demo 常用入口 — 一次性配齐 4 字段。
## build_zone 默认 Rect2() = 无限制; crystal_tower_id 由调方在 add_actor 后 set。
static func create(
	p_team_id: int,
	p_faction_id: String = "",
	p_starting_resources: int = 0,
	p_build_zone: Rect2 = Rect2(),
) -> RtsTeamConfig:
	var cfg := RtsTeamConfig.new()
	cfg.team_id = p_team_id
	cfg.faction_id = p_faction_id
	cfg.starting_resources = p_starting_resources
	cfg.build_zone = p_build_zone
	return cfg


# ========== 查询 ==========

## 是否配置了 build_zone 限制 (零矩形 = 无限制)。
func has_build_zone() -> bool:
	return build_zone.size.x > 0.0 and build_zone.size.y > 0.0


## 给定 world 坐标是否落在建造区内 (无限制时永远 true)。
func contains_position(world_pos: Vector2) -> bool:
	if not has_build_zone():
		return true
	return build_zone.has_point(world_pos)


## 是否配置了水晶塔 (P2.6 新胜负判定); 未配置 → procedure 退化到 team 全灭判定。
func has_crystal_tower() -> bool:
	return crystal_tower_id != ""
