extends Node

## Timeline loop 行为测试
##
## 覆盖：
##  - TimelineData.periodic() factory
##  - loop=true 且 max_loops=N 时跑 N 轮后 STATE_COMPLETED
##  - loop=true 且 max_loops=-1 时无限循环（多轮后仍 executing）
##  - on_timeline_start / on_timeline_end 在非 loop / loop 模式下的触发次数
##  - serialize 包含 loopsCompleted

class TestAction:
	extends Action.BaseAction
	var calls: int = 0
	func _init() -> void:
		super._init(TargetSelector.new())
	func execute(_ctx: ExecutionContext) -> ActionResult:
		calls += 1
		return ActionResult.create_success_result([])

func _init() -> void:
	TestFramework.register_test("TimelineData.periodic builds loop timeline", _test_periodic_factory)
	TestFramework.register_test("Loop with max_loops stops after N cycles", _test_max_loops)
	TestFramework.register_test("Loop with max_loops=-1 runs indefinitely", _test_infinite_loop)
	TestFramework.register_test("on_timeline_start/end fire once in non-loop", _test_sync_actions_non_loop)
	TestFramework.register_test("on_timeline_start/end fire per cycle in loop", _test_sync_actions_loop)
	TestFramework.register_test("serialize includes loopsCompleted", _test_serialize_loops)

func _test_periodic_factory() -> void:
	var timeline := TimelineData.periodic("t-periodic", 2000.0)
	TestFramework.assert_equal("t-periodic", timeline.id)
	TestFramework.assert_equal(2000.0, timeline.total_duration)
	TestFramework.assert_true(timeline.loop)
	TestFramework.assert_equal(-1, timeline.max_loops)
	TestFramework.assert_true(timeline.tags.has("tick"))

func _test_max_loops() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-max", 100.0, {"hit": 50.0})
	timeline.loop = true
	timeline.max_loops = 3
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var action := TestAction.new()
	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-max",
		[TagActionsEntry.new("hit", [action])],
		empty_list,
		empty_list,
		{},
		AbilityRef.new("a", "c")
	)

	# 跑 3 轮：每轮 100ms
	instance.tick(100.0, null)  # 轮 1 结束
	TestFramework.assert_true(instance.is_executing())
	instance.tick(100.0, null)  # 轮 2 结束
	TestFramework.assert_true(instance.is_executing())
	instance.tick(100.0, null)  # 轮 3 结束 → COMPLETED
	TestFramework.assert_true(instance.is_completed())
	TestFramework.assert_equal(3, action.calls)

func _test_infinite_loop() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-inf", 100.0, {"hit": 50.0})
	timeline.loop = true
	timeline.max_loops = -1
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var action := TestAction.new()
	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-inf",
		[TagActionsEntry.new("hit", [action])],
		empty_list,
		empty_list,
		{},
		AbilityRef.new("a", "c")
	)

	# 跑 10 轮仍然 executing
	for i in 10:
		instance.tick(100.0, null)
	TestFramework.assert_true(instance.is_executing())
	TestFramework.assert_equal(10, action.calls)

func _test_sync_actions_non_loop() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new("t-sync-nl", 100.0, {}))
	GameWorld.init()

	var start_action := TestAction.new()
	var end_action := TestAction.new()
	var start_list: Array[Action.BaseAction] = [start_action]
	var end_list: Array[Action.BaseAction] = [end_action]
	var instance := AbilityExecutionInstance.new(
		"t-sync-nl",
		[],
		start_list,
		end_list,
		{},
		AbilityRef.new("a", "c")
	)

	# 模拟 activate: fire_sync_actions(start)
	instance.fire_sync_actions(start_list, "__timeline_start__", null)
	TestFramework.assert_equal(1, start_action.calls)

	# tick 完成 → 触发 end，不再触发 start（非 loop，直接 COMPLETED）
	instance.tick(100.0, null)
	TestFramework.assert_true(instance.is_completed())
	TestFramework.assert_equal(1, start_action.calls)  # 未重复触发
	TestFramework.assert_equal(1, end_action.calls)    # 触发 1 次

func _test_sync_actions_loop() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-sync-loop", 100.0, {})
	timeline.loop = true
	timeline.max_loops = 3
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var start_action := TestAction.new()
	var end_action := TestAction.new()
	var start_list: Array[Action.BaseAction] = [start_action]
	var end_list: Array[Action.BaseAction] = [end_action]
	var instance := AbilityExecutionInstance.new(
		"t-sync-loop",
		[],
		start_list,
		end_list,
		{},
		AbilityRef.new("a", "c")
	)

	# 模拟 activate：start 触发一次（轮 1 开始）
	instance.fire_sync_actions(start_list, "__timeline_start__", null)
	TestFramework.assert_equal(1, start_action.calls)
	TestFramework.assert_equal(0, end_action.calls)

	# 轮 1 结束：end 触发 → 进入轮 2：start 触发
	instance.tick(100.0, null)
	TestFramework.assert_equal(2, start_action.calls)
	TestFramework.assert_equal(1, end_action.calls)

	# 轮 2 结束：end 触发 → 进入轮 3：start 触发
	instance.tick(100.0, null)
	TestFramework.assert_equal(3, start_action.calls)
	TestFramework.assert_equal(2, end_action.calls)

	# 轮 3 结束：end 触发 → max_loops 达到 → COMPLETED，不再 start
	instance.tick(100.0, null)
	TestFramework.assert_true(instance.is_completed())
	TestFramework.assert_equal(3, start_action.calls)
	TestFramework.assert_equal(3, end_action.calls)

func _test_serialize_loops() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-ser", 100.0, {})
	timeline.loop = true
	timeline.max_loops = 5
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-ser", [], empty_list, empty_list, {}, AbilityRef.new("a", "c")
	)

	instance.tick(100.0, null)
	instance.tick(100.0, null)

	var s := instance.serialize()
	TestFramework.assert_true(s.has("loopsCompleted"))
	TestFramework.assert_equal(2, s["loopsCompleted"])
