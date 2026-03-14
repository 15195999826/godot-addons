extends Node


## Mock Actor 实现 IAbilitySetOwner 协议
class TestActor:
	extends Actor

	var _ability_set: AbilitySet

	func _init(ability_set_value: AbilitySet):
		_ability_set = ability_set_value
		type = "TestActor"

	func get_ability_set() -> AbilitySet:
		return _ability_set


## 测试用固定目标选择器（框架层测试不依赖项目层）
class FixedSelector extends TargetSelector:
	var _targets: Array[String]

	func _init(targets: Array[String]) -> void:
		_targets = targets

	func select(_ctx: ExecutionContext) -> Array[String]:
		return _targets


var _test_instance: GameplayInstance


func _init() -> void:
	TestFramework.register_test("ApplyTagAction adds loose tag", _test_apply_loose)
	TestFramework.register_test("ApplyTagAction adds auto-duration tag", _test_apply_auto_duration)
	TestFramework.register_test("RemoveTagAction removes loose tag", _test_remove_tag)
	TestFramework.register_test("HasTagAction executes then/else", _test_has_tag_action)


func _setup_test_instance() -> void:
	# 创建测试用 GameplayInstance 并注册到 GameWorld
	_test_instance = GameWorld.create_instance(func(): return GameplayInstance.new("test_instance"))


func _teardown_test_instance() -> void:
	if _test_instance != null:
		GameWorld.destroy_instance(_test_instance.id)
		_test_instance = null


func _create_test_actor(ability_set: AbilitySet) -> TestActor:
	return _test_instance.add_actor(TestActor.new(ability_set)) as TestActor


func _build_context(event: Dictionary = {}) -> ExecutionContext:
	var event_dict_chain: Array[Dictionary] = [event]
	return ExecutionContext.create(
		event_dict_chain,
		_test_instance,
		GameWorld.event_collector,
		null,  # ability_ref
		null   # execution_info
	)


func _test_apply_loose() -> void:
	_setup_test_instance()
	var ability_set := AbilitySet.create("temp", null)
	var actor := _create_test_actor(ability_set)
	var actor_id := actor.get_id()
	ability_set.owner_actor_id = actor_id
	var ctx := _build_context({"kind": "apply"})

	var action := TagAction.ApplyTagAction.new(
		FixedSelector.new([actor_id]),
		"combo",
		Resolvers.int_val(2)  # stacks
	)
	var result := action.execute(ctx)
	TestFramework.assert_true(result.success)
	TestFramework.assert_equal(2, ability_set.get_loose_tag_stacks("combo"))
	_teardown_test_instance()


func _test_apply_auto_duration() -> void:
	_setup_test_instance()
	var ability_set := AbilitySet.create("temp", null)
	var actor := _create_test_actor(ability_set)
	var actor_id := actor.get_id()
	ability_set.owner_actor_id = actor_id
	var ctx := _build_context({"kind": "apply", "logicTime": 1.0})

	var action := TagAction.ApplyTagAction.new(
		FixedSelector.new([actor_id]),
		"window",
		Resolvers.int_val(1),    # stacks
		Resolvers.float_val(5.0)   # duration
	)
	var result := action.execute(ctx)
	TestFramework.assert_true(result.success)
	TestFramework.assert_equal(1, ability_set.get_tag_stacks("window"))
	ability_set.tick(6.0, 7.0)
	TestFramework.assert_equal(0, ability_set.get_tag_stacks("window"))
	_teardown_test_instance()


func _test_remove_tag() -> void:
	_setup_test_instance()
	var ability_set := AbilitySet.create("temp", null)
	var actor := _create_test_actor(ability_set)
	var actor_id := actor.get_id()
	ability_set.owner_actor_id = actor_id
	ability_set.add_loose_tag("charge", 3)
	var ctx := _build_context({"kind": "remove"})

	var action := TagAction.RemoveTagAction.new(
		FixedSelector.new([actor_id]),
		"charge",
		Resolvers.int_val(1)  # stacks to remove
	)
	var result := action.execute(ctx)
	TestFramework.assert_true(result.success)
	TestFramework.assert_equal(2, ability_set.get_loose_tag_stacks("charge"))
	_teardown_test_instance()


func _test_has_tag_action() -> void:
	_setup_test_instance()
	var ability_set := AbilitySet.create("temp", null)
	var actor := _create_test_actor(ability_set)
	var actor_id := actor.get_id()
	ability_set.owner_actor_id = actor_id
	ability_set.add_loose_tag("ready", 1)
	var ctx := _build_context({"kind": "check"})

	var selector := FixedSelector.new([actor_id])
	var then_action := Action.NoopAction.new(selector)
	var else_action := Action.NoopAction.new(selector)
	var action := TagAction.HasTagAction.new(
		selector,
		"ready",
		[then_action],
		[else_action]
	)
	var result := action.execute(ctx)
	TestFramework.assert_true(result.success)
	TestFramework.assert_equal(0, result.event_dicts.size())
	_teardown_test_instance()
