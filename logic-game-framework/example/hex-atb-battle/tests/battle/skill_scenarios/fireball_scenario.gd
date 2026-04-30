## Fireball 远程魔法投射物场景：cast 发射 fireball → 命中后 80 magical
class_name FireballScenario
extends SkillScenario


const DAMAGE := 80.0


func get_name() -> String:
	return "Fireball projectile hits for 80 magical"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 5, "cols": 5},
		"caster":  {"class": "MAGE", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [3, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleFireball.ABILITY


func get_max_ticks() -> int:
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var target := ctx.enemy_id(0)
	var hits := ctx.filter_damage_events({
		"target_actor_id": target,
		"damage_type": "magical",
	})
	ctx.assert_eq(hits.size(), 1, "exactly 1 Fireball hit")
	if hits.size() >= 1:
		var dmg: float = hits[0].get("damage", 0.0)
		ctx.assert_float_in(dmg, [DAMAGE, DAMAGE * 1.5],
			"damage = 80 or 120 (crit)")
