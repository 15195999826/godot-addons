## Phase B · VampiricTraining + target ward 全吸 → 不回血
##
## V1 契约 (per advanced-skills-next-batch.md):
##   shield 全吸收时 actual_life_damage = 0, 不回血
##
## 设定:
##   caster atk=20 → 主伤 20 (或 crit 30) ≤ ward cap 30 → 全吸 actual_life_damage=0
##   crit 路径: 主伤 30 全吸 + crit bonus 10 击穿 = 实际 10 命中, AttackLandedEvent 仍是主伤的 (actual=0)
##   核心断言: 主伤 attack_landed 的 actual_life_damage=0 → GeneralPassive 早退, 无 heal
class_name LifestealAttributeShieldNoHealScenario
extends SkillScenario


const CASTER_ATK := 20.0


func get_name() -> String:
	return "AttackLifesteal: shield full absorb → actual=0 → no heal"


func get_scene_config() -> Dictionary:
	# enemy 持 WardBuff → 吸收 caster Strike 主伤; caster 自带 VampiricTraining 但 actual=0 时不该 heal.
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 100, "max_hp": 200, "atk": CASTER_ATK},
		"enemies": [{
			"class": "WARRIOR",
			"pos": [1, 0],
			"hp": 500,
			"passives": [HexBattleWardBuff.WARD_BUFF],
		}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVampiricTraining.ABILITY]


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Sanity: 有 AttackLandedEvent (主伤) actual_life_damage = 0
	var attack_events := ctx.events_of_kind("attack_landed")
	ctx.assert_true(attack_events.size() >= 1, "Strike emitted at least 1 AttackLandedEvent")
	ctx.assert_float_eq(attack_events[0].get("actual_life_damage", -1.0) as float, 0.0,
		"Main strike actual_life_damage=0 (ward fully absorbed)")

	# 核心契约: caster 不应被 heal (全吸的主伤不 trigger lifesteal)
	var heal_to_caster: Array = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "heal":
			continue
		if str(e.get("target_actor_id", "")) != ctx.caster_id:
			continue
		heal_to_caster.append(e)
	ctx.assert_eq(heal_to_caster.size(), 0,
		"Expect 0 heal events on caster when main strike fully absorbed (got %d)" % heal_to_caster.size())
