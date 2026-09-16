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
## 8. instance 已销毁后仍 revoke: 两个 modifier 组件的 on_remove 各响亮恰一条断言、仍清内部记录、退场照常走完

const LogCounter := preload("res://addons/logic-game-framework/tests/log_counter.gd")
## 两个 modifier 组件在 owner 反查不到属性集时打的断言文本（模块名 / 钩子名之外的公共部分）。
const ORPHAN_ASSERT_TEXT := "owner 已不在 instance / instance 已销毁，modifier 无法清理"


class TestActor:
	extends BattleActor

	var ability_set: AbilitySet
	var attribute_set: HexBattleCharacterAttributeSet

	func _init(p_actor_id: String) -> void:
		attribute_set = HexBattleCharacterAttributeSet.new(p_actor_id)
		ability_set = AbilitySet.create(p_actor_id, attribute_set)
		type = "TestActor"

	func get_ability_set() -> AbilitySet:
		return ability_set

	func get_attribute_set() -> BaseGeneratedAttributeSet:
		return attribute_set


var _instance: GameplayInstance


func _init() -> void:
	TestFramework.register_test("StatModifierConfig.scale_by_stacks() builder flag set", _test_builder_flag)
	TestFramework.register_test("StatModifier on_apply initial value = config.value * stacks", _test_initial_scaled)
	TestFramework.register_test("StatModifier add_stacks triggers update_modifier", _test_add_stacks)
	TestFramework.register_test("StatModifier stack update emits one before/after attribute event", _test_stack_update_emits_attribute_event)
	TestFramework.register_test("StatModifier remove_stacks updates modifier value", _test_remove_stacks)
	TestFramework.register_test("StatModifier set_stacks updates modifier value", _test_set_stacks)
	TestFramework.register_test("StatModifier non-scale mode does not react to stacks_changed", _test_non_scale_mode_noop)
	TestFramework.register_test("StatModifier revoke after instance destroyed asserts once and still clears its record", _test_stat_modifier_orphan_revoke_asserts_once)
	TestFramework.register_test("DynamicStatModifier revoke after instance destroyed asserts once", _test_dynamic_modifier_orphan_revoke_asserts_once)


func _setup() -> void:
	_instance = GameWorld.create_instance(GameplayInstance.new("stat_mod_test"))


func _teardown() -> void:
	if _instance != null:
		GameWorld.destroy_instance(_instance.id)
		_instance = null


func _make_actor() -> TestActor:
	var actor: TestActor = _instance.add_actor(TestActor.new("test_actor")) as TestActor
	return actor


func _build_ability_with_stacks(cfg: StatModifierConfig, owner_id: String, initial_stacks: int) -> Ability:
	var ability_config := AbilityConfig.new("demon_test", "", "", "", [], [cfg], {}, initial_stacks, 999, 0)
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
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, _instance)
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
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, _instance)
	ability.apply_effects(ctx)
	# initial stacks=1 → +2
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 2.0)) < 0.01)
	# add 2 stacks → total stacks=3 → +6
	ability.add_stacks(2)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 6.0)) < 0.01,
		"after add 2 stacks: expected %.2f, got %.2f" % [initial_atk + 6.0, actor.attribute_set.atk])
	_teardown()


