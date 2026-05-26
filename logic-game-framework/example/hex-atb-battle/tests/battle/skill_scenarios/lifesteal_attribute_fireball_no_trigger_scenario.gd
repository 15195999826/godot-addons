## Phase B · VampiricTraining + Fireball → 不触发普攻吸血
##
## V1 契约:
##   active skill damage (Fireball 等) 不触发普攻吸血
##   (Fireball 不发 BasicAttackLandedEvent → GeneralPassive 不收 trigger → 不 heal)
##
## 即使 caster 持有 VampiricTraining (attack_lifesteal_pct=0.5), Fireball 命中也不回血,
## 因为 contract 只走 basic_attack_landed → general_passive 这一条 path.
class_name LifestealAttributeFireballNoTriggerScenario
extends SkillScenario


func get_name() -> String:
	return "AttackLifesteal: Fireball does NOT trigger lifesteal"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 5, "cols": 5},
		"caster":  {"class": "MAGE", "pos": [0, 0], "hp": 100, "max_hp": 200},
		"enemies": [{"class": "WARRIOR", "pos": [3, 0], "hp": 1000}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVampiricTraining.ABILITY]


func get_active_skill() -> AbilityConfig:
	return HexBattleFireball.ABILITY


func get_max_ticks() -> int:
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Sanity: Fireball 命中 (有 magical damage 事件)
	var fireballs := ctx.filter_damage_events({
		"target_actor_id": ctx.enemy_id(0),
		"damage_type": "magical",
	})
	ctx.assert_true(fireballs.size() >= 1, "Fireball did hit (sanity)")

	# Sanity: Fireball 不该产生 BasicAttackLandedEvent (Phase A 已测, 此处复测保险)
	var attack_events := ctx.events_of_kind("basic_attack_landed")
	ctx.assert_eq(attack_events.size(), 0, "Fireball produces no BasicAttackLandedEvent")

	# 核心契约: 没有 heal event (即使 caster 有 VampiricTraining)
	var heal_events := ctx.events_of_kind("heal")
	ctx.assert_eq(heal_events.size(), 0,
		"No heal events when only Fireball used (got %d)" % heal_events.size())
