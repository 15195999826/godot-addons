## SwiftStrike 三连击场景：验证 3 个 HIT tag 各产生一次 10 physical(或 15 crit)
class_name SwiftStrikeScenario
extends SkillScenario


const HIT_DAMAGE := 10.0


func get_name() -> String:
	return "SwiftStrike 3x 10 physical hits"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleSwiftStrike.ABILITY


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var target := ctx.enemy_id(0)
	var hits := ctx.filter_damage_events({
		"target_actor_id": target,
		"damage_type": "physical",
	})
	ctx.assert_eq(hits.size(), 3, "3 hits from SwiftStrike")
	for i in range(hits.size()):
		var dmg: float = hits[i].get("damage", 0.0)
		ctx.assert_float_in(dmg, [HIT_DAMAGE, HIT_DAMAGE * 1.5],
			"hit #%d damage = 10 or 15 (crit)" % (i + 1))
