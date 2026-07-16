extends Node

## ActiveUse 激活门纯查询（can_activate 干跑）回归测试
##
## 覆盖：
##  - allowed 路径零副作用（不扣资源、不 push 事件、不创建 execution、可重入）
##  - condition / cost 失败的结构化 denied 结果（reason 与 get_fail_reason 同源）
##  - 查询失败不 push AbilityActivateFailed（对照真实激活路径会 push）
##  - Ability 级短路与 receive_event 同判（disabled / expired）
##  - timeline 未注册同判拒绝
##  - 查询 allowed 后真实激活仍正常支付（查询不预扣）
##  - 多 ActiveUse 组件：首个失败门返回

const QUERY_TIMELINE_ID := "t-active-use-query"


func _init() -> void:
	TestFramework.register_test("can_activate allows with zero side effects", _test_allowed_zero_side_effects)
	TestFramework.register_test("can_activate denies on condition without pushing events", _test_denied_by_condition)
	TestFramework.register_test("can_activate denies on cost and keeps resources", _test_denied_by_cost)
	TestFramework.register_test("can_activate mirrors receive_event short-circuits", _test_ability_level_shortcircuits)
	TestFramework.register_test("can_activate denies on missing timeline", _test_missing_timeline)
	TestFramework.register_test("can_activate does not pre-pay real activation", _test_query_then_real_activation)
	TestFramework.register_test("can_activate returns first failing gate across components", _test_multi_component_first_failure)


## 构造 "granted ability + ability_set" 夹具；conditions/costs 注入唯一的 ActiveUseConfig。
func _build_fixture(conditions: Array[Condition], costs: Array[Cost],
		timeline_id: String = QUERY_TIMELINE_ID) -> Dictionary:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(QUERY_TIMELINE_ID, 100.0, {}))
	GameWorld.init()
	var active_use := ActiveUseConfig.new(timeline_id, [], conditions, costs)
	var active_use_list: Array[ActiveUseConfig] = [active_use]
	var config := AbilityConfig.new("q-skill", "", "", "", [], active_use_list, [])
	var ability := Ability.new(config, "actor-q")
	var ability_set := AbilitySet.create("actor-q")
	ability_set.grant_ability(ability)
	GameWorld.event_collector.clear()
	return {"set": ability_set, "ability": ability}


func _test_allowed_zero_side_effects() -> void:
	var conditions: Array[Condition] = [Condition.HasTagCondition.new("ready")]
	var costs: Array[Cost] = [Cost.ConsumeTagCost.new("ammo", 1)]
	var fixture := _build_fixture(conditions, costs)
	var ability_set: AbilitySet = fixture["set"]
	var ability: Ability = fixture["ability"]
	ability_set.add_loose_tag("ready")
	ability_set.add_loose_tag("ammo", 2)

	var result := ability_set.can_activate(ability)
	TestFramework.assert_true(AbilityActivationQuery.is_allowed(result))
	TestFramework.assert_equal("", result[AbilityActivationQuery.KEY_REASON])
	TestFramework.assert_equal("", result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])

	# 零副作用：资源未扣、无事件入队、无 execution 创建
	TestFramework.assert_equal(2, ability_set.get_loose_tag_stacks("ammo"))
	TestFramework.assert_equal(0, GameWorld.event_collector.get_count())
	TestFramework.assert_equal(0, ability.get_executing_instances().size())

	# 可重入：重复查询结果一致，状态依旧不动
	var repeated := ability_set.can_activate(ability)
	TestFramework.assert_true(AbilityActivationQuery.is_allowed(repeated))
	TestFramework.assert_equal(2, ability_set.get_loose_tag_stacks("ammo"))
	TestFramework.assert_equal(0, GameWorld.event_collector.get_count())


func _test_denied_by_condition() -> void:
	var conditions: Array[Condition] = [Condition.NoTagCondition.new("stunned")]
	var costs: Array[Cost] = []
	var fixture := _build_fixture(conditions, costs)
	var ability_set: AbilitySet = fixture["set"]
	var ability: Ability = fixture["ability"]
	ability_set.add_loose_tag("stunned")

	var result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_CONDITION,
		result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])
	# reason 与激活失败事件同源（condition.get_fail_reason）
	TestFramework.assert_equal("已有 Tag: stunned", result[AbilityActivationQuery.KEY_REASON])
	# 查询是纯读：不像真实激活路径那样 push AbilityActivateFailed
	TestFramework.assert_equal(0, GameWorld.event_collector.get_count())

	# 对照：真实激活路径对同一失败会 push AbilityActivateFailed
	var activate_dict := GameEvent.AbilityActivate.create(ability.id, "actor-q").to_dict()
	ability_set.receive_event(activate_dict, null)
	var failed_events := GameWorld.event_collector.filter_by_kind(
		GameEvent.ABILITY_ACTIVATE_FAILED_EVENT)
	TestFramework.assert_equal(1, failed_events.size())


