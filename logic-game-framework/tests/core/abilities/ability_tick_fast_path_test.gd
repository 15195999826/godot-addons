extends Node

## AbilitySet 每帧推进的快速路径
##
## 随时间推进的 component 交函数、不交类型，也不设开关。钉六条：
## ① 从 get_tick_callable 交出函数的 component 每帧被推进、拿到 dt；
## ② 只有一个叫 on_tick 的方法、没交函数的 component 不被推进——基类没有按名字调的钩子；
## ③ 没有任何 ability 交了函数的 set，tick 不走那趟遍历；有一个就走；它退场后又不走（每帧现判，不记计数）；
## ④ 没有 execution 在飞时 tick_executions 不进门；
## ⑤ TimeDurationComponent 经交出的函数到期，由同一趟 tick 回收（expired / time_duration）；
## ⑥ TagContainer 没有计时 tag 时 tick 只拨钟，有计时 tag 时照常到期并通知；
## ⑦ 计时 tag 到期那一趟 tick 广播 TagChanged，old 是到期前的层数（拨钟后数到的 + 本次到期条数），
##    同 tag 同趟多条到期只广播一次，未到期的趟不广播。


## 数 _process_abilities 被叫了几次：「不走那趟遍历」只在这里可观测。
class TraversalProbeSet:
	extends AbilitySet

	var traversals := 0

	func _process_abilities(processor: Callable) -> void:
		traversals += 1
		super._process_abilities(processor)


class ProbeActor:
	extends BattleActor

	var ability_set: AbilitySet

	func _init() -> void:
		type = "tick_fast_path_probe"
		ability_set = TraversalProbeSet.new("")

	func get_ability_set() -> AbilitySet:
		return ability_set


## 交出推进函数的 component：每次被推进把 dt 记下来。
class CountingTickerComponent:
	extends AbilityComponent

	var ticks: Array[float] = []

	func _init() -> void:
		type = "counting_ticker"

	func get_tick_callable() -> Callable:
		return _advance

	func _advance(dt: float) -> void:
		ticks.append(dt)


## 只有一个叫 on_tick 的方法、没交函数：不该被推进。
class NamedOnTickComponent:
	extends AbilityComponent

	var calls := 0

	func _init() -> void:
		type = "named_on_tick"

	func on_tick(_dt: float) -> void:
		calls += 1


## 把现成的 component 实例交给 Ability（测试要拿着它读计数）。
class ProbeComponentConfig:
	extends AbilityComponentConfig

	var component: AbilityComponent

	func _init(p_component: AbilityComponent) -> void:
		component = p_component

	func create_component() -> AbilityComponent:
		return component


func _init() -> void:
	TestFramework.register_test("Ability ticks the callable a component hands over via get_tick_callable, passing dt", _test_handed_over_callable_is_ticked)
	TestFramework.register_test("Ability never calls a component method by the name on_tick: no callable handed over, no tick", _test_named_on_tick_is_not_a_hook)
	TestFramework.register_test("AbilitySet.tick skips the traversal when no ability needs a tick, judged afresh each frame", _test_tick_skips_traversal_without_tickers)
	TestFramework.register_test("AbilitySet.tick_executions does not enter when nothing is executing", _test_tick_executions_skips_without_executions)
	TestFramework.register_test("TimeDurationComponent expires through the handed-over callable and is reclaimed by the same tick", _test_time_duration_expires_and_is_reclaimed)
	TestFramework.register_test("TagContainer.tick only moves the clock without auto-duration tags and still expires them when present", _test_tag_container_tick_without_and_with_timed_tags)
	TestFramework.register_test("TagContainer broadcasts TagChanged on expiry with the pre-expiry stack count, once per tag per tick", _test_tag_container_expiry_broadcasts_tag_changed)


func _test_handed_over_callable_is_ticked() -> void:
	var actor := _spawn("tick_fast_path_handed_over")
	var ticker := CountingTickerComponent.new()
	var ability := _grant(actor, "ticking", ticker)

	TestFramework.assert_true(ability.needs_tick(), "交了函数的 ability 需要 tick")
	for i in 3:
		actor.ability_set.tick(10.0, 10.0 * (i + 1))

	TestFramework.assert_equal(3, ticker.ticks.size())
	TestFramework.assert_equal(10.0, ticker.ticks[0])
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


