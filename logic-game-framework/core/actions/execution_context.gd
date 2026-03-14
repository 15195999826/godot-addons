class_name ExecutionContext
extends RefCounted

## 执行上下文
##
## Action 执行时的上下文信息，仅存在于 Action 链执行流程中。
##
## 设计原则：
## - 输入：event_dict_chain, game_state_provider, ability_ref
## - 输出：event_collector
##
## 事件链（字典形式）：
## [code]
## [
##     # event_dict_chain[0] - 原始触发事件（技能激活）
##     { "kind": "abilityActivate", "abilityInstanceId": "skill_001", "sourceId": "actor_001" },
##     # event_dict_chain[1] - 回调事件（伤害事件）
##     { "kind": "damage", "target_actor_id": "actor_002", "damage": 150.0 }
## ]
## [/code]
##
## 转换为强类型事件：
## [code]
## var event_dict := ctx.get_current_event()
## if BattleEvents.DamageEvent.is_match(event_dict):
##     var event := BattleEvents.DamageEvent.from_dict(event_dict)
##     print(event.damage)  # 类型安全访问
## [/code]

## 触发事件链（字典形式），记录从原始触发事件到当前回调事件的完整链路。
## 每个元素是 GameEvent.to_dict() 的结果。
var event_dict_chain: Array[Dictionary] = []

## 游戏状态提供者（项目层实现）
var game_state_provider: Variant = null

## 事件收集器
var event_collector: EventCollector = null

## 触发此 Action 的能力引用（可选）
var ability_ref: AbilityRef = null

## 执行实例信息（可选，当 Action 由 AbilityExecutionInstance 触发时存在）
var execution_info: AbilityExecutionInfo = null


func _init(
	p_event_dict_chain: Array[Dictionary] = [],
	p_game_state_provider: Variant = null,
	p_event_collector: EventCollector = null,
	p_ability_ref: AbilityRef = null,
	p_execution_info: AbilityExecutionInfo = null
) -> void:
	event_dict_chain.assign(p_event_dict_chain)
	game_state_provider = p_game_state_provider
	event_collector = p_event_collector
	ability_ref = p_ability_ref
	execution_info = p_execution_info


## 获取当前触发事件（事件链的最后一个元素）
## 无事件时返回空字典，调用方通过 .has() / .is_empty() 判断。
func get_current_event() -> Dictionary:
	if event_dict_chain.is_empty():
		return {}
	return event_dict_chain.back()


## 获取原始触发事件（事件链的第一个元素）
## 无事件时返回空字典，调用方通过 .has() / .is_empty() 判断。
func get_original_event() -> Dictionary:
	if event_dict_chain.is_empty():
		return {}
	return event_dict_chain.front()


## 推送事件到收集器
func push_event(event_dict: Dictionary) -> Dictionary:
	return event_collector.push(event_dict)


## 创建执行上下文
static func create(
	p_event_dict_chain: Array[Dictionary],
	p_game_state_provider: Variant,
	p_event_collector: EventCollector,
	p_ability_ref: AbilityRef = null,
	p_execution_info: AbilityExecutionInfo = null
) -> ExecutionContext:
	return ExecutionContext.new(
		p_event_dict_chain,
		p_game_state_provider,
		p_event_collector,
		p_ability_ref,
		p_execution_info
	)


## 创建回调执行上下文
##
## 在原有上下文基础上追加新事件到事件链。
## 其他字段（game_state_provider, event_collector, ability_ref）保持不变。
## 注意：execution_info 不传递到回调上下文（回调不在 Timeline 执行流程中）。
static func create_callback_context(ctx: ExecutionContext, callback_event_dict: Dictionary) -> ExecutionContext:
	var new_chain: Array[Dictionary] = []
	new_chain.assign(ctx.event_dict_chain)
	new_chain.append(callback_event_dict)
	return ExecutionContext.new(
		new_chain,
		ctx.game_state_provider,
		ctx.event_collector,
		ctx.ability_ref,
		null  # 回调上下文不继承 execution_info
	)
