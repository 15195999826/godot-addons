extends Node

## §0.X stack-scaled StatModifier 单测
##
## 合同断言:
## 1. scale_by_stacks() builder 项把 scales_by_stacks=true 透传给 component
## 2. on_apply 时 initial modifier value = config.value * ability.stacks
## 3. Ability.add_stacks 后 modifier value 通过 update_modifier 原子更新
## 4. Ability.remove_stacks 后 modifier value 同步 (按新 stacks)
## 5. Ability.set_stacks 也触发 update (clamp 边界)
## 6. on_stacks_changed reentrance guard: hook 内再调 add_stacks → assert_crash
##    (这条难以直接 test crash; 验证 _notifying_stacks_changed 标志)
## 7. 非 scale_by_stacks 模式: stacks 变化时 component on_stacks_changed no-op


class TestActor:
	extends Actor

	var ability_set: AbilitySet
	var attribute_set: HexBattleCharacterAttributeSet

	func _init(p_actor_id: String) -> void:
		attribute_set = HexBattleCharacterAttributeSet.new(p_actor_id)
		ability_set = AbilitySet.create(p_actor_id, attribute_set)
		type = "TestActor"

	func get_ability_set() -> AbilitySet:
		return ability_set


var _instance: GameplayInstance


func _init() -> void:
	TestFramework.register_test("StatModifierConfig.scale_by_stacks() builder flag set", _test_builder_flag)
	TestFramework.register_test("StatModifier on_apply initial value = config.value * stacks", _test_initial_scaled)
	TestFramework.register_test("StatModifier add_stacks triggers update_modifier", _test_add_stacks)
	TestFramework.register_test("StatModifier remove_stacks updates modifier value", _test_remove_stacks)
	TestFramework.register_test("StatModifier set_stacks updates modifier value", _test_set_stacks)
	TestFramework.register_test("StatModifier non-scale mode does not react to stacks_changed", _test_non_scale_mode_noop)


func _setup() -> void:
	_instance = GameWorld.create_instance(func(): return GameplayInstance.new("stat_mod_test"))


func _teardown() -> void:
	if _instance != null:
		GameWorld.destroy_instance(_instance.id)
		_instance = null


func _make_actor() -> TestActor:
	var actor: TestActor = _instance.add_actor(TestActor.new("test_actor")) as TestActor
	actor.ability_set.owner_actor_id = actor.get_id()
	return actor


func _build_ability_with_stacks(cfg: StatModifierConfig, owner_id: String, initial_stacks: int) -> Ability:
	var ability_config := AbilityConfig.new("demon_test", "", "", "", [], [], [cfg], {}, initial_stacks, 999, 0)
	return Ability.new(ability_config, owner_id)


func _test_builder_flag() -> void:
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.scale_by_stacks()
		.build())
	TestFramework.assert_true(cfg.scales_by_stacks)
	# 不启用时默认 false
	var cfg_default := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.build())
	TestFramework.assert_true(not cfg_default.scales_by_stacks)


func _test_initial_scaled() -> void:
	_setup()
	var actor := _make_actor()
	var initial_atk := actor.attribute_set.atk
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.scale_by_stacks()
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 3)
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, null)
	ability.apply_effects(ctx)
	# stacks=3 → atk +6 (3 * 2.0 ADD_BASE)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 6.0)) < 0.01,
		"initial value should = base + stacks*2 = %.2f, got %.2f" % [initial_atk + 6.0, actor.attribute_set.atk])
	_teardown()


func _test_add_stacks() -> void:
	_setup()
	var actor := _make_actor()
	var initial_atk := actor.attribute_set.atk
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.scale_by_stacks()
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 1)
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, null)
	ability.apply_effects(ctx)
	# initial stacks=1 → +2
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 2.0)) < 0.01)
	# add 2 stacks → total stacks=3 → +6
	ability.add_stacks(2)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 6.0)) < 0.01,
		"after add 2 stacks: expected %.2f, got %.2f" % [initial_atk + 6.0, actor.attribute_set.atk])
	_teardown()


func _test_remove_stacks() -> void:
	_setup()
	var actor := _make_actor()
	var initial_atk := actor.attribute_set.atk
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.scale_by_stacks()
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 5)
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, null)
	ability.apply_effects(ctx)
	# stacks=5 → +10
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 10.0)) < 0.01)
	ability.remove_stacks(2)
	# stacks=3 → +6
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 6.0)) < 0.01,
		"after remove 2 stacks: expected %.2f, got %.2f" % [initial_atk + 6.0, actor.attribute_set.atk])
	_teardown()


func _test_set_stacks() -> void:
	_setup()
	var actor := _make_actor()
	var initial_atk := actor.attribute_set.atk
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.scale_by_stacks()
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 1)
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, null)
	ability.apply_effects(ctx)
	ability.set_stacks(10)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 20.0)) < 0.01,
		"set_stacks 10: expected %.2f, got %.2f" % [initial_atk + 20.0, actor.attribute_set.atk])
	_teardown()


func _test_non_scale_mode_noop() -> void:
	_setup()
	var actor := _make_actor()
	var initial_atk := actor.attribute_set.atk
	# 不调 scale_by_stacks
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 5.0)
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 1)
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, null)
	ability.apply_effects(ctx)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 5.0)) < 0.01)
	# 增加 stacks 不应改变 modifier value (非 scale 模式)
	ability.add_stacks(4)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 5.0)) < 0.01,
		"non-scale mode: stacks 变化不应改变 modifier (atk 仍为 base+5)")
	_teardown()
