## RtsComputerPlayer - team-level AI 对手 (M2.2)
##
## 每 DECISION_INTERVAL_TICKS (30 tick = 1s @ 30Hz) 决策一次, 走 RtsPlayerCommandQueue
## 与玩家同接口 enqueue PlaceBuildingCommand / MoveUnitsCommand, 保 bit-identical replay。
##
## 不持有 procedure ref (避免循环); world.procedure 已就位 (M2.1 Phase C),
## 通过 world.procedure.* 访问 procedure API。
##
## 不变量:
##   - decide 只读 world / procedure 状态, 不写 actor / system 内部字段
##   - _attack_dispatched 由 procedure 管理生命周期 (procedure-attached object → 决定性 OK)
##   - 决定性来源 = 同 game state → 同决策; barracks 数每决策 tick 重新查 (不缓存)
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


# ========== 字段 ==========

## 阵营 ID (0=left, 1=right; 与 RtsBattleActor.team_id 对齐)
var team_id: int = -1

## E6 cache: 是否已发出过 attack-move 命令 (M2.2 不做反复跟随, only-once)
var _attack_dispatched: bool = false


# ========== 初始化 ==========

func _init(p_team_id: int) -> void:
	team_id = p_team_id


# ========== 决策入口 ==========

## procedure tick 末尾调用 — 非决策 tick (current_tick % DECISION_INTERVAL_TICKS != 0)
## 直接返。决策 tick 顺序:
##   1. _try_build_barracks: 资源 ≥ cost + barracks 数 == 0 → enqueue PlaceBuildingCommand
##   2. _try_attack: alive non-worker unit ≥ 3 → enqueue MoveUnitsCommand (only-once)
func think(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	if world == null:
		return
	if current_tick % DECISION_INTERVAL_TICKS != 0:
		return
	_try_build_barracks(world, current_tick)
	_try_attack(world, current_tick)


# ========== 决策实现 (E.1 占位; E.2 / E.3 实现) ==========

## E2 — Build 决策: barracks 1 cap, ct 偏移点。
##
## 流程:
##   1. 查己方 barracks 数 (E5 — 实时计数, 不缓存) ≥ BARRACKS_CAP → 不放
##   2. 查己方资源 (procedure.get_team_resources) 不足 cost → 不放
##   3. 找己方 ct.position_2d (team_config.crystal_tower_id) → 不存在 → 不放
##   4. 算 ct + offset (左 +96, 右 -96) → enqueue PlaceBuildingCommand (tick_stamp = current_tick)
##
## placement 校验失败 (out of build_zone / cells_occupied) 走 PlaceBuildingCommand.apply 内
## 部失败链路, 失败 → 下个 1s 决策再试 (天然 retry — _try_build_barracks 是 stateless)。
func _try_build_barracks(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	var procedure := world.procedure
	if procedure == null:
		return
	if _count_team_barracks(world) >= BARRACKS_CAP:
		return
	var cost := RtsBuildingConfig.get_stats(RtsBuildingConfig.KIND_BARRACKS).cost
	if not _team_can_afford(procedure, cost):
		return
	var ct_pos: Vector2 = _find_team_ct_position(world, procedure)
	if ct_pos == Vector2.INF:
		return
	var offset_x: float = BARRACKS_OFFSET_X if team_id == 0 else -BARRACKS_OFFSET_X
	var place_pos: Vector2 = ct_pos + Vector2(offset_x, 0.0)
	procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		current_tick, team_id, RtsBuildingConfig.KIND_BARRACKS, place_pos,
	))


## E3 — Attack 决策: ≥3 non-worker unit 后 attack-move 一次。E.3 实现。
func _try_attack(_world: RtsWorldGameplayInstance, _current_tick: int) -> void:
	pass


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


## 找己方 ct.position_2d; 没 ct (team_config 没绑 / actor 已死 / world 没此 actor) → Vector2.INF。
func _find_team_ct_position(world: RtsWorldGameplayInstance, procedure: RtsAutoBattleProcedure) -> Vector2:
	var cfg: RtsTeamConfig = procedure.get_team_config(team_id)
	if cfg == null or not cfg.has_crystal_tower():
		return Vector2.INF
	var ct: Actor = world.get_actor(cfg.crystal_tower_id)
	if ct == null:
		return Vector2.INF
	var ct_actor := ct as RtsBattleActor
	if ct_actor == null or ct_actor.is_dead():
		return Vector2.INF
	return ct_actor.position_2d
