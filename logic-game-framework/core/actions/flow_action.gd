## FlowAction - 通用 Action flow 组合器
##
## §0.2: 当前只批准 `FlowAction.if_(predicate, then_actions, else_actions := [])`，
## 不扩展 sequence / DSL / VM。
##
## 合同:
## - predicate 必须 `func(ctx: ExecutionContext) -> bool`; 返回非 bool 时 Log.assert_crash。
## - then_actions / else_actions 允许为空数组 (no-op branch); 不需要额外占位 Action。
## - 只执行被选中 branch，按数组顺序执行 child actions。
## - child 必须经 Action.execute_child(self, child, ctx) 执行；child failure 早停并
##   返回 failure result，已产生的 event_dicts 保留在 failure 内。
## - ActionResult.data 只合并 FlowAction 自身元信息 ({ branch: "then"/"else" })。
class_name FlowAction
extends RefCounted


static func if_(
	predicate: Callable,
	then_actions: Array[Action.BaseAction],
	else_actions: Array[Action.BaseAction] = []
) -> Action.BaseAction:
	return IfAction.new(predicate, then_actions, else_actions)


class IfAction:
	extends Action.FlowActionBase

	var _predicate: Callable
	var _then_actions: Array[Action.BaseAction] = []
	var _else_actions: Array[Action.BaseAction] = []

	func _init(
		predicate: Callable,
		then_actions: Array[Action.BaseAction],
		else_actions: Array[Action.BaseAction] = []
	) -> void:
		super._init(TargetSelector.new())
		type = "flow_if"
		_predicate = predicate
		_then_actions.assign(then_actions)
		_else_actions.assign(else_actions)

	func get_child_actions() -> Array[Action.BaseAction]:
		var children: Array[Action.BaseAction] = []
		children.append_array(_then_actions)
		children.append_array(_else_actions)
		return children

	func execute(ctx: ExecutionContext) -> ActionResult:
		var predicate_result: Variant = _predicate.call(ctx)
		Log.assert_crash(predicate_result is bool,
			"FlowAction.if_",
			"predicate must return bool, got %s" % typeof(predicate_result))
		var passed: bool = predicate_result
		var actions := _then_actions if passed else _else_actions
		var all_events: Array[Dictionary] = []
		for child in actions:
			var result := Action.execute_child(self, child, ctx)
			if result.event_dicts is Array:
				all_events.append_array(result.event_dicts)
			if not result.success:
				return ActionResult.create_failure_result(result.failure_reason, all_events)
		return ActionResult.create_success_result(all_events, { "branch": "then" if passed else "else" })
