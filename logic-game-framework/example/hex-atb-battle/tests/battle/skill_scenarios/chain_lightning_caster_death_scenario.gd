## Chain Lightning post-reaction regression.
##
## enemy_0 has Thorn. First hit reflects lethal damage to caster during post damage;
## the already-launched next projectile may still exist, but it must not resolve the
## next damage hop after the caster is dead.
class_name ChainLightningCasterDeathScenario
extends SkillScenario


func get_name() -> String:
	return "ChainLightning: caster 被 post reaction 反死后不继续结算下一跳 damage"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 5},
		"caster": {"class": "MAGE", "pos": [0, 0], "atk": 50, "hp": 1, "max_hp": 1},
		"enemies": [
			{
				"class": "WARRIOR",
				"pos": [1, 0],
				"hp": 1000,
				"max_hp": 1000,
				"passives": [HexBattleThorn.ABILITY],
			},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "max_hp": 1000},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 1000, "max_hp": 1000},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleChainLightning.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


func get_max_ticks() -> int:
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	ctx.assert_true(ctx.actor_final_hp(ctx.caster_id) <= 0.0,
		"caster 应被 enemy_0 Thorn post reaction 反死")

	var caster_damage_targets: Array[String] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "damage" and str(e.get("source_actor_id", "")) == ctx.caster_id:
			caster_damage_targets.append(str(e.get("target_actor_id", "")))

	ctx.assert_eq(caster_damage_targets.size(), 1,
		"caster 死亡后不应继续结算第二/第三跳 damage")
	if caster_damage_targets.size() == 1:
		ctx.assert_eq(caster_damage_targets[0], ctx.enemy_id(0),
			"唯一一次 caster damage 应为首跳 enemy_0")

	ctx.assert_eq(ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(1),
	}).size(), 0, "enemy_1 不应收到第二跳 damage")
	ctx.assert_eq(ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(2),
	}).size(), 0, "enemy_2 不应收到第三跳 damage")
