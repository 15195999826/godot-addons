## DeathrattleAoe 亡语场景：caster 被一击杀死，DeathrattleAoe 对所有敌方造成 20 PURE
##
## 关键 pattern 验证：
##   - 被动挂载到 caster(死亡方)
##   - PostEvent on death kind 触发
##   - 死者在 handler 中仍能用自己作 source push 伤害事件
##   - 多敌人场景:20 PURE 命中每个敌人
class_name DeathrattleAoeScenario
extends SkillScenario


const AOE_DAMAGE := 20.0


func get_name() -> String:
	return "DeathrattleAoe hits all enemies for 20 pure on caster death"


func get_scene_config() -> Dictionary:
	# caster hp=50,enemy_0 atk=100 一击毙命(不 crit 时);避免 crit 时 ally 也一起被 aoe 死,做成纯的
	return {
		"map": {"rows": 5, "cols": 5},
		"caster":  {"class": "BERSERKER", "pos": [0, 0], "hp": 50},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "atk": 100, "hp": 500},
			{"class": "WARRIOR", "pos": [2, 1], "atk": 50, "hp": 500},
		],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleDeathrattleAoe.ABILITY]


func get_actions() -> Array[Dictionary]:
	# enemy_0 一击 Strike caster → caster 死 → Deathrattle AoE 所有敌方
	return [{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# caster 应该死了
	ctx.assert_float_eq(ctx.actor_final_hp(ctx.caster_id), 0.0, "caster dead after kill blow")

	# 每个 enemy 都应有 1 次 PURE 伤害(基础 20,crit 时 30)
	for i in range(2):
		var enemy_id := ctx.enemy_id(i)
		var aoe_hits := ctx.filter_damage_events({
			"target_actor_id": enemy_id,
			"damage_type": "pure",
		})
		ctx.assert_eq(aoe_hits.size(), 1, "enemy_%d received 1 deathrattle AoE hit" % i)
		if aoe_hits.size() >= 1:
			var dmg: float = aoe_hits[0].get("damage", 0.0)
			ctx.assert_float_in(dmg, [AOE_DAMAGE, AOE_DAMAGE * 1.5],
				"enemy_%d AoE damage = 20 or 30 (crit)" % i)
