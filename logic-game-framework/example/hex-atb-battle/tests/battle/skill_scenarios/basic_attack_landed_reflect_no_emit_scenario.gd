## Phase A · BasicAttackLandedEvent 负面契约：反伤不重复 emit
##
## V1 契约:
##   reflected damage 不产生 BasicAttackLandedEvent
##
## 设定：caster 装 Thorn 被动, enemy_0 用 Strike 攻击 caster。
##   - enemy_0 Strike → 1 BasicAttackLandedEvent (来自 enemy_0)
##   - Thorn 反伤 → ReflectDamageAction 推 reflected damage event,
##     不通过 HexBattleDamageAction.on_hit chain → 无 BasicAttackLandedEvent
## 综合: 总共 1 条 BasicAttackLandedEvent (来自 enemy_0 的 Strike)
class_name BasicAttackLandedReflectNoEmitScenario
extends SkillScenario


func get_name() -> String:
	return "BasicAttackLanded: reflected damage does NOT emit BasicAttackLandedEvent"


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
	# Sanity: reflected damage 出现 (PURE 反伤)
	var enemy := ctx.enemy_id(0)
	var reflected := ctx.filter_damage_events({
		"target_actor_id": enemy,
		"damage_type": "pure",
	})
	ctx.assert_true(reflected.size() >= 1, "Thorn did fire reflect damage (sanity)")

	# 核心契约: 只有 enemy_0 Strike 的 1 条 BasicAttackLandedEvent,
	# Thorn 反伤的 damage event 不复触发 BasicAttackLandedEvent
	var attack_events := ctx.events_of_kind("basic_attack_landed")
	ctx.assert_eq(attack_events.size(), 1,
		"Expect exactly 1 BasicAttackLandedEvent — reflected damage must not produce additional one (got %d)" % attack_events.size())
	if attack_events.is_empty():
		return
	var e: Dictionary = attack_events[0]
	ctx.assert_eq(e.get("attacker_actor_id", ""), enemy,
		"attacker = enemy_0 (the one who cast Strike)")
	ctx.assert_eq(e.get("target_actor_id", ""), ctx.caster_id,
		"target = caster (Strike's target, not the reflect ricochet target)")