func _test_named_on_tick_is_not_a_hook() -> void:
	var actor := _spawn("tick_fast_path_named_on_tick")
	var named := NamedOnTickComponent.new()
	var ability := _grant(actor, "named", named)

	TestFramework.assert_false(ability.needs_tick(), "没交函数就不需要 tick")
	for i in 3:
		actor.ability_set.tick(10.0, 10.0 * (i + 1))

	TestFramework.assert_true(named.calls == 0, "叫 on_tick 的方法不是钩子")
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


## grant 自投递也经 _process_abilities，所以每段都从 grant 之后的计数起算。
func _test_tick_skips_traversal_without_tickers() -> void:
	var actor := _spawn("tick_fast_path_skip")
	var probe_set := actor.ability_set as TraversalProbeSet
	_grant_plain(actor, "static_buff")
	var before := probe_set.traversals
	actor.ability_set.tick(10.0, 10.0)
	actor.ability_set.tick(10.0, 20.0)
	TestFramework.assert_true(probe_set.traversals == before, "没有 ability 交函数：tick 不走遍历")

	var ticker := CountingTickerComponent.new()
	var ticking := _grant(actor, "ticking", ticker)
	before = probe_set.traversals
	actor.ability_set.tick(10.0, 30.0)
	TestFramework.assert_true(probe_set.traversals == before + 1, "有一个交了函数：走遍历")
	TestFramework.assert_equal(1, ticker.ticks.size())

	actor.ability_set.revoke_ability(ticking.id)
	before = probe_set.traversals
	actor.ability_set.tick(10.0, 40.0)
	TestFramework.assert_true(probe_set.traversals == before, "交函数的退场后又不走：每帧现判，不记计数")
	TestFramework.assert_equal(1, ticker.ticks.size())
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


func _test_tick_executions_skips_without_executions() -> void:
	var actor := _spawn("tick_fast_path_exec_skip")
	var probe_set := actor.ability_set as TraversalProbeSet
	_grant_plain(actor, "static_buff")
	_grant(actor, "ticking", CountingTickerComponent.new())
	var before := probe_set.traversals

	var triggered := actor.ability_set.tick_executions(10.0)

	TestFramework.assert_equal(0, triggered.size())
	TestFramework.assert_true(probe_set.traversals == before, "没有 execution 在飞：不进门")
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


func _test_time_duration_expires_and_is_reclaimed() -> void:
	var actor := _spawn("tick_fast_path_time_duration")
	var ability := Ability.new((AbilityConfig.builder()
		.config_id("timed")
		.component_config(TimeDurationConfig.new(100.0))
		.build()), actor.get_id())
	actor.ability_set.grant_ability(ability)
	var revoked: Array[String] = []
	actor.ability_set.on_ability_revoked(func(revoked_ability: Ability, reason: String, _set: AbilitySet, expire_reason: String) -> void:
		revoked.append("%s/%s/%s" % [revoked_ability.id, reason, expire_reason]))

	TestFramework.assert_true(ability.needs_tick(), "TimeDuration 交了函数")
	actor.ability_set.tick(60.0, 60.0)
	TestFramework.assert_false(ability.is_expired(), "60/100 未到期")
	TestFramework.assert_equal(1, actor.ability_set.get_ability_count())
	actor.ability_set.tick(60.0, 120.0)
	TestFramework.assert_true(ability.is_expired(), "120/100 到期")
	TestFramework.assert_true(actor.ability_set.get_ability_count() == 0, "由同一趟 tick 回收")
	TestFramework.assert_equal(
		"%s/%s/%s" % [ability.id, AbilitySet.REVOKE_REASON_EXPIRED, TimeDurationComponent.EXPIRE_REASON_TIME_DURATION],
		",".join(revoked))
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