func _test_stack_update_emits_attribute_event() -> void:
	_setup()
	var actor := _make_actor()
	var initial_atk := actor.attribute_set.atk
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.scale_by_stacks()
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 1)
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, _instance)
	ability.apply_effects(ctx)

	var events: Array[Dictionary] = []
	actor.attribute_set.get_raw().add_change_listener(func(event: Dictionary) -> void:
		events.append(event.duplicate())
	)

	ability.add_stacks(2)

	TestFramework.assert_true(events.size() == 1,
		"stack-scaled modifier update should emit exactly one attribute event, got %d" % events.size())
	if events.size() == 1:
		var event := events[0]
		TestFramework.assert_true(str(event.get("attribute_name", "")) == "atk",
			"attribute event should be for atk")
		TestFramework.assert_near(event.get("old_value", 0.0) as float, initial_atk + 2.0, 0.01,
			"attribute event old_value should reflect pre-update atk")
		TestFramework.assert_near(event.get("new_value", 0.0) as float, initial_atk + 6.0, 0.01,
			"attribute event new_value should reflect post-update atk")
		TestFramework.assert_true(str(event.get("change_type", "")) == "modifier",
			"attribute event change_type should be modifier")
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
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, _instance)
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
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, _instance)
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
	var ctx := AbilityLifecycleContext.new(actor.get_id(), actor.attribute_set, ability, actor.ability_set, _instance)
	ability.apply_effects(ctx)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 5.0)) < 0.01)
	# 增加 stacks 不应改变 modifier value (非 scale 模式)
	ability.add_stacks(4)
	TestFramework.assert_true(absf(actor.attribute_set.atk - (initial_atk + 5.0)) < 0.01,
		"non-scale mode: stacks 变化不应改变 modifier (atk 仍为 base+5)")
	_teardown()


## instance 已销毁后仍 revoke：on_remove 的 context 按 owner 反查、属性集为 null。合同 = 响亮恰一条断言（不是静默返回，
## 也不是 null 解引用的引擎错误）、组件内部记录仍清、退场照常走完（ability 过期、set 除名）。属性集上那条 modifier
## 清不到正是这条断言存在的原因，不是合同。
func _test_stat_modifier_orphan_revoke_asserts_once() -> void:
	_setup()
	var actor := _make_actor()
	var cfg := (StatModifierConfig.builder()
		.modifier("atk", AttributeModifier.Type.ADD_BASE, 2.0)
		.build())
	var ability := _build_ability_with_stacks(cfg, actor.get_id(), 1)
	actor.ability_set.grant_ability(ability)
	var component := ability.get_all_components()[0] as StatModifierComponent
	TestFramework.assert_equal(1, component.get_modifiers().size())
	GameWorld.destroy_instance(_instance.id)
	_instance = null

	var log_counter := LogCounter.new(ORPHAN_ASSERT_TEXT)
	TestFramework.expect_script_errors(1)
	OS.add_logger(log_counter)
	var revoked := actor.ability_set.revoke_ability(ability.id)
	OS.remove_logger(log_counter)

	TestFramework.assert_true(revoked)
	TestFramework.assert_true(ability.is_expired())
	TestFramework.assert_equal(0, actor.ability_set.get_ability_count())
	TestFramework.assert_equal(1, log_counter.matched_errors)
	TestFramework.assert_equal(1, log_counter.errors)
	TestFramework.assert_true(component.get_modifiers().is_empty(), "内部记录仍要清")


func _test_dynamic_modifier_orphan_revoke_asserts_once() -> void:
	_setup()
	var actor := _make_actor()
	var config := (AbilityConfig.builder()
		.config_id("dynamic_orphan_test")
		.component_config(DynamicStatModifierComponentConfig.new(
			DynamicStatModifierConfig.new("max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.01)))
		.build())
	var ability := Ability.new(config, actor.get_id())
	actor.ability_set.grant_ability(ability)
	GameWorld.destroy_instance(_instance.id)
	_instance = null

	var log_counter := LogCounter.new(ORPHAN_ASSERT_TEXT)
	TestFramework.expect_script_errors(1)
	OS.add_logger(log_counter)
	var revoked := actor.ability_set.revoke_ability(ability.id)
	OS.remove_logger(log_counter)

	TestFramework.assert_true(revoked)
	TestFramework.assert_true(ability.is_expired())
	TestFramework.assert_equal(0, actor.ability_set.get_ability_count())
	TestFramework.assert_equal(1, log_counter.matched_errors)
	TestFramework.assert_equal(1, log_counter.errors)
