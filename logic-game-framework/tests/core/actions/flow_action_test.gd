extends Node

## §0.2 FlowAction.if_ 单测
##
## 合同断言:
## 1. predicate 返回 true → 执行 then_actions
## 2. predicate 返回 false → 执行 else_actions
## 3. then_actions / else_actions 为空数组 (no-op branch) 合法
## 4. predicate 返回非 bool → Log.assert_crash (不测，crash 难以 catch)
## 5. child action failure → 当前 branch 早停 + 返回 failure result
## 6. nested action freeze: get_child_actions 包含所有 child


class FixedSelector extends TargetSelector:
	var _targets: Array[String] = []

	func _init(targets: Array[String]) -> void:
		_targets = targets

	func select(_ctx: ExecutionContext) -> Array[String]:
		return _targets


class RecordingAction:
	extends Action.PrimitiveAction

	var calls: Array[String] = []
	var tag: String
	var should_fail: bool = false

	func _init(p_tag: String, p_should_fail: bool = false) -> void:
		super._init(FixedSelector.new([]))
		tag = p_tag
		should_fail = p_should_fail
		type = "recording_" + p_tag

	func execute(_ctx: ExecutionContext) -> ActionResult:
		calls.append(tag)
		if should_fail:
			return ActionResult.create_failure_result("intentional", [])
		return ActionResult.create_success_result([{ "kind": tag, "tag": tag }])


func _ctx() -> ExecutionContext:
	return ExecutionContext.create([{"kind":"test"}], null, GameWorld.event_collector, null, null)


func _init() -> void:
	TestFramework.register_test("FlowAction.if_ true path runs then_actions only", _test_then_branch)
	TestFramework.register_test("FlowAction.if_ false path runs else_actions only", _test_else_branch)
	TestFramework.register_test("FlowAction.if_ empty branch is valid (no-op)", _test_empty_branch)
	TestFramework.register_test("FlowAction.if_ child failure halts current branch", _test_child_failure)
	TestFramework.register_test("FlowAction.if_ get_child_actions exposes both branches", _test_child_actions_for_freeze)


func _test_then_branch() -> void:
	var then_act := RecordingAction.new("then")
	var else_act := RecordingAction.new("else")
	var then_arr: Array[Action.BaseAction] = [then_act]
	var else_arr: Array[Action.BaseAction] = [else_act]
	var flow := FlowAction.if_(func(_c): return true, then_arr, else_arr)
	var result := flow.execute(_ctx())
	TestFramework.assert_true(result.success)
	TestFramework.assert_equal("then", str(result.data.get("branch", "")))
	TestFramework.assert_equal(1, then_act.calls.size())
	TestFramework.assert_equal(0, else_act.calls.size())


func _test_else_branch() -> void:
	var then_act := RecordingAction.new("then")
	var else_act := RecordingAction.new("else")
	var then_arr: Array[Action.BaseAction] = [then_act]
	var else_arr: Array[Action.BaseAction] = [else_act]
	var flow := FlowAction.if_(func(_c): return false, then_arr, else_arr)
	var result := flow.execute(_ctx())
	TestFramework.assert_true(result.success)
	TestFramework.assert_equal("else", str(result.data.get("branch", "")))
	TestFramework.assert_equal(0, then_act.calls.size())
	TestFramework.assert_equal(1, else_act.calls.size())


func _test_empty_branch() -> void:
	var then_act := RecordingAction.new("then")
	var then_arr: Array[Action.BaseAction] = [then_act]
	# else 留空,只测 false predicate 走空 branch
	var flow := FlowAction.if_(func(_c): return false, then_arr)
	var result := flow.execute(_ctx())
	TestFramework.assert_true(result.success, "empty else branch should succeed silently")
	TestFramework.assert_equal(0, then_act.calls.size())
	TestFramework.assert_equal(0, result.event_dicts.size())


func _test_child_failure() -> void:
	var fail_act := RecordingAction.new("fail_first", true)
	var after_act := RecordingAction.new("after")
	var then_arr: Array[Action.BaseAction] = [fail_act, after_act]
	var flow := FlowAction.if_(func(_c): return true, then_arr)
	var result := flow.execute(_ctx())
	TestFramework.assert_true(not result.success, "failure should propagate")
	TestFramework.assert_equal(1, fail_act.calls.size())
	TestFramework.assert_true(after_act.calls.size() == 0,
		"branch should halt at first child failure")


func _test_child_actions_for_freeze() -> void:
	var t1 := RecordingAction.new("t1")
	var t2 := RecordingAction.new("t2")
	var e1 := RecordingAction.new("e1")
	var then_arr: Array[Action.BaseAction] = [t1, t2]
	var else_arr: Array[Action.BaseAction] = [e1]
	var flow := FlowAction.if_(func(_c): return true, then_arr, else_arr)
	var children := flow.get_child_actions()
	TestFramework.assert_true(children.size() == 3,
		"both branches' children should be enumerated for freeze, got %d" % children.size())
	# 确认 _freeze 不抛
	flow._freeze()
	flow._verify_unchanged()
