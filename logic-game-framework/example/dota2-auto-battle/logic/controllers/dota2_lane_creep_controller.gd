## Dota2LaneCreepController - 首个具体 controller（小型显式状态机，M1 不引入行为树）
##
## controller-intent-model.md「First Controller Behavior」：
##   无 current intent → 建 LaneMarchIntent
##   LaneMarch 到 reconsider tick → aggro 范围内有敌 → interrupt 换 AttackTargetIntent
##                                  无敌 → 保持 LaneMarch，排下次 reconsider
##   AttackTarget 终态后重决策 → 仍有 aggro 敌 → 新 AttackTarget；否则回 LaneMarch
##
## AttackTargetIntent 有效期间**不**周期换目标（latch）—— _intent_allows_reconsider
## 仅对 LaneMarch 返 true。决策错峰：next = tick + RESCAN + spawn_index % 3。
class_name Dota2LaneCreepController
extends Dota2UnitController


## controller-intent-model.md：30Hz 下 lane march 每 5 tick 扫一次 aggro。
const AGGRO_RESCAN_INTERVAL_TICKS := 5
const DECISION_STAGGER_MOD := 3


func _init(p_actor_id: String, p_team_id: int, p_spawn_index: int) -> void:
	super(p_actor_id, p_team_id, p_spawn_index)
	behavior_mode = BEHAVIOR_LANE_CREEP


## 仅 LaneMarch 允许周期重扫 aggro；AttackTarget latch 不被周期决策打断。
func _intent_allows_reconsider() -> bool:
	return current_intent != null and current_intent.kind == Dota2Intent.KIND_LANE_MARCH


func decide(world: Dota2WorldGameplayInstance, tick: int) -> Dota2DecisionResult:
	var unit: Dota2UnitActor = world.get_actor(actor_id) as Dota2UnitActor
	if unit == null or unit.is_dead():
		return Dota2DecisionResult.clear()

	var has_running_march := (
		current_intent != null
		and current_intent.kind == Dota2Intent.KIND_LANE_MARCH
		and current_intent_status == Dota2IntentStatus.RUNNING
	)

	# LaneMarch 期间的周期 aggro 复扫：发现敌人 → interrupt-replace 成 AttackTarget。
	if has_running_march:
		var scan_id := Dota2TargetingSystem.find_aggro_target(world, unit)
		if scan_id != "":
			_emit_target_acquired(world, unit, scan_id)
			_schedule_next_reconsider(tick)
			return Dota2DecisionResult.create(
				Dota2Intent.attack_target(tick, scan_id), "aggro_in_range",
			)
		# 无敌：保持 march，排下次复扫 tick。
		_schedule_next_reconsider(tick)
		return Dota2DecisionResult.keep()

	# 无 current intent / 上个 intent 终态 → 重新决策：优先接敌，否则推线。
	var aggro_id := Dota2TargetingSystem.find_aggro_target(world, unit)
	if aggro_id != "":
		_emit_target_acquired(world, unit, aggro_id)
		return Dota2DecisionResult.create(Dota2Intent.attack_target(tick, aggro_id))
	var goal := Dota2LaneConfig.get_lane_goal(unit.get_team_id())
	_schedule_next_reconsider(tick)
	return Dota2DecisionResult.create(Dota2Intent.lane_march(tick, goal))


func _schedule_next_reconsider(tick: int) -> void:
	next_decision_tick = tick + AGGRO_RESCAN_INTERVAL_TICKS + (spawn_index % DECISION_STAGGER_MOD)


func _emit_target_acquired(world: Dota2WorldGameplayInstance, unit: Dota2UnitActor, target_id: String) -> void:
	var dist := Dota2TargetingSystem.distance_to(world, unit, target_id)
	GameWorld.event_collector.push(Dota2BattleEvents.make_target_acquired(actor_id, target_id, dist))
