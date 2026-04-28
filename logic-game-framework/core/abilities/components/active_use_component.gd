class_name ActiveUseComponent
extends ActivateInstanceComponent
## 主动使用组件：在 ActivateInstanceComponent 的 trigger → execute 流程中，
## 插入 Condition 检查和 Cost 扣除。
##
## 继承关系说明：
## ActiveUse "是一个" ActivateInstance —— 带有额外前置校验的触发执行组件。
## 父类的 _check_triggers()、_activate_execution()、serialize() 等逻辑被完整复用，
## on_event() 仅在 trigger 通过与 execute 之间增加 conditions/costs 管道。

const COMPONENT_TYPE := "ActiveUseComponent"

var _conditions: Array[Condition] = []
var _costs: Array[Cost] = []

func _init(config: ActiveUseConfig):
	# 构建父类配置
	var triggers_to_use: Array[TriggerConfig] = []
	if not config.triggers.is_empty():
		triggers_to_use.assign(config.triggers)
	else:
		triggers_to_use = [TriggerConfig.ABILITY_ACTIVATE]
	var parent_config := ActivateInstanceConfig.new(
		config.timeline_id,
		config.tag_actions,
		triggers_to_use,
		config.trigger_mode,
		config.on_timeline_start_actions,
		config.on_timeline_end_actions
	)
	super._init(parent_config)
	type = COMPONENT_TYPE
	_conditions.assign(config.conditions)
	_costs.assign(config.costs)
	# Debug: 冻结所有 Condition 和 Cost，检测无状态约束
	_freeze_conditions_and_costs()


func on_event(event_dict: Dictionary, context: AbilityLifecycleContext, game_state_provider: Variant) -> bool:
	if not _check_triggers(event_dict, context):
		return false
	if not _check_conditions(context, event_dict, game_state_provider):
		return false
	if not _check_costs(context, event_dict, game_state_provider):
		return false
	_pay_costs(context, event_dict, game_state_provider)
	_activate_execution(event_dict, context, game_state_provider)
	return true

func _check_conditions(ctx: AbilityLifecycleContext, event_dict: Dictionary, game_state: Variant) -> bool:
	for condition in _conditions:
		if not condition.check(ctx, event_dict, game_state):
			var reason := condition.get_fail_reason(ctx, event_dict, game_state)
			if reason == "":
				reason = condition.get_condition_type()
			Log.debug("ActiveUseComponent", "条件不满足: %s" % reason)
			_push_activate_failed(ctx, event_dict, reason, "condition")
			# Debug: 验证 Condition 状态未被修改
			condition._verify_unchanged()
			return false
		# Debug: 验证 Condition 状态未被修改
		condition._verify_unchanged()
	return true

func _check_costs(ctx: AbilityLifecycleContext, event_dict: Dictionary, game_state: Variant) -> bool:
	for cost in _costs:
		if not cost.can_pay(ctx, event_dict, game_state):
			var reason := cost.get_fail_reason(ctx, event_dict, game_state)
			if reason == "":
				reason = cost.type
			Log.debug("ActiveUseComponent", "消耗不足: %s" % reason)
			_push_activate_failed(ctx, event_dict, reason, "cost")
			# Debug: 验证 Cost 状态未被修改（can_pay 不应修改状态）
			cost._verify_unchanged()
			return false
		# Debug: 验证 Cost 状态未被修改
		cost._verify_unchanged()
	return true


## condition / cost 失败时 push AbilityActivateFailed 事件到 event_collector,
## 让 recorder 收录、前端 console 渲染、SkillPreview 显示"释放失败 + reason"。
##
## 仅在 trigger 已匹配后才会进到 _check_conditions/_check_costs, 所以本事件
## 只代表"已匹配 trigger 的本 ability 被 condition/cost 拦截", 不会被无关
## ability 的 trigger miss 误触发。
##
## reason 由 example 层 condition.get_fail_reason / cost.get_fail_reason 提供
## (LGF core 不知道"冷却"/"mp 不足", 只搬运字符串)。
func _push_activate_failed(
	ctx: AbilityLifecycleContext, event_dict: Dictionary,
	reason: String, failed_component_type: String,
) -> void:
	var ability := ctx.ability
	if ability == null:
		return
	GameWorld.event_collector.push(GameEvent.AbilityActivateFailed.create(
		ability.id,
		ability.config_id,
		ctx.owner_actor_id,
		String(event_dict.get("target_actor_id", "")),
		reason,
		failed_component_type,
	).to_dict())

func _pay_costs(ctx: AbilityLifecycleContext, event_dict: Dictionary, game_state: Variant) -> void:
	for cost in _costs:
		cost.pay(ctx, event_dict, game_state)
		# Debug: 验证 Cost 状态未被修改（pay 不应修改 self）
		cost._verify_unchanged()

## Debug: 冻结所有 Condition 和 Cost，用于检测无状态约束
func _freeze_conditions_and_costs() -> void:
	for condition in _conditions:
		condition._freeze()
	for cost in _costs:
		cost._freeze()
