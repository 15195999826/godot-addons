## Phase A · AttackLandedEvent 边界契约：actual_life_damage = 0 仍 emit
##
## V1 契约 (per advanced-skills-next-batch.md Phase A):
##   actual_life_damage = 0 时仍允许事件存在；consumer 自己 no-op
##
## 设定：enemy.atk = 20 (< ward cap 30) → 主伤被 ward 全吸 → actual_life_damage = 0。
## AttackLandedEvent 仍应当 emit。
## (crit 路径下 主伤 30 == ward cap 30 也是全吸; crit bonus 10 不带 attack_landed
##  callback, 所以总是 1 条事件)
class_name AttackLandedZeroActualDamageScenario
extends SkillScenario


func get_name() -> String:
	return "AttackLanded: actual_life_damage = 0 still emits event"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": 20, "hp": 500}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleWardBuff.WARD_BUFF]


func get_actions() -> Array[Dictionary]:
	return [{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var attack_events := ctx.events_of_kind("attack_landed")
	ctx.assert_eq(attack_events.size(), 1,
		"Expect 1 AttackLandedEvent even when shield fully absorbs main damage (got %d)" % attack_events.size())
	if attack_events.is_empty():
		return
	var e: Dictionary = attack_events[0]
	var actual := e.get("actual_life_damage", -1.0) as float
	ctx.assert_float_eq(actual, 0.0,
		"actual_life_damage = 0 (shield absorbed full main damage)")
	ctx.assert_eq(e.get("attacker_actor_id", ""), ctx.enemy_id(0),
		"attacker = enemy_0 (who cast Strike)")
	ctx.assert_eq(e.get("target_actor_id", ""), ctx.caster_id,
		"target = caster (Strike landed on caster, ward absorbed)")
