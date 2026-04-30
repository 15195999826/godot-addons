## Strike 基础伤害契约场景：caster.atk 通过 Resolver 实时读取 → 伤害数值正确
##
## caster.atk = 77（覆盖 WARRIOR 默认 50），target 满血 1000
## Strike 内置 10% crit → 命中伤害 = 77 或 77 * 1.5 = 115.5
class_name StrikeScenario
extends SkillScenario


const EXPECTED_ATK := 77.0


func get_name() -> String:
	return "Strike damage = caster.atk (77 or 115.5 crit)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": EXPECTED_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
		"target":  {"mode": "auto"},
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 50


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var target := ctx.enemy_id(0)
	var dmgs := ctx.filter_damage_events({"target_actor_id": target})

	if dmgs.is_empty():
		ctx.fail("no damage event captured (Strike never fired)")
		return

	# 第一次 Strike 命中的主伤害（crit bonus 如有,会紧随其后）
	var main_damage: float = dmgs[0].get("damage", -1.0)
	ctx.assert_float_in(main_damage, [EXPECTED_ATK, EXPECTED_ATK * 1.5],
		"Strike main damage matches caster.atk (crit or no-crit)")