func _test_tag_container_tick_without_and_with_timed_tags() -> void:
	var tags := TagContainer.create("tick_fast_path_tags")
	tags.tick(50.0)
	TestFramework.assert_near(tags.get_logic_time(), 50.0, 0.0001, "没有计时 tag：只拨钟（按 dt 累加）")
	tags.tick(0.0, 200.0)
	TestFramework.assert_near(tags.get_logic_time(), 200.0, 0.0001, "没有计时 tag：只拨钟（按 logic_time 对表）")

	var changes: Array[String] = []
	tags.on_tag_changed(func(tag: String, old_count: int, new_count: int, _container: TagContainer) -> void:
		changes.append("%s:%d>%d" % [tag, old_count, new_count]))
	tags.add_auto_duration_tag("cooldown", 100.0)
	TestFramework.assert_equal("cooldown:0>1", ",".join(changes))
	tags.tick(50.0, 250.0)
	TestFramework.assert_true(tags.has_tag("cooldown"), "250 < 300 未到期")
	TestFramework.assert_equal("cooldown:0>1", ",".join(changes))
	tags.tick(100.0, 350.0)
	TestFramework.assert_false(tags.has_tag("cooldown"), "350 >= 300 到期")
	TestFramework.assert_equal("cooldown:0>1,cooldown:1>0", ",".join(changes))


## 到期广播的 old 是到期前的层数：tick 先拨钟，此时 get_tag_stacks 已数不到到期条目，
## old 只能由「拨钟后数到的 + 本次到期条数」算出；loose 层与未到期的计时层都留在 new 里。
func _test_tag_container_expiry_broadcasts_tag_changed() -> void:
	var tags := TagContainer.create("tick_fast_path_expiry")
	var changes: Array[String] = []
	tags.on_tag_changed(func(tag: String, old_count: int, new_count: int, _container: TagContainer) -> void:
		changes.append("%s:%d>%d" % [tag, old_count, new_count]))

	# 同 tag 三层：一层 loose + 两条计时（到期 100 / 200），逐条到期各广播一次，层数按总数算
	tags.add_loose_tag("burning", 1)
	tags.add_auto_duration_tag("burning", 100.0)
	tags.add_auto_duration_tag("burning", 200.0)
	TestFramework.assert_equal("burning:0>1,burning:1>2,burning:2>3", ",".join(changes))
	changes.clear()
	tags.tick(50.0, 50.0)
	TestFramework.assert_true(changes.is_empty(), "没有到期的趟不广播")
	tags.tick(50.0, 100.0)
	TestFramework.assert_equal("burning:3>2", ",".join(changes))
	tags.tick(100.0, 200.0)
	TestFramework.assert_equal("burning:3>2,burning:2>1", ",".join(changes))
	TestFramework.assert_equal(1, tags.get_tag_stacks("burning"))
	TestFramework.assert_true(tags.has_tag("burning"), "loose 层不随计时层到期")

	# 同 tag 两条在同一趟一起到期：只广播一次，层数一次跳到位；别的 tag 互不干扰
	changes.clear()
	tags.add_auto_duration_tag("chill", 10.0)
	tags.add_auto_duration_tag("chill", 20.0)
	tags.add_auto_duration_tag("wet", 500.0)
	changes.clear()
	tags.tick(100.0, 300.0)
	TestFramework.assert_equal("chill:2>0", ",".join(changes))
	TestFramework.assert_false(tags.has_tag("chill"), "两条一起到期后无 chill")
	TestFramework.assert_true(tags.has_tag("wet"), "未到期的 wet 不受影响")
	tags.tick(100.0, 400.0)
	TestFramework.assert_equal("chill:2>0", ",".join(changes))


# ========== 夹具 ==========

static func _spawn(instance_id: String) -> ProbeActor:
	var instance := GameWorld.create_instance(GameplayInstance.new(instance_id))
	return instance.add_actor(ProbeActor.new()) as ProbeActor


static func _grant(actor: ProbeActor, config_id: String, component: AbilityComponent) -> Ability:
	var ability := Ability.new((AbilityConfig.builder()
		.config_id(config_id)
		.component_config(ProbeComponentConfig.new(component))
		.build()), actor.get_id())
	actor.ability_set.grant_ability(ability)
	return ability


static func _grant_plain(actor: ProbeActor, config_id: String) -> Ability:
	var ability := Ability.new(AbilityConfig.builder().config_id(config_id).build(), actor.get_id())
	actor.ability_set.grant_ability(ability)
	return ability
