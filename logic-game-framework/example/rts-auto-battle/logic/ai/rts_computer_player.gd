## RtsComputerPlayer - team-level AI 对手 (M2.2)
##
## 每 DECISION_INTERVAL_TICKS 决策一次, 走 RtsPlayerCommandQueue (与玩家同接口) enqueue
## PlaceBuildingCommand / MoveUnitsCommand → 决定性 OK, bit-identical replay 不破。
##
## 不变量 (决定性来源):
##   - think 只读 world / procedure 状态, 不写 actor / system 内部字段
##   - 状态查询每决策 tick 现查不缓存 (barracks 数 / 资源 / non-worker unit list)
##   - _attack_dispatched 由 procedure 管理生命周期 (procedure-attached object)
##
## 决策来源: task-plan/m2-2-ai-opponent/README.md §设计决策表 E1-E10
class_name RtsComputerPlayer
extends RefCounted


# ========== 决策粒度 ==========

## E3 — 每 30 tick (1s @ 30Hz) 触发一次决策; 非决策 tick think() 直接返
const DECISION_INTERVAL_TICKS: int = 30

## E4 — barracks 建造位置: ct 偏移点 (左 team +96 east, 右 team -96 west; 3 cell @ size=32)
const BARRACKS_OFFSET_X: float = 96.0

## E5 — barracks 建造 cap (1 个/team; ≥ 1 就不再放)
const BARRACKS_CAP: int = 1

## E6 — 触发 attack-move 的最小 alive non-worker unit 数量
const ATTACK_DISPATCH_THRESHOLD: int = 3


# ========== 字段 ==========

## 阵营 ID (0=left, 1=right; 与 RtsBattleActor.team_id 对齐)
var team_id: int = -1

## E6 cache: 是否已发出过 attack-move 命令 (M2.2 不做反复跟随, only-once)
var _attack_dispatched: bool = false


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
	_try_attack(world, current_tick)


# ========== 决策实现 ==========

## E2 — Build 决策: barracks 1 cap, ct 偏移点。
##
## placement 校验失败 (out of build_zone / cells_occupied) 走 PlaceBuildingCommand.apply
## 内部失败链路, 失败 → 下个决策 tick 再试 (天然 retry — _try_build_barracks 是 stateless)。
func _try_build_barracks(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	var procedure := world.procedure
	if procedure == null:
		return
	if _count_team_barracks(world) >= BARRACKS_CAP:
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


## E3 — Attack 决策: ≥ ATTACK_DISPATCH_THRESHOLD non-worker unit 后 attack-move 一次。
##
## RtsMoveUnitsCommand 走纯 RtsMoveToActivity, unit 走到敌方 ct 后 controller
## ._player_command_active 自然清零 → RtsBasicAttackStrategy + AutoTargetSystem 接管 →
## unit 在 ct 范围内 attack ct (不需要 attack_move=true 标志)。
func _try_attack(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	if _attack_dispatched:
		return
	var procedure := world.procedure
	if procedure == null:
		return
	var dispatch_unit_ids: Array[String] = _collect_team_non_worker_unit_ids(world)
	if dispatch_unit_ids.size() < ATTACK_DISPATCH_THRESHOLD:
		return
	var enemy_team_id: int = 1 - team_id
	var enemy_ct_pos: Vector2 = _find_team_ct_position_for(world, procedure, enemy_team_id)
	if enemy_ct_pos == Vector2.INF:
		return
	procedure.enqueue_player_command(RtsMoveUnitsCommand.new(
		current_tick, team_id, dispatch_unit_ids, enemy_ct_pos,
	))
	_attack_dispatched = true


# ========== 内部 helpers ==========

## E5 — 数己方 alive barracks (实时计数, 不缓存; 决定性来源 = 同 game state → 同决策)
func _count_team_barracks(world: RtsWorldGameplayInstance) -> int:
	var count: int = 0
	for actor in world.get_alive_actors():
		if not (actor is RtsBuildingActor):
			continue
		var building := actor as RtsBuildingActor
		if building.get_team_id() != team_id:
			continue
		if building.building_kind == RtsBuildingConfig.KIND_BARRACKS:
			count += 1
	return count


## 资源充足判定 — 逐 key 对比 cost 与 procedure team_resources。
## 缺 key → 视为 0; 任一 key 不足 → 返 false。
func _team_can_afford(procedure: RtsAutoBattleProcedure, cost: Dictionary) -> bool:
	var remaining: Dictionary = procedure.get_team_resources(team_id)
	for kind in cost:
		if int(remaining.get(kind, 0)) < int(cost[kind]):
			return false
	return true


## 找指定 team 的 ct.position_2d (Build 决策查己方, Attack 决策查敌方);
## 没 ct (team_config 没绑 / actor 已死 / world 没此 actor) → Vector2.INF。
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


## 收集己方 alive non-worker RtsUnitActor 的 actor_id (E6 — 不含 worker; spawn 顺序自然 stable)。
func _collect_team_non_worker_unit_ids(world: RtsWorldGameplayInstance) -> Array[String]:
	var ids: Array[String] = []
	for unit in world.get_alive_units():
		if unit.get_team_id() != team_id:
			continue
		if unit.unit_class == RtsUnitClassConfig.UnitClass.WORKER:
			continue
		ids.append(unit.get_id())
	return ids
