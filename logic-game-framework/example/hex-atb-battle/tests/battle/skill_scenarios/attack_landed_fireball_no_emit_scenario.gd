## Phase A · AttackLandedEvent 负面契约：非 Strike 伤害源不 emit
##
## V1 契约 (per advanced-skills-next-batch.md Phase A):
##   Fireball / Poison tick / reflected / Fire Tile / Totem passive 不产生 AttackLandedEvent
##
## 本 scenario 覆盖 Fireball (远程 magical, 不挂 on_hit attack_landed callback)。
## reflected / poison 等其它非 Strike damage 在另外 scenario 中覆盖。
class_name AttackLandedFireballNoEmitScenario
extends SkillScenario


func get_name() -> String:
	return "AttackLanded: Fireball does NOT emit AttackLandedEvent"


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
	# Fireball 应当命中 (damage event 存在), 但不携带 AttackLandedEvent。
	var dmgs := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	ctx.assert_true(dmgs.size() >= 1, "Fireball did fire damage (sanity)")

	var attack_events := ctx.events_of_kind("attack_landed")
	ctx.assert_eq(attack_events.size(), 0,
		"Fireball must NOT emit any AttackLandedEvent (got %d)" % attack_events.size())
