class_name TagAction
extends RefCounted

## 永久标签的 duration 值（不会自动过期）
const PERMANENT_DURATION := -1.0
## 移除全部层数的 stacks 值
const REMOVE_ALL_STACKS := -1

static func _get_ability_set_for_target(_ctx: ExecutionContext, target_id: String) -> AbilitySet:
	var actor := GameWorld.get_actor(target_id)
	return IAbilitySetOwner.get_ability_set(actor)

static func _get_logic_time(ctx: ExecutionContext) -> float:
	var event := ctx.get_current_event()
	if event.has("logicTime") and typeof(event["logicTime"]) in [TYPE_INT, TYPE_FLOAT]:
		return float(event["logicTime"])
	return IGameStateProvider.get_logic_time(ctx.game_state_provider)

class ApplyTagAction:
	extends Action.BaseAction

	var tag: String
	var _duration: FloatResolver
	var _stacks: IntResolver

	## 构造函数
	## @param target_selector: 目标选择器
	## @param tag_name: 标签名称
	## @param stacks_count: 层数解析器（默认 1）
	## @param tag_duration: 持续时间解析器（默认永久，使用 PERMANENT_DURATION）
	func _init(
		target_selector: TargetSelector,
		tag_name: String,
		stacks_count: IntResolver = Resolvers.int_val(1),
		tag_duration: FloatResolver = Resolvers.float_val(PERMANENT_DURATION)
	) -> void:
		super._init(target_selector)
		type = "applyTag"
		tag = tag_name
		_stacks = stacks_count
		_duration = tag_duration

	func execute(ctx: ExecutionContext) -> ActionResult:
		var targets := get_targets(ctx)
		var duration_value := _duration.resolve(ctx)
		var stacks_value := _stacks.resolve(ctx)
		for target_id in targets:
			var ability_set := TagAction._get_ability_set_for_target(ctx, target_id)
			if ability_set == null:
				Log.debug("TagAction", "ApplyTagAction: 无法获取 AbilitySet")
				continue
			if duration_value > 0.0:
				ability_set.add_auto_duration_tag(tag, duration_value)
			else:
				ability_set.add_loose_tag(tag, stacks_value)
		return ActionResult.create_success_result([])

class RemoveTagAction:
	extends Action.BaseAction

	var tag: String
	var _stacks: IntResolver

	## 构造函数
	## @param target_selector: 目标选择器
	## @param tag_name: 标签名称
	## @param stacks_count: 要移除的层数解析器（默认移除全部，使用 REMOVE_ALL_STACKS）
	func _init(
		target_selector: TargetSelector,
		tag_name: String,
		stacks_count: IntResolver = Resolvers.int_val(REMOVE_ALL_STACKS)
	) -> void:
		super._init(target_selector)
		type = "removeTag"
		tag = tag_name
		_stacks = stacks_count

	func execute(ctx: ExecutionContext) -> ActionResult:
		var targets := get_targets(ctx)
		var stacks_value := _stacks.resolve(ctx)
		for target_id in targets:
			var ability_set := TagAction._get_ability_set_for_target(ctx, target_id)
			if ability_set == null:
				Log.debug("TagAction", "RemoveTagAction: 无法获取 AbilitySet")
				continue
			ability_set.remove_loose_tag(tag, stacks_value)
		return ActionResult.create_success_result([])

class HasTagAction:
	extends Action.BaseAction

	var tag: String
	var then_actions: Array[Action.BaseAction] = []
	var else_actions: Array[Action.BaseAction] = []

	## 构造函数
	## @param target_selector: 目标选择器
	## @param tag_name: 标签名称
	## @param then_action_list: 有标签时执行的 Action 列表
	## @param else_action_list: 无标签时执行的 Action 列表
	func _init(
		target_selector: TargetSelector,
		tag_name: String,
		then_action_list: Array[Action.BaseAction] = [],
		else_action_list: Array[Action.BaseAction] = []
	) -> void:
		super._init(target_selector)
		type = "hasTag"
		tag = tag_name
		then_actions.assign(then_action_list)
		else_actions.assign(else_action_list)

	## 重写 _freeze 以冻结嵌套 Action
	func _freeze() -> void:
		super._freeze()
		for action in then_actions:
			action._freeze()
		for action in else_actions:
			action._freeze()

	func execute(ctx: ExecutionContext) -> ActionResult:
		Log.debug("TagAction", "HasTagAction 多目标行为可能非预期")
		var targets := get_targets(ctx)
		var all_events: Array[Dictionary] = []
		for target_id in targets:
			var ability_set := TagAction._get_ability_set_for_target(ctx, target_id)
			if ability_set == null:
				continue
			var has_tag := ability_set.has_tag(tag)
			var actions: Array[Action.BaseAction] = then_actions if has_tag else else_actions
			for action in actions:
				var result: ActionResult = action.execute(ctx)
				action._verify_unchanged()
				if result != null and result.event_dicts is Array:
					all_events.append_array(result.event_dicts)
		return ActionResult.create_success_result(all_events)
