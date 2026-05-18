## Dota2LogicFrame - 单个固定 logic tick 的只读快照（logic→view 合同）
##
## logic-view-contract.md：snapshot = 当前可观测状态；event = 本 tick 内发生的事；
## view = 只消费。本对象只持稳定数据（Dictionary / 基础类型），**不**持 live actor 引用，
## 这样 frontend 不可能反向 mutate 战斗状态。
##
## actor_snapshots: { actor_id: {
##   actor_id, unit_type_id, team_id, x, y, facing, hp, max_hp, alive,
##   intent_kind, intent_status, intent_target_id, next_decision_tick,
##   movement_state, movement_goal_x, movement_goal_y, movement_block_reason,
##   attack_state, attack_cooldown_remaining_ms, attack_target_id,
## } }
## events: Array[Dictionary]（Dota2BattleEvents.make_* 的产物，本 tick 收集）
class_name Dota2LogicFrame
extends RefCounted


var tick_index: int = 0
var logic_time_ms: float = 0.0
var actor_snapshots: Dictionary = {}
var events: Array = []


func _init(
	p_tick_index: int = 0,
	p_logic_time_ms: float = 0.0,
	p_actor_snapshots: Dictionary = {},
	p_events: Array = [],
) -> void:
	tick_index = p_tick_index
	logic_time_ms = p_logic_time_ms
	actor_snapshots = p_actor_snapshots
	events = p_events
