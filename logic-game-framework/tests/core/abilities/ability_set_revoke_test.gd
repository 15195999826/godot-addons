extends Node

## AbilitySet 批量 revoke 出口合同
##
## core 只留两个 revoke 出口：revoke_ability(id) 单个退场、revoke_abilities_where(predicate) 按条件批量退场——
## 条件由游戏层写（config_id / tag / source / 全部……），core 不为任一种条件立专用动词。钉三条：
## ① 只 revoke predicate 命中的，每个都经 revoke_ability 正规退场（expire → 除名 → revoked 回调），返回条数；
## ② 遍历命中快照：前面的命中者退场让活数组左移、某个命中者的 on_remove 里再 revoke 别的命中者，都不让后面的命中者
##    被跳过；已被连带退场的不二次退场（revoked 回调各恰一次），也不计入返回值；
## ③ reason 透传到 revoked 回调，expire_reason 缺省跟 reason。

const CONFIG_KEEP := "revoke_where_keep"
const CONFIG_DROP := "revoke_where_drop"
const CONFIG_CASCADE := "revoke_where_cascade"
const TAG_DROP := "revoke_where_drop_tag"


class ProbeActor:
	extends BattleActor

	var ability_set: AbilitySet

	func _init() -> void:
		type = "revoke_where_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set


## 在 on_remove 里 revoke 拥有者身上 config_id 的全部 ability（config_id 构造后只读，action 无状态）。
class RevokeByConfigAction:
	extends Action.BaseAction

	var config_id: String

	func _init(p_config_id: String) -> void:
		super._init(TargetSelector.new())
		config_id = p_config_id

	func execute(ctx: ExecutionContext) -> ActionResult:
		var owner_set := BattleActor.ability_set_of(ctx.instance.get_actor(ctx.ability_ref.owner_actor_id))
		var wanted := config_id
		owner_set.revoke_abilities_where(func(ability: Ability) -> bool: return ability.config_id == wanted)
		return ActionResult.create_success_result([])


func _init() -> void:
	TestFramework.register_test("AbilitySet.revoke_abilities_where revokes exactly the predicate hits through revoke_ability", _test_revokes_predicate_hits)
	TestFramework.register_test("AbilitySet.revoke_abilities_where walks a snapshot: cascade revoke inside on_remove neither skips nor double-revokes", _test_cascade_inside_on_remove)
	TestFramework.register_test("AbilitySet.revoke_abilities_where passes reason through to revoked listeners", _test_reason_passthrough)


func _test_revokes_predicate_hits() -> void:
	var actor := _spawn("revoke_where_hits")
	var drop_a := _grant(actor, CONFIG_DROP)
	var keep := _grant(actor, CONFIG_KEEP)
	var drop_b := _grant(actor, CONFIG_DROP)
	var revoked_ids: Array[String] = []
	actor.ability_set.on_ability_revoked(func(ability: Ability, _reason: String, _set: AbilitySet, _expire_reason: String) -> void:
		revoked_ids.append(ability.id))

	var count := actor.ability_set.revoke_abilities_where(func(ability: Ability) -> bool:
		return ability.config_id == CONFIG_DROP)

	TestFramework.assert_equal(2, count)
	TestFramework.assert_equal(",".join([drop_a.id, drop_b.id]), ",".join(revoked_ids))
	TestFramework.assert_true(drop_a.is_expired() and drop_b.is_expired(), "命中的每个都经 revoke_ability 正规退场")
	TestFramework.assert_false(keep.is_expired(), "不命中的不动")
	TestFramework.assert_equal(1, actor.ability_set.get_ability_count())
	TestFramework.assert_true(actor.ability_set.find_ability_by_id(keep.id) == keep)
	var none := actor.ability_set.revoke_abilities_where(func(_ability: Ability) -> bool: return false)
	TestFramework.assert_equal(0, none)
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


