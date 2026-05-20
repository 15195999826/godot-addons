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
##
## §0.4 execution_state: 同一 AbilityExecutionInstance 共享的 transient scratchpad
## (CAST 阶段写, HIT 阶段读); ExecutionContext 不拥有这份字典, 只是引用入口。
## 详见 phase-00-infrastructure.md §0.4。

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

## §0.4 同一 AbilityExecutionInstance 共享的 transient scratchpad 引用
##
## 注意:
## - owner 是 AbilityExecutionInstance, ExecutionContext 只持有引用,不持有 ownership。
## - 不同 execution 之间天然隔离 (每次施法新 instance 新字典)。
## - 跨 tag 共享: CAST 阶段 ctx.set_execution_state(...), HIT 阶段 ctx.get_execution_state(...)。
## - callback context 也携带同一引用 (create_callback_context 透传)。
## - key 必须带 namespace, set/get helper 内部 assert。
var execution_state: Dictionary


func _init(
	p_event_dict_chain: Array[Dictionary] = [],
	p_game_state_provider: Variant = null,
	p_event_collector: EventCollector = null,
	p_ability_ref: AbilityRef = null,
	p_execution_info: AbilityExecutionInfo = null,
	p_execution_state: Dictionary = {}
) -> void:
	event_dict_chain.assign(p_event_dict_chain)
	game_state_provider = p_game_state_provider
	event_collector = p_event_collector
	ability_ref = p_ability_ref
	execution_info = p_execution_info
	execution_state = p_execution_state


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


## §0.4: 写入 execution_state, key 必须包含 namespace (含 ".")
func set_execution_state(key: String, value: Variant) -> void:
	Log.assert_crash(key.find(".") > 0,
		"ExecutionContext",
		"execution_state key 必须带 namespace, e.g. 'shadow_step.teleport_success'; got '%s'" % key)
	execution_state[key] = value


## §0.4: 读取 execution_state, 找不到返回 fallback
func get_execution_state(key: String, fallback: Variant = null) -> Variant:
	Log.assert_crash(key.find(".") > 0,
		"ExecutionContext",
		"execution_state key 必须带 namespace; got '%s'" % key)
	return execution_state.get(key, fallback)


## 创建执行上下文
static func create(
	p_event_dict_chain: Array[Dictionary],
	p_game_state_provider: Variant,
	p_event_collector: EventCollector,
	p_ability_ref: AbilityRef = null,
	p_execution_info: AbilityExecutionInfo = null,
	p_execution_state: Dictionary = {}
) -> ExecutionContext:
	return ExecutionContext.new(
		p_event_dict_chain,
		p_game_state_provider,
		p_event_collector,
		p_ability_ref,
		p_execution_info,
		p_execution_state
	)


## 创建回调执行上下文
##
## 在原有上下文基础上追加新事件到事件链。
## 其他字段（game_state_provider, event_collector, ability_ref）保持不变。
## 注意：execution_info 不传递到回调上下文（回调不在 Timeline 执行流程中）。
## §0.4: execution_state 透传 — hook 内仍可读写本次 execution 的状态。
static func create_callback_context(ctx: ExecutionContext, callback_event_dict: Dictionary) -> ExecutionContext:
	var new_chain: Array[Dictionary] = []
	new_chain.assign(ctx.event_dict_chain)
	new_chain.append(callback_event_dict)
	return ExecutionContext.new(
		new_chain,
		ctx.game_state_provider,
		ctx.event_collector,
		ctx.ability_ref,
		null,  # 回调上下文不继承 execution_info
		ctx.execution_state  # §0.4: 携带同一份引用
	)
