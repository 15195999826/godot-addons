## Dota2UnitController - 每单位运行时行为拥有者（README.md（Controller / Intent 模型 节））
##
## 拥有 behavior_mode / current_intent / current_intent_status / last_decision_result /
## next_decision_tick。**不**直接改 position / hp / cooldown / 执行 ability / 删 actor /
## 调 frontend —— 只选/保持/打断自己的 current intent + 记录执行状态。
##
## 编排（procedure 调）：
##   step 4 decision: decide_if_needed(world, tick) → 据 DecisionResult 改 current_intent
##   step 6 result:    record_step_result(result, tick) → 据 StepResult 推进生命周期
class_name Dota2UnitController
extends RefCounted


const BEHAVIOR_LANE_CREEP := "lane_creep"


var actor_id: String = ""
var team_id: int = -1
## 决策错峰用（README.md（Controller / Intent 模型 节）：actor_spawn_index % 3，避免同 tick 齐扫）。
var spawn_index: int = 0
var behavior_mode: String = BEHAVIOR_LANE_CREEP

var current_intent: Dota2Intent = null
var current_intent_status: String = Dota2IntentStatus.NONE
var last_decision_result: Dota2DecisionResult = null
## 下一次"允许重新考虑"的 tick（仅对允许 reconsider 的 intent 有意义）。
var next_decision_tick: int = 0


func _init(p_actor_id: String, p_team_id: int, p_spawn_index: int) -> void:
	actor_id = p_actor_id
	team_id = p_team_id
	spawn_index = p_spawn_index


# ========== 决策步（procedure step 4）==========

## 子类实现：返回本 tick 的 DecisionResult。仅在 _needs_decision 为真时被调。
func decide(_world: Dota2WorldGameplayInstance, _tick: int) -> Dota2DecisionResult:
	return Dota2DecisionResult.keep()


## 决策触发条件（README.md（Controller / Intent 模型 节）「Decision Triggers」）：
## 没有 current intent / 上次 step 终态 / 到达 next_decision_tick。
## 不因"新 tick 发生"而决策。
func _needs_decision(tick: int) -> bool:
	if current_intent == null:
		return true
	if current_intent_status == Dota2IntentStatus.COMPLETED:
		return true
	if current_intent_status == Dota2IntentStatus.FAILED:
		return true
	if current_intent_status == Dota2IntentStatus.INTERRUPTED:
		return true
	if tick >= next_decision_tick and _intent_allows_reconsider():
		return true
	return false


## 子类覆盖：当前 intent 是否允许周期性重新考虑（lane march 允许 aggro 复扫；
## attack target 有效期间不允许 —— 防止周期扫描换目标导致抖动）。
func _intent_allows_reconsider() -> bool:
	return false


## procedure step 4 入口：必要时决策并应用到 current_intent。
## 返回本 tick 产生的 intent 生命周期事件（procedure push 进 collector）。
func decide_if_needed(world: Dota2WorldGameplayInstance, tick: int) -> Array[Dictionary]:
	if not _needs_decision(tick):
		return []
	var decision := decide(world, tick)
	last_decision_result = decision
	return _apply_decision(decision, tick)


func _apply_decision(decision: Dota2DecisionResult, tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match decision.action:
		Dota2DecisionResult.ACTION_CREATE:
			if current_intent != null and current_intent_status == Dota2IntentStatus.RUNNING:
				# interrupt-replace：先报旧 intent 被打断（事实），再上新 intent。
				events.append(Dota2BattleEvents.make_intent_failed(
					actor_id, current_intent.intent_id, current_intent.kind,
					"interrupted:" + decision.replace_reason,
				))
			current_intent = decision.new_intent
			current_intent_status = Dota2IntentStatus.RUNNING
			events.append(Dota2BattleEvents.make_intent_started(
				actor_id, current_intent.intent_id, current_intent.kind,
				current_intent.get_target_id(),
			))
		Dota2DecisionResult.ACTION_CLEAR:
			current_intent = null
			current_intent_status = Dota2IntentStatus.NONE
		Dota2DecisionResult.ACTION_KEEP:
			pass
	return events


# ========== 结果步（procedure step 6）==========

## systems 推进 current intent 后回灌执行结果，controller 据此推进生命周期。
## 返回本 tick 产生的 intent 生命周期事件。
func record_step_result(result: Dota2IntentStepResult, _tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if current_intent == null:
		return events
	if result.status == Dota2IntentStatus.RUNNING:
		current_intent_status = Dota2IntentStatus.RUNNING
		return events
	# 终态：记录事实，清空 intent，下 tick 立即重决策（_needs_decision 因 status 终态返 true）。
	if result.status == Dota2IntentStatus.COMPLETED:
		events.append(Dota2BattleEvents.make_intent_completed(
			actor_id, current_intent.intent_id, current_intent.kind, result.reason,
		))
	else:
		events.append(Dota2BattleEvents.make_intent_failed(
			actor_id, current_intent.intent_id, current_intent.kind, result.reason,
		))
	current_intent_status = result.status
	return events


# ========== 查询（snapshot / debug 用）==========

func get_intent_kind() -> String:
	return current_intent.kind if current_intent != null else ""


func get_intent_id() -> int:
	return current_intent.intent_id if current_intent != null else 0


func get_intent_target_id() -> String:
	return current_intent.get_target_id() if current_intent != null else ""
