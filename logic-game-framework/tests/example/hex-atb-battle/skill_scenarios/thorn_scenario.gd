## Thorn 反伤被动场景：enemy 打 caster，caster 的 Thorn 被动反弹 2 PURE
##
## 关键 pattern 验证：
##   - enemy 作为 action 的 caster（action 接口支持反向施法）
##   - caster 受到物理伤害后触发 NoInstanceConfig trigger
##   - 反伤事件 is_reflected = true，避免无限循环(Thorn filter 过滤自己)
class_name ThornScenario
extends SkillScenario


const REFLECT_DAMAGE := 2.0


func get_name() -> String:
	return "Thorn reflects 2 pure back to attacker"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": 50, "hp": 500}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleThorn.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var enemy := ctx.enemy_id(0)

	# enemy 的 Strike 命中 caster（atk 50，可能 crit 75）
	var dmg_to_caster := ctx.filter_damage_events({"target_actor_id": ctx.caster_id})
	ctx.assert_true(dmg_to_caster.size() >= 1, "caster received at least 1 hit")

	# Thorn 反弹 PURE 2 给 enemy_0。
	# 注意:Strike crit 时产生 主伤害 + crit bonus 两个 damage event,Thorn 对每个都触发。
	# 所以 reflect 次数 = 主伤害次数 + (crit ? 1 : 0),断言范围 [1, 2] 且每次都是 2 PURE。
	var reflected := ctx.filter_damage_events({
		"target_actor_id": enemy,
		"damage_type": "pure",
	})
	ctx.assert_true(reflected.size() in [1, 2],
		"Thorn reflect count 1 (no-crit) or 2 (crit), got %d" % reflected.size())
	for r in reflected:
		ctx.assert_float_eq(r.get("damage", 0.0) as float, REFLECT_DAMAGE,
			"Thorn reflected damage = 2")