func _test_denied_by_cost() -> void:
	var conditions: Array[Condition] = []
	var costs: Array[Cost] = [Cost.ConsumeTagCost.new("ammo", 3)]
	var fixture := _build_fixture(conditions, costs)
	var ability_set: AbilitySet = fixture["set"]
	var ability: Ability = fixture["ability"]
	ability_set.add_loose_tag("ammo", 1)

	var result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_COST,
		result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])
	TestFramework.assert_equal("ammo 层数不足: 1/3", result[AbilityActivationQuery.KEY_REASON])
	TestFramework.assert_equal(1, ability_set.get_loose_tag_stacks("ammo"))
	TestFramework.assert_equal(0, GameWorld.event_collector.get_count())


func _test_ability_level_shortcircuits() -> void:
	var conditions: Array[Condition] = []
	var costs: Array[Cost] = []
	var fixture := _build_fixture(conditions, costs)
	var ability_set: AbilitySet = fixture["set"]
	var ability: Ability = fixture["ability"]

	TestFramework.assert_true(AbilityActivationQuery.is_allowed(ability_set.can_activate(ability)))

	# disabled：receive_event 顶层短路，查询同判
	ability.add_disabled_source("break-1")
	var disabled_result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(disabled_result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_ABILITY,
		disabled_result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])

	ability.remove_disabled_source("break-1")
	TestFramework.assert_true(AbilityActivationQuery.is_allowed(ability_set.can_activate(ability)))

	# expired：非 granted 状态同判拒绝
	ability.expire("test")
	var expired_result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(expired_result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_ABILITY,
		expired_result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])


func _test_missing_timeline() -> void:
	var conditions: Array[Condition] = []
	var costs: Array[Cost] = []
	var fixture := _build_fixture(conditions, costs, "t-query-not-registered")
	var ability_set: AbilitySet = fixture["set"]
	var ability: Ability = fixture["ability"]

	var result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_TIMELINE,
		result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])


func _test_query_then_real_activation() -> void:
	var conditions: Array[Condition] = []
	var costs: Array[Cost] = [Cost.ConsumeTagCost.new("ammo", 1)]
	var fixture := _build_fixture(conditions, costs)
	var ability_set: AbilitySet = fixture["set"]
	var ability: Ability = fixture["ability"]
	ability_set.add_loose_tag("ammo", 1)

	# 查询 allowed 且不预扣
	TestFramework.assert_true(AbilityActivationQuery.is_allowed(ability_set.can_activate(ability)))
	TestFramework.assert_equal(1, ability_set.get_loose_tag_stacks("ammo"))

	# 真实激活：默认 ABILITY_ACTIVATE trigger 命中 → 支付 + 创建 execution
	var activate_dict := GameEvent.AbilityActivate.create(ability.id, "actor-q").to_dict()
	ability_set.receive_event(activate_dict, null)
	TestFramework.assert_equal(0, ability_set.get_loose_tag_stacks("ammo"))
	TestFramework.assert_equal(1, ability.get_executing_instances().size())

	# 资源已耗尽，查询翻转为 denied（读到与激活门同一个世界）
	var drained_result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(drained_result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_COST,
		drained_result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])


func _test_multi_component_first_failure() -> void:
	TimelineRegistry.reset()
	TimelineRegistry.register(TimelineData.new(QUERY_TIMELINE_ID, 100.0, {}))
	GameWorld.init()
	var pass_conditions: Array[Condition] = []
	var no_costs: Array[Cost] = []
	var blocked_conditions: Array[Condition] = [Condition.NoTagCondition.new("sealed")]
	var first_use := ActiveUseConfig.new(QUERY_TIMELINE_ID, [], pass_conditions, no_costs)
	var second_use := ActiveUseConfig.new(QUERY_TIMELINE_ID, [], blocked_conditions, no_costs)
	var active_use_list: Array[ActiveUseConfig] = [first_use, second_use]
	var config := AbilityConfig.new("q-multi", "", "", "", [], active_use_list, [])
	var ability := Ability.new(config, "actor-q")
	var ability_set := AbilitySet.create("actor-q")
	ability_set.grant_ability(ability)
	GameWorld.event_collector.clear()

	TestFramework.assert_true(AbilityActivationQuery.is_allowed(ability_set.can_activate(ability)))

	ability_set.add_loose_tag("sealed")
	var result := ability_set.can_activate(ability)
	TestFramework.assert_false(AbilityActivationQuery.is_allowed(result))
	TestFramework.assert_equal(AbilityActivationQuery.FAILED_CONDITION,
		result[AbilityActivationQuery.KEY_FAILED_COMPONENT_TYPE])
	TestFramework.assert_equal("已有 Tag: sealed", result[AbilityActivationQuery.KEY_REASON])
