extends Node

## §0.1 LooseTagAction 单测
##
## 锁定合同:
## - Apply 只改 loose tag (不影响 component / auto-duration tag)
## - Remove 只改 loose tag (不影响 component / auto-duration tag)
## - Remove 多 stack 时按数量扣，全清用 REMOVE_ALL_STACKS

class TestActor:
	extends Actor

	var _ability_set: AbilitySet

	func _init(ability_set_value: AbilitySet) -> void:
		_ability_set = ability_set_value
		type = "TestActor"

	func get_ability_set() -> AbilitySet:
		return _ability_set


class FixedSelector extends TargetSelector:
	var _targets: Array[String]

	func _init(targets: Array[String]) -> void:
		_targets = targets

	func select(_ctx: ExecutionContext) -> Array[String]:
		return _targets


var _instance: GameplayInstance


func _init() -> void:
	TestFramework.register_test("LooseTagAction.Apply adds loose tag with stacks", _test_apply_basic)
	TestFramework.register_test("LooseTagAction.Remove drops single stack", _test_remove_partial)
	TestFramework.register_test("LooseTagAction.Remove with REMOVE_ALL_STACKS clears tag", _test_remove_all)
	TestFramework.register_test("LooseTagAction does not touch auto-duration tags", _test_no_collision_with_auto_duration)


func _setup() -> void:
	_instance = GameWorld.create_instance(func(): return GameplayInstance.new("loose_tag_test"))


func _teardown() -> void:
	if _instance != null:
		GameWorld.destroy_instance(_instance.id)
		_instance = null


func _make_actor() -> Array:
	var aset := AbilitySet.create("dummy", null)
	var actor: TestActor = _instance.add_actor(TestActor.new(aset)) as TestActor
	aset.owner_actor_id = actor.get_id()
	return [aset, actor.get_id()]


func _ctx() -> ExecutionContext:
	return ExecutionContext.create([{"kind":"test"}], _instance, GameWorld.event_collector, null, null)


func _test_apply_basic() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var actor_id: String = pair[1]
	var act := LooseTagAction.Apply.new(FixedSelector.new([actor_id]), "combo", Resolvers.int_val(2))
	act.execute(_ctx())
	TestFramework.assert_equal(2, aset.get_loose_tag_stacks("combo"))
	_teardown()


func _test_remove_partial() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var actor_id: String = pair[1]
	aset.add_loose_tag("charge", 3)
	var act := LooseTagAction.Remove.new(FixedSelector.new([actor_id]), "charge", Resolvers.int_val(1))
	act.execute(_ctx())
	TestFramework.assert_equal(2, aset.get_loose_tag_stacks("charge"))
	_teardown()


func _test_remove_all() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var actor_id: String = pair[1]
	aset.add_loose_tag("rage", 5)
	var act := LooseTagAction.Remove.new(FixedSelector.new([actor_id]), "rage")
	act.execute(_ctx())
	TestFramework.assert_equal(0, aset.get_loose_tag_stacks("rage"))
	_teardown()


func _test_no_collision_with_auto_duration() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var actor_id: String = pair[1]
	aset.add_auto_duration_tag("window", 100.0)
	# Apply 不应清掉 auto-duration window stack
	var act := LooseTagAction.Apply.new(FixedSelector.new([actor_id]), "window", Resolvers.int_val(1))
	act.execute(_ctx())
	# loose 加一层后，window 聚合至少 2 stacks (loose1 + duration1)
	TestFramework.assert_true(aset.get_tag_stacks("window") >= 2)
	TestFramework.assert_equal(1, aset.get_loose_tag_stacks("window"))
	_teardown()
