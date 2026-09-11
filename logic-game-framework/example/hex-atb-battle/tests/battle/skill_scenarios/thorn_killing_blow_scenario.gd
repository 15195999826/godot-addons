## Thorn 致死一击场景：enemy 一击打死带 Thorn 的 caster，Thorn 仍反弹 2 PURE
##
## 关键 pattern 验证：
##   - post damage 派发时 caster 已判死，HexBattleActor.is_event_responsive 让死者仍响应自己作为 target 的 damage
##   - 回退这条豁免（死者一律不响应 post），反伤不会发生，本场景变红
class_name ThornKillingBlowScenario
extends SkillScenario


const REFLECT_DAMAGE := 2.0


func get_name() -> String:
	return "Thorn still reflects on the blow that kills its owner"


func get_scene_config() -> Dictionary:
	# caster hp=50，enemy_0 atk=100 一击毙命；enemy hp 拉高，反伤不会误杀。
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 50},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": 100, "hp": 500}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleThorn.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	ctx.assert_float_eq(ctx.actor_final_hp(ctx.caster_id), 0.0, "caster dead after kill blow")

	var reflected := ctx.filter_damage_events({
		"target_actor_id": ctx.enemy_id(0),
		"damage_type": "pure",
	})
	ctx.assert_eq(reflected.size(), 1, "Thorn reflects once on the killing blow")
	for r in reflected:
		ctx.assert_float_eq(r.get("damage", 0.0) as float, REFLECT_DAMAGE,
			"Thorn reflected damage = 2")
