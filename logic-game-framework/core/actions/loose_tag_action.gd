## LooseTagAction - 只承载 loose tag mutation
##
## §0.1: 旧 TagAction 名字过宽（Apply/Remove 改 loose tag，Has 又读聚合 tag，语义混合）。
## V1 收敛: 新代码使用 LooseTagAction.Apply / LooseTagAction.Remove，明确只动 loose tag。
##
## 不处理 auto-duration tag (那是 buff/duration ability 的语义), 不处理 component tag
## (那由 TagComponentConfig + TagComponent 在 Ability 生命周期内自动管理).
##
## 聚合 tag 查询继续用 Condition.HasTagCondition / NoTagCondition (主动技能条件入口) 或
## FlowAction.if_ predicate (action flow 内分支判断)。
##
## 用法:
##     LooseTagAction.Apply.new(target_selector, "stance:wrath")
##     LooseTagAction.Remove.new(target_selector, "stance:wrath")
class_name LooseTagAction
extends RefCounted


const REMOVE_ALL_STACKS := -1


static func _get_ability_set(target_id: String) -> AbilitySet:
	var actor := GameWorld.get_actor(target_id)
	return IAbilitySetOwner.get_ability_set(actor)


class Apply:
	extends Action.PrimitiveAction

	var tag: String
	var _stacks: IntResolver

	func _init(
		target_selector: TargetSelector,
		tag_name: String,
		stacks_count: IntResolver = Resolvers.int_val(1)
	) -> void:
		super._init(target_selector)
		type = "looseTagApply"
		tag = tag_name
		_stacks = stacks_count

	func execute(ctx: ExecutionContext) -> ActionResult:
		var stacks_value := _stacks.resolve(ctx)
		for target_id in get_targets(ctx):
			var ability_set := LooseTagAction._get_ability_set(target_id)
			if ability_set == null:
				Log.debug("LooseTagAction.Apply", "无法获取 AbilitySet target=%s" % target_id)
				continue
			ability_set.add_loose_tag(tag, stacks_value)
		return ActionResult.create_success_result([])


class Remove:
	extends Action.PrimitiveAction

	var tag: String
	var _stacks: IntResolver

	func _init(
		target_selector: TargetSelector,
		tag_name: String,
		stacks_count: IntResolver = Resolvers.int_val(REMOVE_ALL_STACKS)
	) -> void:
		super._init(target_selector)
		type = "looseTagRemove"
		tag = tag_name
		_stacks = stacks_count

	func execute(ctx: ExecutionContext) -> ActionResult:
		var stacks_value := _stacks.resolve(ctx)
		for target_id in get_targets(ctx):
			var ability_set := LooseTagAction._get_ability_set(target_id)
			if ability_set == null:
				Log.debug("LooseTagAction.Remove", "无法获取 AbilitySet target=%s" % target_id)
				continue
			ability_set.remove_loose_tag(tag, stacks_value)
		return ActionResult.create_success_result([])
