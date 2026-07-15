extends Node

## §0.6 NoInstanceConfig / NoInstanceComponent lifecycle actions 单测
##
## 合同断言:
## 1. 旧行为 (trigger + action) 不变
## 2. lifecycle-only config 合法 (无 trigger)
## 3. on_apply_actions: Ability apply_effects → 执行 actions
## 4. on_remove_actions: Ability remove_effects → 执行 actions
## 5. lifecycle actions 配合 LooseTagAction 写 tag → 在 AbilitySet 真生效


class TestActor:
	extends Actor

	var ability_set: AbilitySet

	func _init(ability_set_value: AbilitySet) -> void:
		ability_set = ability_set_value
		type = "TestActor"

	func get_ability_set() -> AbilitySet:
		return ability_set


class FixedSelector extends TargetSelector:
	var _targets: Array[String] = []

	func _init(targets: Array[String]) -> void:
		_targets = targets

	func select(_ctx: ExecutionContext) -> Array[String]:
		return _targets


class RecordingAction:
	extends Action.PrimitiveAction

	const EVENT_KIND := "no_instance_test_recording"
	var tag: String

	func _init(p_tag: String) -> void:
		super._init(FixedSelector.new([]))
		type = "recording_" + p_tag
		tag = p_tag

	func execute(ctx: ExecutionContext) -> ActionResult:
		var event_dict := {
			"kind": EVENT_KIND,
			"tag": tag,
		}
		ctx.event_collector.push(event_dict)
		return ActionResult.create_success_result([event_dict])


var _instance: GameplayInstance


func _init() -> void:
	TestFramework.register_test("NoInstance lifecycle-only build is valid (no trigger)", _test_lifecycle_only)
	TestFramework.register_test("NoInstance on_apply runs apply-time actions", _test_on_apply_runs)
	TestFramework.register_test("NoInstance on_remove runs remove-time actions", _test_on_remove_runs)
	TestFramework.register_test("NoInstance lifecycle actions mutate loose tag via Ability lifecycle", _test_lifecycle_tag_mutation)
	TestFramework.register_test("NoInstance trigger+action still works after lifecycle extension", _test_trigger_still_works)


func _setup() -> void:
	GameWorld.event_collector.clear()
	_instance = GameWorld.create_instance(func(): return GameplayInstance.new("no_instance_test"))


func _teardown() -> void:
	if _instance != null:
		GameWorld.destroy_instance(_instance.id)
		_instance = null


func _make_actor() -> Array:
	var aset := AbilitySet.create("dummy", null)
	var actor: TestActor = _instance.add_actor(TestActor.new(aset)) as TestActor
	aset.owner_actor_id = actor.get_id()
	return [aset, actor.get_id()]


func _build_ability(cfg: NoInstanceConfig, owner_id: String) -> Ability:
	var ability_config := AbilityConfig.new("test_ability", "", "", "", [], [], [cfg])
	return Ability.new(ability_config, owner_id)


func _recorded_count(tag: String) -> int:
	var count := 0
	for event_dict in GameWorld.event_collector.collect():
		if (event_dict.get("kind", "") as String) == RecordingAction.EVENT_KIND \
				and (event_dict.get("tag", "") as String) == tag:
			count += 1
	return count


func _test_lifecycle_only() -> void:
	# Verify build() permits lifecycle-only NoInstanceConfig (no trigger)
	var apply_act := RecordingAction.new("apply")
	var remove_act := RecordingAction.new("remove")
	var apply_arr: Array[Action.BaseAction] = [apply_act]
	var remove_arr: Array[Action.BaseAction] = [remove_act]
	var cfg := (NoInstanceConfig.builder()
		.on_apply_actions(apply_arr)
		.on_remove_actions(remove_arr)
		.build())
	TestFramework.assert_equal(0, cfg.triggers.size())
	TestFramework.assert_equal(1, cfg.on_apply_actions.size())
	TestFramework.assert_equal(1, cfg.on_remove_actions.size())


func _test_on_apply_runs() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var apply_act := RecordingAction.new("apply")
	var apply_arr: Array[Action.BaseAction] = [apply_act]
	var cfg := NoInstanceConfig.builder().on_apply_actions(apply_arr).build()
	var ability := _build_ability(cfg, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)
	ability.apply_effects(ctx)
	TestFramework.assert_equal(1, _recorded_count("apply"))
	_teardown()


func _test_on_remove_runs() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var remove_act := RecordingAction.new("remove")
	var remove_arr: Array[Action.BaseAction] = [remove_act]
	var cfg := NoInstanceConfig.builder().on_remove_actions(remove_arr).build()
	var ability := _build_ability(cfg, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)
	ability.apply_effects(ctx)
	TestFramework.assert_true(_recorded_count("remove") == 0, "on_remove must not fire on apply")
	ability.remove_effects()
	TestFramework.assert_equal(1, _recorded_count("remove"))
	_teardown()


func _test_lifecycle_tag_mutation() -> void:
	# Use real LooseTagAction in lifecycle: apply 添加 tag, remove 移除 tag.
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var sel := FixedSelector.new([owner_id])
	var apply_arr: Array[Action.BaseAction] = [
		LooseTagAction.Apply.new(sel, "stance:test:wrath")
	]
	var remove_arr: Array[Action.BaseAction] = [
		LooseTagAction.Remove.new(sel, "stance:test:wrath")
	]
	var cfg := (NoInstanceConfig.builder()
		.on_apply_actions(apply_arr)
		.on_remove_actions(remove_arr)
		.build())
	var ability := _build_ability(cfg, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)

	ability.apply_effects(ctx)
	TestFramework.assert_true(aset.get_loose_tag_stacks("stance:test:wrath") == 1,
		"on_apply should add loose tag, got %d" % aset.get_loose_tag_stacks("stance:test:wrath"))
	ability.remove_effects()
	TestFramework.assert_true(aset.get_loose_tag_stacks("stance:test:wrath") == 0,
		"on_remove should remove loose tag, got %d" % aset.get_loose_tag_stacks("stance:test:wrath"))
	_teardown()


func _test_trigger_still_works() -> void:
	# 旧 trigger+action 行为不应被 lifecycle 扩展破坏
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var trigger_act := RecordingAction.new("trigger")
	var trigger_cfg := TriggerConfig.new("test_kind",
		func(_e: Dictionary, _c: AbilityLifecycleContext) -> bool: return true)
	var cfg := (NoInstanceConfig.builder()
		.trigger(trigger_cfg)
		.action(trigger_act)
		.build())
	var ability := _build_ability(cfg, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)
	ability.apply_effects(ctx)
	var comp: NoInstanceComponent = ability.get_all_components()[0] as NoInstanceComponent
	comp.on_event({"kind": "test_kind"}, ctx, null)
	TestFramework.assert_equal(1, _recorded_count("trigger"))
	_teardown()
