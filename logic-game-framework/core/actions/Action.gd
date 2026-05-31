class_name Action
extends RefCounted

## Action 分层合同
##
## Action 体系按四层理解和约束（详见 docs/reference/action-architecture.md）:
##
## | 层 | 基类 | 是否可进 timeline | 用途 |
## |---|---|---|---|
## | Util / Utils | (不是 Action 子类) | 否 | 最底层结算 / 副作用函数 |
## | Primitive Action | Action.PrimitiveAction | 是 | 公开领域原语 adapter |
## | FlowAction | Action.FlowActionBase | 是 | 流程组合器,只组织 child actions |
## | SkillLocalAction | Action.SkillLocalAction | 是 | 技能私有过程函数,运行时 assert owner |
##
## 新增 Action 必须选择更具体的语义基类，禁止应用层直接 extends Action.BaseAction。
## 历史既有 Action 走 allowlist (见 tests/core/actions/action_architecture_validator_test.gd)。


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


## Primitive Action: 公开领域原语 adapter
##
## 薄封装 target selector / resolver / util；不知道具体技能。
## 必须登记在 public primitive allowlist（见 validator test）。
## 例: DamageAction / LaunchProjectileAction / ApplyBuffAction / LooseTagAction。
class PrimitiveAction:
	extends BaseAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector)
		type = "primitive"


## FlowAction 基类: 流程组合器
##
## 只能组织 child actions、不承载业务语义。当前只批准 FlowAction.if_。
## 子类必须重写 get_child_actions() 返回所有 child 引用以参与 _freeze()。
class FlowActionBase:
	extends BaseAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector)
		type = "flow"


## SkillLocalAction: 技能私有过程函数
##
## 只服务一个 Ability，运行时 assert 当前 ability config_id 匹配 owner_config_id。
## 不允许使用 class_name (validator 强制)，应作为内嵌 class 写在技能/buff 文件内。
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
