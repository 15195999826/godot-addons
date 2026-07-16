extends Node

## Timeline loop 行为测试
##
## 覆盖：
##  - TimelineData.periodic() factory
##  - loop=true 且 max_loops=N 时跑 N 轮后 STATE_COMPLETED
##  - loop=true 且 max_loops=-1 时无限循环（多轮后仍 executing）
##  - on_timeline_start / on_timeline_end 在非 loop / loop 模式下的触发次数
##  - serialize 包含 loopsCompleted
##  - 跨周期余量结转：溢出时间进入下一轮计时、结转窗口内 tag 同 tick 补触发、
##    周期节奏不随 dt 漂移、max_loops 终轮不结转

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
	TestFramework.register_test("Loop carries overflow into next cycle", _test_loop_carry_over)
	TestFramework.register_test("Loop cycle cadence does not drift with dt", _test_loop_cadence_no_drift)
	TestFramework.register_test("Loop final cycle does not carry past max_loops", _test_loop_no_carry_past_max_loops)

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

## 溢出余量必须进入下一轮计时，且结转窗口 (0, carry] 内的 tag 在同一次 tick 补触发。
func _test_loop_carry_over() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-carry", 100.0, {"hit": 50.0})
	timeline.loop = true
	timeline.max_loops = -1
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var action := TestAction.new()
	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-carry",
		[TagActionsEntry.new("hit", [action])],
		empty_list,
		empty_list,
		{},
		AbilityRef.new("a", "c")
	)

	# tick1: 0→80，hit@50 触发
	instance.tick(80.0, null)
	TestFramework.assert_equal(1, action.calls)
	TestFramework.assert_near(instance.get_elapsed(), 80.0)

	# tick2: 80→160，跨过 100：余量 60 结转，新一轮 (0, 60] 内 hit@50 同 tick 补触发
	var triggered := instance.tick(80.0, null)
	TestFramework.assert_equal(2, action.calls)
	TestFramework.assert_true(triggered.has("hit"))
	TestFramework.assert_near(instance.get_elapsed(), 60.0)
	TestFramework.assert_true(instance.is_executing())
	TestFramework.assert_equal(1, instance.serialize()["loopsCompleted"])


## 周期节奏不随 dt 漂移：100ms 周期在 dt=60 下，300ms 内应完成 3 轮
## （若余量被清零，每轮被拉长到 120ms，只会完成 2 轮）。
func _test_loop_cadence_no_drift() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-cadence", 100.0, {"hit": 50.0})
	timeline.loop = true
	timeline.max_loops = -1
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var tag_action := TestAction.new()
	var start_action := TestAction.new()
	var end_action := TestAction.new()
	var start_list: Array[Action.BaseAction] = [start_action]
	var end_list: Array[Action.BaseAction] = [end_action]
	var instance := AbilityExecutionInstance.new(
		"t-cadence",
		[TagActionsEntry.new("hit", [tag_action])],
		start_list,
		end_list,
		{},
		AbilityRef.new("a", "c")
	)

	for i in 5:
		instance.tick(60.0, null)

	# 真实时间 300ms = 3 个完整周期：每轮 end/重启 start/hit 各 3 次
	TestFramework.assert_equal(3, end_action.calls)
	TestFramework.assert_equal(3, start_action.calls)
	TestFramework.assert_equal(3, tag_action.calls)
	TestFramework.assert_equal(3, instance.serialize()["loopsCompleted"])
	TestFramework.assert_near(instance.get_elapsed(), 0.0)


## max_loops 达成时终轮溢出不得结转：不重启、不补触发新一轮 tag。
func _test_loop_no_carry_past_max_loops() -> void:
	TimelineRegistry.reset()
	var timeline := TimelineData.new("t-carry-max", 100.0, {"hit": 50.0})
	timeline.loop = true
	timeline.max_loops = 1
	TimelineRegistry.register(timeline)
	GameWorld.init()

	var action := TestAction.new()
	var empty_list: Array[Action.BaseAction] = []
	var instance := AbilityExecutionInstance.new(
		"t-carry-max",
		[TagActionsEntry.new("hit", [action])],
		empty_list,
		empty_list,
		{},
		AbilityRef.new("a", "c")
	)

	instance.tick(80.0, null)   # hit 触发
	instance.tick(80.0, null)   # 160 ≥ 100：唯一一轮结束 → COMPLETED，余量丢弃
	TestFramework.assert_true(instance.is_completed())
	TestFramework.assert_equal(1, action.calls)


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
