## Phase F · Lifesteal - 基础命中按 actual_life_damage * ratio 吸血
##
## V1 契约:
## - shield 全吸收 → actual=0 不吸血 (留 follow-up scenario, 这里只测无 shield 命中)
## - 普通命中 → heal = damage * 0.5
##
## 时序:
##   t=0     caster atk=40 cast Lifesteal target enemy_0 → HIT @ t=300
##           → damage event source=caster target=enemy_0 damage=40 actual_life_damage=40 (无 shield)
##           → on_hit callback _LifestealHealAction → heal caster 40*0.5=20
##
## scene_config caster.hp 起始低于 max_hp, 让 heal 不 overcap clamp 到 max。
class_name LifestealBasicScenario
extends SkillScenario


const CASTER_ATK := 40.0
const LIFESTEAL_RATIO := 0.5
const CASTER_START_HP := 100.0
const CASTER_MAX_HP := 200.0


func get_name() -> String:
	return "Lifesteal: heal = actual_life_damage * 0.5 on normal hit"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": CASTER_START_HP, "max_hp": CASTER_MAX_HP, "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattleLifesteal.ABILITY,
			"target": "enemy_0",
			"time_ms": 0,
		},
	]


func get_max_ticks() -> int:
	return 20


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. enemy_0 受 damage 主伤害 ~40 (无 shield, actual_life_damage = 40, crit *1.5 = 60)
	var all_damages := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	# 过滤主 damage event (atk 40 / crit 60; crit bonus damage 10 单独)
	var main_damages: Array = []
	for e in all_damages:
		if (e.get("damage", 0.0) as float) >= 30.0:
			main_damages.append(e)
	ctx.assert_eq(main_damages.size(), 1, "Expect 1 main damage event")
	if main_damages.size() != 1:
		return

	var actual := main_damages[0].get("actual_life_damage", main_damages[0].get("damage", 0.0)) as float
	var expected_heal := actual * LIFESTEAL_RATIO

	# 2. heal event source/target=caster, amount ~= actual * 0.5
	var heal_events: Array = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "heal":
			continue
		if str(e.get("target_actor_id", "")) != ctx.caster_id:
			continue
		heal_events.append(e)
	ctx.assert_true(heal_events.size() >= 1,
		"Expect 1 heal event on caster (got %d)" % heal_events.size())
	if heal_events.size() >= 1:
		var heal_amount := heal_events[0].get("amount", heal_events[0].get("heal_amount", 0.0)) as float
		ctx.assert_float_eq(heal_amount, expected_heal,
			"Heal amount = actual_life_damage %.1f * 0.5 = %.1f (got %.1f)" % [actual, expected_heal, heal_amount],
			1.0)

	# 3. caster 期末 hp 升高 (100 + 20 = 120 no_crit, or 100 + 30 = 130 crit)
	var final_hp := ctx.actor_final_hp(ctx.caster_id)
	ctx.assert_true(final_hp > CASTER_START_HP,
		"After lifesteal, caster hp (%.1f) > start hp (%.1f)" % [final_hp, CASTER_START_HP])
