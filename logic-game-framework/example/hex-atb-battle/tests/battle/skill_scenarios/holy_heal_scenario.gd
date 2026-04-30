## HolyHeal 治疗场景：caster 对残血 ally 释放治疗，验证 heal_amount 正确
##
## HolyHeal 固定治疗 40.0，target 从 activate event.target_actor_id 来
class_name HolyHealScenario
extends SkillScenario


const HEAL_AMOUNT := 40.0
const ALLY_INITIAL_HP := 10.0
const ALLY_MAX_HP := 100.0


func get_name() -> String:
	return "HolyHeal heals ally for 40"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "PRIEST", "pos": [0, 0]},
		"allies":  [{"class": "WARRIOR", "pos": [1, 0], "hp": ALLY_INITIAL_HP}],
	}


func get_actions() -> Array[Dictionary]:
	return [{"caster": "caster", "skill": HexBattleHolyHeal.ABILITY, "target": "ally_0"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var ally := ctx.ally_id(0)
	var heals := ctx.filter_events({"kind": "heal", "target_actor_id": ally})
	ctx.assert_eq(heals.size(), 1, "exactly 1 heal event to ally")
	if heals.size() >= 1:
		ctx.assert_float_eq(heals[0].get("heal_amount", 0.0) as float, HEAL_AMOUNT,
			"heal amount = 40")
