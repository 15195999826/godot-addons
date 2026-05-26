## Phase B · VampiricTraining 50% → Strike 命中 heal = actual_life_damage * 0.5
##
## V1 契约:
## - VampiricTraining (passive) 通过 StatModifier 给 owner +0.5 attack_lifesteal_pct
## - Strike 命中 → BasicAttackLandedEvent → HexBattleGeneralPassive 监听 →
##   读 attacker.attack_lifesteal_pct = 0.5 → 调 HexBattleHealAction heal 0.5 * actual_life_damage
## - heal event source/target = caster (attacker 自治)
##
## 时序:
##   t=0   caster atk=40 cast Strike enemy_0 → HIT @ t=300
##           → damage event actual_life_damage=40 (无 shield, 无 equipment crit)
##           → BasicAttackLandedEvent 携 actual_life_damage
##           → GeneralPassive heal caster 40*0.5=20
class_name LifestealAttributeBasicScenario
extends SkillScenario


const CASTER_ATK := 40.0
const CASTER_START_HP := 100.0
const CASTER_MAX_HP := 200.0


func get_name() -> String:
	return "AttackLifesteal: VampiricTraining 50% → heal = actual_life_damage * 0.5"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": CASTER_START_HP, "max_hp": CASTER_MAX_HP, "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVampiricTraining.ABILITY]


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. 主伤害命中事件
	var main_damages := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_eq(main_damages.size(), 1, "Expect 1 main damage event")
	if main_damages.size() != 1:
		return

	var actual: float = main_damages[0].get("actual_life_damage", main_damages[0].get("damage", 0.0)) as float
	ctx.assert_float_eq(actual, CASTER_ATK, "actual_life_damage = caster atk")
	var expected_heal: float = actual * HexBattleVampiricTraining.LIFESTEAL_PCT

	# 2. heal event on caster, amount = actual * 0.5
	var heal_events: Array = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "heal":
			continue
		if str(e.get("target_actor_id", "")) != ctx.caster_id:
			continue
		heal_events.append(e)
	ctx.assert_eq(heal_events.size(), 1,
		"Expect 1 heal event on caster, got %d" % heal_events.size())
	if heal_events.size() != 1:
		return
	var heal_amount := heal_events[0].get("amount", heal_events[0].get("heal_amount", 0.0)) as float
	ctx.assert_float_eq(heal_amount, expected_heal,
		"Heal amount = actual_life_damage %.1f * %.2f = %.1f (got %.1f)" % [actual, HexBattleVampiricTraining.LIFESTEAL_PCT, expected_heal, heal_amount],
		1.0)

	# 3. caster final hp = start + heal
	var final_hp := ctx.actor_final_hp(ctx.caster_id)
	ctx.assert_float_eq(final_hp, CASTER_START_HP + expected_heal,
		"After lifesteal, caster hp = start hp + heal")
