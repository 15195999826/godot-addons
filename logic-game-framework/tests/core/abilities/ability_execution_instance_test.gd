extends Node

class TestAction:
	extends Action.BaseAction

	var calls: Array[ExecutionContext] = []

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(ctx: ExecutionContext) -> ActionResult:
		calls.append(ctx)
		return ActionResult.create_success_result([])

func _init() -> void:
	TestFramework.register_test("AbilityExecutionInstance fires sync + async actions", _test_trigger_tags)
	TestFramework.register_test("AbilityExecutionInstance matches wildcard", _test_wildcard)
	TestFramework.register_test("AbilityExecutionInstance completes and cancels", _test_complete_cancel)

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
		null,
		AbilityRef.new("a1", "c1")
	)

	# 模拟 ability.activate_new_execution_instance 的同步触发
	instance.fire_sync_actions(sync_list, "__timeline_start__")
	TestFramework.assert_equal(1, sync_action.calls.size())
	TestFramework.assert_equal(0, async_action.calls.size())

	# 异步 tag：tick 到 0.5 时触发 impact
	var triggered := instance.tick(0.5)
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
		null,
		AbilityRef.new("a2", "c2")
	)

	var triggered := instance.tick(0.2)
	TestFramework.assert_equal(1, triggered.size())
	TestFramework.assert_equal("hit-1", triggered[0])
	TestFramework.assert_equal(1, action.calls.size())

func _test_complete_cancel() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-complete",
		0.1,
		{}
	))

	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-complete", [], empty_list, empty_list, {}, null, AbilityRef.new()
	)

	TestFramework.assert_true(instance.is_executing())
	instance.tick(0.1)
	TestFramework.assert_true(instance.is_completed())

	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(
		"t-cancel",
		1.0,
		{}
	))

	var cancelled := AbilityExecutionInstance.new(
		"t-cancel", [], empty_list, empty_list, {}, null, AbilityRef.new()
	)
	cancelled.cancel()
	TestFramework.assert_true(cancelled.is_cancelled())
