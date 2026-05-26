## Shield 完全吸收时 Thorn 不触发反伤
##
## 验证 on-damage-taken 反应（如 Thorn）的 filter 规则：
##   actual_life_damage > 0 才触发；若伤害被护盾完全吸收，反伤静默。
##
## 设定：enemy.atk = 20（< ward 30），enemy 用 Strike 攻击。
##
## Phase G 起 Strike 不再自带随机暴击或 crit bonus damage；本 scenario 只验证
## 单次主伤 20 被 ward 全吸后 Thorn 不触发。
class_name ShieldFullAbsorbNoThornsScenario
extends SkillScenario


func get_name() -> String:
	return "Full shield absorption does NOT trigger thorn"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": 20, "hp": 500}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleThorn.ABILITY, HexBattleWardBuff.WARD_BUFF]


func get_actions() -> Array[Dictionary]:
	return [{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var dmgs := ctx.filter_damage_events({"target_actor_id": ctx.caster_id})
	if dmgs.is_empty():
		ctx.fail("no damage event captured")
		return

	# 主伤事件: 20 ≤ ward 30 → 全部吸收
	# 这是本 scenario 的核心契约 —— "全吸的伤害不应触发 Thorn"
	var first: Dictionary = dmgs[0]
	var damage_value: float = first.get("damage", 0.0) as float
	var absorbed: float = first.get("shield_absorbed", -1.0) as float
	var actual_life: float = first.get("actual_life_damage", -1.0) as float

	ctx.assert_float_eq(damage_value, 20.0, "primary damage = enemy atk")
	ctx.assert_float_eq(absorbed, damage_value,
		"primary damage fully absorbed (damage=%.0f)" % damage_value)
	ctx.assert_float_eq(actual_life, 0.0, "primary actual_life_damage = 0 on full absorption")

	var enemy := ctx.enemy_id(0)
	var reflected := ctx.filter_damage_events({
		"target_actor_id": enemy,
		"damage_type": "pure",
	})
	ctx.assert_eq(reflected.size(), 0,
		"thorn must not reflect when primary damage is fully absorbed")
