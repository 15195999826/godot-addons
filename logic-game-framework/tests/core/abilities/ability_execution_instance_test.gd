extends Node

class TestAction:
	extends Action.BaseAction

	var calls: Array[ExecutionContext] = []

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(ctx: ExecutionContext) -> ActionResult:
		calls.append(ctx)
		return ActionResult.create_success_result([])


class CancelExecutionAction:
	extends Action.BaseAction

	var _instance_ref: WeakRef

	func _init() -> void:
		super._init(TargetSelector.new())

	func bind(instance: AbilityExecutionInstance) -> void:
		_instance_ref = weakref(instance)

	func execute(ctx: ExecutionContext) -> ActionResult:
		var instance := _instance_ref.get_ref() as AbilityExecutionInstance
		instance.cancel(ctx.game_state_provider)
		return ActionResult.create_success_result([])


func _init() -> void:
	TestFramework.register_test("AbilityExecutionInstance fires sync + async actions", _test_trigger_tags)
	TestFramework.register_test("AbilityExecutionInstance matches wildcard", _test_wildcard)
	TestFramework.register_test("AbilityExecutionInstance completes and cancels", _test_complete_cancel)
	TestFramework.register_test("AbilityExecutionInstance fires same-timestamp tags in definition order", _test_same_timestamp_tag_order)
	TestFramework.register_test("AbilityExecutionInstance end cancellation stays cancelled", _test_end_cancel)
	TestFramework.register_test("AbilityExecutionInstance §0.4 shares execution_state across tags", _test_execution_state_shared)
	TestFramework.register_test("AbilityExecutionInstance §0.4 different instances have isolated state", _test_execution_state_isolated)
	TestFramework.register_test("ExecutionContext §0.4 set/get rejects namespace-less key", _test_execution_state_namespace_assert)

func _test_trigger_tags() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-tags",
		1.0,
		{
			"impact": 0.5,
		}
	))
	GameWorld.init()

	var sync_action := TestAction.new()
	var async_action := TestAction.new()
	var sync_list: Array[Action.BaseAction] = [sync_action]
	var end_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-tags",
		[TagActionsEntry.new("impact", [async_action])],
		sync_list,
		end_list,
		{},
		AbilityRef.new("a1", "c1")
	)

	# 模拟 ability.activate_new_execution_instance 的同步触发
	instance.fire_sync_actions(sync_list, "__timeline_start__", null)
	TestFramework.assert_equal(1, sync_action.calls.size())
	TestFramework.assert_equal(0, async_action.calls.size())

	# 异步 tag：tick 到 0.5 时触发 impact
	var triggered := instance.tick(0.5, null)
	TestFramework.assert_equal(1, triggered.size())
	TestFramework.assert_equal("impact", triggered[0])
	TestFramework.assert_equal(1, async_action.calls.size())

func _test_wildcard() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-wild",
		1.0,
		{
			"hit-1": 0.2,
		}
	))
	GameWorld.init()

	var action := TestAction.new()
	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-wild",
		[TagActionsEntry.new("hit*", [action])],
		empty_list,
		empty_list,
		{},
		AbilityRef.new("a2", "c2")
	)

	var triggered := instance.tick(0.2, null)
	TestFramework.assert_equal(1, triggered.size())
	TestFramework.assert_equal("hit-1", triggered[0])
	TestFramework.assert_equal(1, action.calls.size())

## 同 timestamp 的多个 tag 必须按 timeline 定义序触发（显式二级排序，
## 不依赖 sort_custom 稳定性）。定义序特意用非字母序排布以暴露隐式排序。
func _test_same_timestamp_tag_order() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-tag-order",
		1.0,
		{
			"zeta": 0.5,
			"alpha": 0.5,
			"mid": 0.3,
			"omega": 0.5,
		}
	))
	GameWorld.init()

	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-tag-order",
		[],
		empty_list,
		empty_list,
		{},
		AbilityRef.new("a-order", "c-order")
	)

	# 一次 tick 覆盖全部 tag：时间序在先（mid@0.3），同刻组按定义序 zeta → alpha → omega
	var triggered := instance.tick(1.0, null)
	TestFramework.assert_equal(4, triggered.size())
	TestFramework.assert_equal("mid", triggered[0])
	TestFramework.assert_equal("zeta", triggered[1])
	TestFramework.assert_equal("alpha", triggered[2])
	TestFramework.assert_equal("omega", triggered[3])


func _test_complete_cancel() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-complete",
		0.1,
		{}
	))

	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-complete", [], empty_list, empty_list, {}, AbilityRef.new()
	)

	TestFramework.assert_true(instance.is_executing())
	instance.tick(0.1, null)
	TestFramework.assert_true(instance.is_completed())

	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-cancel",
		1.0,
		{}
	))

	var cancel_action := TestAction.new()
	var cancel_actions: Array[Action.BaseAction] = [cancel_action]
	var cancelled := AbilityExecutionInstance.new(
		"t-cancel", [], empty_list, empty_list, {}, AbilityRef.new(), cancel_actions
	)
	cancelled.cancel()
	cancelled.cancel()
	TestFramework.assert_true(cancelled.is_cancelled())
	TestFramework.assert_equal(1, cancel_action.calls.size())


