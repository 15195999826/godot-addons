## RtsComputerPlayer - team-level AI 对手
##
## 简化设计 (用户拍板): AI Player 只管经济 — 钱够就造兵营, 无 cap. 单位的攻击 / 寻敌 /
## 移动归 unit-AI (RtsAttackMoveActivity + AutoTargetSystem + BasicAttackStrategy 链路);
## AI Player 不直接派兵.
##
## 每 DECISION_INTERVAL_TICKS 决策一次, 走 RtsPlayerCommandQueue (与玩家同接口) enqueue
## PlaceBuildingCommand → 决定性 OK, bit-identical replay 不破。
##
## 不变量 (决定性来源):
##   - think 只读 world / procedure 状态, 不写 actor / system 内部字段
##   - 状态查询每决策 tick 现查不缓存 (资源)
##   - 失败 (cells_blocked / out_of_zone) 下个决策 tick 重试 (think 是 stateless)
class_name RtsComputerPlayer
extends RefCounted


# ========== 决策粒度 ==========

## 每 30 tick (1s @ 30Hz) 触发一次决策; 非决策 tick think() 直接返
const DECISION_INTERVAL_TICKS: int = 30

## barracks 建造位置: ct 偏移点 (左 team +96 east, 右 team -96 west; 3 cell @ size=32)
const BARRACKS_OFFSET_X: float = 96.0


# ========== 字段 ==========

## 阵营 ID (0=left, 1=right; 与 RtsBattleActor.team_id 对齐)
var team_id: int = -1


# ========== 初始化 ==========

func _init(p_team_id: int) -> void:
	team_id = p_team_id


# ========== 决策入口 ==========

## procedure tick 末尾调用 (非决策 tick 直接返)。
func think(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	if world == null:
		return
	if current_tick % DECISION_INTERVAL_TICKS != 0:
		return
	_try_build_barracks(world, current_tick)


# ========== 决策实现 ==========

## Build 决策: 钱够就造 barracks, 无 cap. 落点固定 ct 偏移点.
##
## placement 校验失败 (out of build_zone / cells_occupied) 走 PlaceBuildingCommand.apply
## 内部失败链路, 失败 → 下个决策 tick 再试 (天然 retry — stateless)。
func _try_build_barracks(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	var procedure := world.procedure
	if procedure == null:
		return
	var cost := RtsBuildingConfig.get_stats(RtsBuildingConfig.KIND_BARRACKS).cost
	if not _team_can_afford(procedure, cost):
		return
	var ct_pos: Vector2 = _find_team_ct_position_for(world, procedure, team_id)
	if ct_pos == Vector2.INF:
		return
	var offset_x: float = BARRACKS_OFFSET_X if team_id == 0 else -BARRACKS_OFFSET_X
	var place_pos: Vector2 = ct_pos + Vector2(offset_x, 0.0)
	procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		current_tick, team_id, RtsBuildingConfig.KIND_BARRACKS, place_pos,
	))


# ========== 内部 helpers ==========

## 资源充足判定 — 逐 key 对比 cost 与 procedure team_resources。
## 缺 key → 视为 0; 任一 key 不足 → 返 false。
func _team_can_afford(procedure: RtsAutoBattleProcedure, cost: Dictionary) -> bool:
	var remaining: Dictionary = procedure.get_team_resources(team_id)
	for kind in cost:
		if int(remaining.get(kind, 0)) < int(cost[kind]):
			return false
	return true


## 找指定 team 的 ct.position_2d; 没 ct → Vector2.INF.
func _find_team_ct_position_for(world: RtsWorldGameplayInstance, procedure: RtsAutoBattleProcedure, p_team_id: int) -> Vector2:
	var cfg: RtsTeamConfig = procedure.get_team_config(p_team_id)
	if cfg == null or not cfg.has_crystal_tower():
		return Vector2.INF
	var ct: Actor = world.get_actor(cfg.crystal_tower_id)
	if ct == null:
		return Vector2.INF
	var ct_actor := ct as RtsBattleActor
	if ct_actor == null or ct_actor.is_dead():
		return Vector2.INF
	return ct_actor.position_2d