## 集合顺序 [drop_a, cascade, drop_x, drop_c, keep]，predicate 命中前四个；cascade 的 on_remove 里再 revoke 全部 CONFIG_DROP。
## 活数组遍历会在 drop_a 退场后左移、跳过 cascade；快照遍历下 cascade 正常退场，其 on_remove 连带退掉仍在集里的
## drop_x 与 drop_c，主循环再遇到两者时 revoke_ability 返回 false——revoked 回调各恰一次，返回值只数本调用亲手 revoke 的两条。
func _test_cascade_inside_on_remove() -> void:
	var actor := _spawn("revoke_where_cascade")
	var drop_tags: Array[String] = [TAG_DROP]
	var drop_a := _grant(actor, CONFIG_DROP, drop_tags)
	var remove_actions: Array[Action.BaseAction] = [RevokeByConfigAction.new(CONFIG_DROP)]
	var cascade := Ability.new((AbilityConfig.builder()
		.config_id(CONFIG_CASCADE)
		.ability_tags(drop_tags)
		.component_config(NoInstanceConfig.builder().on_remove_actions(remove_actions).build())
		.build()), actor.get_id())
	actor.ability_set.grant_ability(cascade)
	var drop_x := _grant(actor, CONFIG_DROP, drop_tags)
	var drop_c := _grant(actor, CONFIG_DROP, drop_tags)
	var keep := _grant(actor, CONFIG_KEEP)
	var revoked_ids: Array[String] = []
	actor.ability_set.on_ability_revoked(func(ability: Ability, _reason: String, _set: AbilitySet, _expire_reason: String) -> void:
		revoked_ids.append(ability.id))

	var count := actor.ability_set.revoke_abilities_where(func(ability: Ability) -> bool:
		return ability.has_ability_tag(TAG_DROP))

	TestFramework.assert_equal(2, count)
	TestFramework.assert_equal(1, actor.ability_set.get_ability_count())
	TestFramework.assert_true(actor.ability_set.find_ability_by_id(keep.id) == keep, "不命中的 ability 不受牵连")
	TestFramework.assert_equal(4, revoked_ids.size())
	for ability: Ability in [drop_a, cascade, drop_x, drop_c]:
		TestFramework.assert_true(ability.is_expired(), "%s 应已退场" % ability.config_id)
		TestFramework.assert_equal(1, revoked_ids.count(ability.id))
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


func _test_reason_passthrough() -> void:
	var actor := _spawn("revoke_where_reason")
	var first := _grant(actor, CONFIG_DROP)
	var reasons: Array[String] = []
	var expire_reasons: Array[String] = []
	actor.ability_set.on_ability_revoked(func(_ability: Ability, reason: String, _set: AbilitySet, expire_reason: String) -> void:
		reasons.append(reason)
		expire_reasons.append(expire_reason))
	var is_drop := func(ability: Ability) -> bool: return ability.config_id == CONFIG_DROP

	actor.ability_set.revoke_abilities_where(is_drop, AbilitySet.REVOKE_REASON_DISPELLED)
	var second := _grant(actor, CONFIG_DROP)
	actor.ability_set.revoke_abilities_where(is_drop)

	TestFramework.assert_equal(",".join([AbilitySet.REVOKE_REASON_DISPELLED, AbilitySet.REVOKE_REASON_MANUAL]), ",".join(reasons))
	TestFramework.assert_equal(",".join(reasons), ",".join(expire_reasons))
	TestFramework.assert_equal(AbilitySet.REVOKE_REASON_DISPELLED, first.get_expire_reason())
	TestFramework.assert_equal(AbilitySet.REVOKE_REASON_MANUAL, second.get_expire_reason())
	GameWorld.destroy_instance(actor.get_gameplay_instance_id())


# ========== 夹具 ==========

static func _spawn(instance_id: String) -> ProbeActor:
	var instance := GameWorld.create_instance(GameplayInstance.new(instance_id))
	return instance.add_actor(ProbeActor.new()) as ProbeActor


## grant 一个无 component 的 ability（config_id + ability tags 足够让 predicate 分辨）。
static func _grant(actor: ProbeActor, config_id: String, tags: Array[String] = []) -> Ability:
	var ability := Ability.new(AbilityConfig.builder().config_id(config_id).ability_tags(tags).build(), actor.get_id())
	actor.ability_set.grant_ability(ability)
	return ability
