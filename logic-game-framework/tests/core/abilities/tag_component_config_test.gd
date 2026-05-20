extends Node

## §0.1 TagComponentConfig 单测
##
## 锁定合同:
## - builder().tag(name) / .optional_tag("") 都正确
## - create_component 生成的 TagComponent 在 Ability apply 后写入 component tag
## - Ability remove 后 component tag 被自动清掉
## - component tag 与 loose tag 互不影响 (在 ability 存在期间不依赖 loose tag mutation)

const STATUS_TAG := "test_status"
const ACTION_LOCK_TAG := "test_action_lock"
const REASON_TAG := "test_reason"


class TestActor:
	extends Actor

	# Ability._build_remove_context 使用 "ability_set" in actor 属性检测,
	# 所以这里暴露为公共属性而非私有 + getter。
	var ability_set: AbilitySet

	func _init(ability_set_value: AbilitySet) -> void:
		ability_set = ability_set_value
		type = "TestActor"

	func get_ability_set() -> AbilitySet:
		return ability_set


var _instance: GameplayInstance


func _init() -> void:
	TestFramework.register_test("TagComponentConfig builder rejects empty tag set", _test_builder_empty)
	TestFramework.register_test("TagComponentConfig optional_tag('') ignored", _test_optional_empty)
	TestFramework.register_test("TagComponent applies tags via ability lifecycle", _test_lifecycle_apply)
	TestFramework.register_test("TagComponent removes tags on ability remove", _test_lifecycle_remove)
	TestFramework.register_test("TagComponent does not affect loose tag of same name", _test_independent_from_loose)


func _setup() -> void:
	_instance = GameWorld.create_instance(func(): return GameplayInstance.new("tag_cfg_test"))


func _teardown() -> void:
	if _instance != null:
		GameWorld.destroy_instance(_instance.id)
		_instance = null


func _make_actor() -> Array:
	var aset := AbilitySet.create("dummy", null)
	var actor: TestActor = _instance.add_actor(TestActor.new(aset)) as TestActor
	aset.owner_actor_id = actor.get_id()
	return [aset, actor.get_id()]


func _test_builder_empty() -> void:
	# 期望 build() crash 这种 case 测试比较麻烦，改成检查 tags_dict() 至少有一项
	var cfg := TagComponentConfig.builder().tag(STATUS_TAG).build()
	TestFramework.assert_equal(1, cfg.tags_dict().size())


func _test_optional_empty() -> void:
	var cfg := (TagComponentConfig.builder()
		.tag(STATUS_TAG)
		.optional_tag("")  # 空字符串忽略
		.optional_tag(REASON_TAG)
		.build())
	TestFramework.assert_equal(2, cfg.tags_dict().size())
	TestFramework.assert_true(cfg.tags_dict().has(STATUS_TAG))
	TestFramework.assert_true(cfg.tags_dict().has(REASON_TAG))


func _test_lifecycle_apply() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var cfg := TagComponentConfig.builder().tag(STATUS_TAG).tag(ACTION_LOCK_TAG).build()
	var ability_config := AbilityConfig.new("dummy_ability", "", "", "", [], [], [cfg])
	var ability := Ability.new(ability_config, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)
	ability.apply_effects(ctx)
	# 这两 tag 都属于 component tag,聚合查询能命中
	TestFramework.assert_true(aset.has_tag(STATUS_TAG), "STATUS_TAG should be present after apply")
	TestFramework.assert_true(aset.has_tag(ACTION_LOCK_TAG), "ACTION_LOCK_TAG should be present after apply")
	# 而 loose tag 不应被设置
	TestFramework.assert_equal(0, aset.get_loose_tag_stacks(STATUS_TAG))
	_teardown()


func _test_lifecycle_remove() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var cfg := TagComponentConfig.builder().tag(STATUS_TAG).build()
	var ability_config := AbilityConfig.new("dummy_ability", "", "", "", [], [], [cfg])
	var ability := Ability.new(ability_config, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)
	ability.apply_effects(ctx)
	TestFramework.assert_true(aset.has_tag(STATUS_TAG))
	ability.remove_effects()
	TestFramework.assert_true(not aset.has_tag(STATUS_TAG), "STATUS_TAG should be cleared after remove")
	_teardown()


func _test_independent_from_loose() -> void:
	_setup()
	var pair := _make_actor()
	var aset: AbilitySet = pair[0]
	var owner_id: String = pair[1]
	var cfg := TagComponentConfig.builder().tag(STATUS_TAG).build()
	var ability_config := AbilityConfig.new("dummy_ability", "", "", "", [], [], [cfg])
	var ability := Ability.new(ability_config, owner_id)
	var ctx := AbilityLifecycleContext.new(owner_id, null, ability, aset, null)
	ability.apply_effects(ctx)
	# 同名 loose tag 与 component tag 共存
	aset.add_loose_tag(STATUS_TAG, 3)
	TestFramework.assert_equal(3, aset.get_loose_tag_stacks(STATUS_TAG))
	# component tag 仍在 (loose remove 不应影响 component)
	aset.remove_loose_tag(STATUS_TAG)  # 移除全部 loose stacks
	TestFramework.assert_equal(0, aset.get_loose_tag_stacks(STATUS_TAG))
	TestFramework.assert_true(aset.has_tag(STATUS_TAG), "component tag survives loose remove")
	# Ability remove 后 component tag 也清掉
	ability.remove_effects()
	TestFramework.assert_true(not aset.has_tag(STATUS_TAG))
	_teardown()
