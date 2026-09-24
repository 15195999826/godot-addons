extends Node

## ActionStepper（表演步进器）的时序合同钉子
##
## 钉住合同：
## - enqueue 后每 tick 按 delta 推 elapsed；progress = (elapsed - delay) / duration 夹到 [0, 1]
## - delay 未过：is_delaying、progress 0，仍在 active_actions 里，不算完成，但算 has_changes
## - duration 0 的瞬时卡片：delay 一过当 tick 完成，progress 钉 1
## - 完成那一 tick 进 completed_this_tick（progress 钉 1，哪怕 elapsed 超出），同 tick 不再出现在
##   active_actions，之后也不再出现；表空时 tick 无变化
## - cancel_all 清空且不补发完成；id 在整个 stepper 生命周期内不复用


func _init() -> void:
	TestFramework.register_test("ActionStepper progress 0→1，完成 tick 进 completed_this_tick 且退出 active", _test_progress_and_completion)
	TestFramework.register_test("ActionStepper delay 期间 is_delaying、progress 0、不推进", _test_delay)
	TestFramework.register_test("ActionStepper duration 0 瞬时卡片 delay 一过当 tick 完成", _test_instant)
	TestFramework.register_test("ActionStepper 空表 tick 无变化", _test_empty_tick)
	TestFramework.register_test("ActionStepper cancel_all 清空不补发完成，id 不复用", _test_cancel_all)


static func _card(duration: float, delay: float = 0.0) -> VisualAction:
	var action := VisualAction.new(VisualAction.KIND_MOVE, duration, delay)
	action.actor_id = "probe"
	return action


func _test_progress_and_completion() -> void:
	var stepper := ActionStepper.new()
	var actions: Array[VisualAction] = [_card(400.0)]
	stepper.enqueue(actions)
	TestFramework.assert_equal(1, stepper.get_action_count())

	var r1 := stepper.tick(100.0)
	TestFramework.assert_true(r1.has_changes)
	TestFramework.assert_equal(1, r1.active_actions.size())
	TestFramework.assert_equal(0, r1.completed_this_tick.size())
	TestFramework.assert_near(r1.active_actions[0].progress, 0.25)
	TestFramework.assert_false(r1.active_actions[0].is_delaying)

	var r2 := stepper.tick(100.0)
	TestFramework.assert_near(r2.active_actions[0].progress, 0.5)

	# elapsed 450 ≥ 400：完成，progress 钉 1（不是 1.125）
	var r3 := stepper.tick(250.0)
	TestFramework.assert_equal(1, r3.completed_this_tick.size())
	TestFramework.assert_near(r3.completed_this_tick[0].progress, 1.0)
	# 完成的卡片同 tick 不再是 active
	TestFramework.assert_equal(0, r3.active_actions.size())
	TestFramework.assert_true(r3.has_changes)
	TestFramework.assert_equal(0, stepper.get_action_count())

	var r4 := stepper.tick(100.0)
	TestFramework.assert_false(r4.has_changes)
	TestFramework.assert_equal(0, r4.completed_this_tick.size())


func _test_delay() -> void:
	var stepper := ActionStepper.new()
	var actions: Array[VisualAction] = [_card(200.0, 300.0)]
	stepper.enqueue(actions)
	TestFramework.assert_true(stepper.get_active_actions()[0].is_delaying, "入队即按 delay > 0 标延迟")

	# elapsed 100 < delay 300
	var r1 := stepper.tick(100.0)
	TestFramework.assert_true(r1.active_actions[0].is_delaying)
	TestFramework.assert_near(r1.active_actions[0].progress, 0.0)
	TestFramework.assert_true(r1.has_changes, "延迟中也算有变化")
	TestFramework.assert_equal(0, r1.completed_this_tick.size())

	# elapsed 300 == delay：延迟结束，有效时长 0，还没完成
	var r2 := stepper.tick(200.0)
	TestFramework.assert_false(r2.active_actions[0].is_delaying)
	TestFramework.assert_near(r2.active_actions[0].progress, 0.0)
	TestFramework.assert_equal(0, r2.completed_this_tick.size())

	# 有效 100 / 200
	var r3 := stepper.tick(100.0)
	TestFramework.assert_near(r3.active_actions[0].progress, 0.5)

	# 有效 200 ≥ 200：完成
	var r4 := stepper.tick(100.0)
	TestFramework.assert_equal(1, r4.completed_this_tick.size())
	TestFramework.assert_near(r4.completed_this_tick[0].progress, 1.0)
	TestFramework.assert_equal(0, stepper.get_action_count())


func _test_instant() -> void:
	var stepper := ActionStepper.new()
	var actions: Array[VisualAction] = [_card(0.0), _card(0.0, 150.0)]
	stepper.enqueue(actions)

	var r1 := stepper.tick(16.0)
	# 无延迟的瞬时卡片首 tick 完成
	TestFramework.assert_equal(1, r1.completed_this_tick.size())
	TestFramework.assert_near(r1.completed_this_tick[0].progress, 1.0)
	# 延迟中的瞬时卡片仍活着
	TestFramework.assert_equal(1, r1.active_actions.size())
	TestFramework.assert_true(r1.active_actions[0].is_delaying)

	# elapsed 150 == delay：瞬时卡片当 tick 完成
	var r2 := stepper.tick(134.0)
	TestFramework.assert_equal(1, r2.completed_this_tick.size())
	TestFramework.assert_near(r2.completed_this_tick[0].progress, 1.0)
	TestFramework.assert_equal(0, r2.active_actions.size())
	TestFramework.assert_equal(0, stepper.get_action_count())


func _test_empty_tick() -> void:
	var stepper := ActionStepper.new()
	var result := stepper.tick(100.0)
	TestFramework.assert_false(result.has_changes)
	TestFramework.assert_equal(0, result.active_actions.size())
	TestFramework.assert_equal(0, result.completed_this_tick.size())
	TestFramework.assert_equal(0, stepper.get_action_count())
	TestFramework.assert_equal(0, stepper.get_active_actions().size())


func _test_cancel_all() -> void:
	var stepper := ActionStepper.new()
	var first: Array[VisualAction] = [_card(500.0), _card(500.0)]
	stepper.enqueue(first)
	var before := stepper.tick(100.0)
	var seen := {}
	for active: ActionStepper.ActiveAction in before.active_actions:
		seen[active.id] = true
	# 两张卡片 id 各不相同
	TestFramework.assert_equal(2, seen.size())

	stepper.cancel_all()
	TestFramework.assert_equal(0, stepper.get_action_count())
	TestFramework.assert_equal(0, stepper.get_active_actions().size())
	var after_cancel := stepper.tick(100.0)
	TestFramework.assert_false(after_cancel.has_changes)
	# 取消的卡片不补发完成
	TestFramework.assert_equal(0, after_cancel.completed_this_tick.size())

	var second: Array[VisualAction] = [_card(500.0)]
	stepper.enqueue(second)
	var again := stepper.tick(100.0)
	TestFramework.assert_equal(1, again.active_actions.size())
	TestFramework.assert_false(seen.has(again.active_actions[0].id), "cancel_all 之后 id 不复用")