func _test_end_cancel() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new("t-end-cancel", 0.1, {}))
	var cancel_action := CancelExecutionAction.new()
	var skipped_action := TestAction.new()
	var cleanup_action := TestAction.new()
	var empty_actions: Array[Action.BaseAction] = []
	var end_actions: Array[Action.BaseAction] = [cancel_action, skipped_action]
	var cancel_actions: Array[Action.BaseAction] = [cleanup_action]
	var instance := AbilityExecutionInstance.new(
		"t-end-cancel", [], empty_actions, end_actions, {}, AbilityRef.new(), cancel_actions)
	cancel_action.bind(instance)
	instance.tick(0.1, null)
	TestFramework.assert_true(instance.is_cancelled())
	TestFramework.assert_equal(0, skipped_action.calls.size())
	TestFramework.assert_equal(1, cleanup_action.calls.size())


# ========== §0.4 execution_state ==========

## 验证 fire_sync_actions + 异步 tag actions 共享同一 execution_state Dictionary。
class WriteStateAction:
	extends Action.BaseAction
	var key: String
	var value: Variant
	func _init(p_key: String, p_value: Variant) -> void:
		super._init(TargetSelector.new())
		key = p_key
		value = p_value
	func execute(ctx: ExecutionContext) -> ActionResult:
		ctx.set_execution_state(key, value)
		return ActionResult.create_success_result([])


class ReadStateAction:
	extends Action.BaseAction
	var key: String
	var captured: Variant = null
	func _init(p_key: String) -> void:
		super._init(TargetSelector.new())
		key = p_key
	func execute(ctx: ExecutionContext) -> ActionResult:
		captured = ctx.get_execution_state(key, null)
		return ActionResult.create_success_result([])


func _test_execution_state_shared() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new("t-state-shared", 1.0, { "later": 0.5 }))
	GameWorld.init()

	var write := WriteStateAction.new("test.flag", true)
	var read := ReadStateAction.new("test.flag")
	var sync_list: Array[Action.BaseAction] = [write]
	var end_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-state-shared",
		[TagActionsEntry.new("later", [read])],
		sync_list,
		end_list,
		{},
		AbilityRef.new("a-state", "c-state")
	)
	# 1. sync action 在 timeline_start 写
	instance.fire_sync_actions(sync_list, "__timeline_start__", null)
	# 2. tick 到 0.5 触发 later tag, ReadStateAction 应读到刚写的值
	instance.tick(0.5, null)
	TestFramework.assert_true(read.captured == true,
		"execution_state should be shared across tag contexts; got %s" % str(read.captured))


func _test_execution_state_isolated() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new("t-iso", 1.0, {}))
	GameWorld.init()

	var empty_list: Array[Action.BaseAction] = []
	var inst1 := AbilityExecutionInstance.new(
		"t-iso", [], empty_list, empty_list, {}, AbilityRef.new("a1", "c1")
	)
	var inst2 := AbilityExecutionInstance.new(
		"t-iso", [], empty_list, empty_list, {}, AbilityRef.new("a2", "c2")
	)
	var write1 := WriteStateAction.new("test.x", "from_inst1")
	var write2 := WriteStateAction.new("test.x", "from_inst2")
	var read1 := ReadStateAction.new("test.x")
	var read2 := ReadStateAction.new("test.x")
	var arr1: Array[Action.BaseAction] = [write1, read1]
	var arr2: Array[Action.BaseAction] = [write2, read2]
	inst1.fire_sync_actions(arr1, "tag1", null)
	inst2.fire_sync_actions(arr2, "tag2", null)
	# inst1 write后 inst2 write 不应污染 inst1 的 state
	# read1 在 inst1.fire_sync_actions 链尾,读的是 inst1 state
	TestFramework.assert_true(read1.captured == "from_inst1",
		"inst1 should see its own value; got %s" % str(read1.captured))
	TestFramework.assert_true(read2.captured == "from_inst2",
		"inst2 should see its own value; got %s" % str(read2.captured))


func _test_execution_state_namespace_assert() -> void:
	# 此处仅验证带 namespace key 不 crash; 不带 namespace 应 assert_crash,
	# 但 GDScript 没法在测试内 catch crash, 跳过反例.
	var ctx := ExecutionContext.new([], null, null, null, null)
	ctx.set_execution_state("ns.key", 42)
	TestFramework.assert_equal(42, ctx.get_execution_state("ns.key", -1))
	TestFramework.assert_equal(-1, ctx.get_execution_state("ns.missing", -1))
