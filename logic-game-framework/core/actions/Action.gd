class_name Action
extends RefCounted

## Action 两类合同
##
## | 类 | 基类 | 用途 | 放哪 |
## |---|---|---|---|
## | 公共原语 | Action.BaseAction | 通用积木（伤害 / 治疗 / 上 buff / 发射投射物 / loose tag / stage cue / FlowAction.if_ …），不知道具体技能 | 公共 action 目录，带 class_name |
## | 技能私有 | Action.SkillLocalAction | 只服务一个 ability 的过程步骤，运行时 assert owner config_id | 内嵌在该技能文件里，不得 class_name |
##
## 最底层的结算 / 副作用函数是 Util，不是 Action 子类。目录规则见 enforcing-lgf/SKILL.md §8。


class BaseAction:
	extends RefCounted

	var type: String = "base"
	var _target_selector: TargetSelector
	var _frozen_hash: int = 0

	## 子类必须调用 super._init(target_selector)
	func _init(target_selector: TargetSelector) -> void:
		_target_selector = target_selector

	func execute(_ctx: ExecutionContext) -> ActionResult:
		return ActionResult.create_success_result([])

	func get_targets(ctx: ExecutionContext) -> Array[String]:
		return _target_selector.select(ctx)

	## 持有 child actions 的 Action 必须重写此方法返回所有 child action 引用。
	## 默认返回空数组；framework 会通过它统一处理 freeze。
	func get_child_actions() -> Array[BaseAction]:
		return []

	## 冻结 Action，记录当前状态 hash；自动同时冻结 child actions
	func _freeze() -> void:
		_frozen_hash = StateCheck.freeze(self)
		for child in get_child_actions():
			child._freeze()

	## 验证状态未被修改
	func _verify_unchanged() -> void:
		StateCheck.verify(self, _frozen_hash, "Action")


class NoopAction:
	extends BaseAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector)
		type = "noop"

	func execute(_ctx: ExecutionContext) -> ActionResult:
		return ActionResult.create_success_result([])


## SkillLocalAction: 技能私有过程函数
##
## 只服务一个 Ability，运行时 assert 当前 ability config_id 匹配 owner_config_id。
## 不用 class_name，作为内嵌 class 写在技能 / buff 文件内。
class SkillLocalAction:
	extends BaseAction

	var owner_config_id: String = ""

	func _init(target_selector: TargetSelector, p_owner_config_id: String) -> void:
		super._init(target_selector)
		Log.assert_crash(not p_owner_config_id.is_empty(),
			"Action.SkillLocalAction", "owner_config_id must not be empty")
		owner_config_id = p_owner_config_id
		type = "skill_local"

	func execute(ctx: ExecutionContext) -> ActionResult:
		var current_config_id := ctx.ability_ref.config_id if ctx.ability_ref != null else ""
		Log.assert_crash(current_config_id == owner_config_id,
			"Action.SkillLocalAction",
			"owner_config_id mismatch: expected %s, got %s" % [owner_config_id, current_config_id])
		return _execute_local(ctx)

	## 子类重写
	func _execute_local(_ctx: ExecutionContext) -> ActionResult:
		return ActionResult.create_success_result([])


## 统一的 child action 执行入口
##
## FlowAction / hook / composite 调用 child action 必须经此 helper:
## - 执行 child.execute(ctx)
## - 自动 _verify_unchanged()
## - 返回 ActionResult (永不为 null)
##
## 禁止各处手写 child.execute() 漏 verify_unchanged。
static func execute_child(_parent_action: BaseAction, child_action: BaseAction, ctx: ExecutionContext) -> ActionResult:
	Log.assert_crash(child_action != null, "Action.execute_child", "child_action must not be null")
	var result: ActionResult = child_action.execute(ctx)
	child_action._verify_unchanged()
	if result == null:
		return ActionResult.create_success_result([])
	return result
