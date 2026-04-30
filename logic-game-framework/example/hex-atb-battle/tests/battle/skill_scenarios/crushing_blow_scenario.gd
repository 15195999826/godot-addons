## CrushingBlow 重击场景：WINDUP 300ms 后 HIT 600ms 一次 90 physical
class_name CrushingBlowScenario
extends SkillScenario


const DAMAGE := 90.0


func get_name() -> String:
	return "CrushingBlow single 90 physical hit"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "BERSERKER", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleCrushingBlow.ABILITY


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var target := ctx.enemy_id(0)
	var hits := ctx.filter_damage_events({
		"target_actor_id": target,
		"damage_type": "physical",
	})
	ctx.assert_eq(hits.size(), 1, "exactly 1 CrushingBlow hit")
	if hits.size() >= 1:
		var dmg: float = hits[0].get("damage", 0.0)
		ctx.assert_float_in(dmg, [DAMAGE, DAMAGE * 1.5],
			"damage = 90 or 135 (crit)")
