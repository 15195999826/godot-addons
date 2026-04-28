## Shield 基础吸收 + 反伤过滤场景
##
## 验证：
##   1. 伤害先被护盾吸收，actual_life_damage = damage - shield_absorbed
##   2. damage event 携带 shield_absorbed / actual_life_damage / consumption_records
##   3. consumption_records 标记被打破的护盾 broken=true
##   4. 推送 shield_broken 事件
##   5. Thorn 在 actual_life_damage > 0 时仍正常反弹（部分吸收不破坏现有反伤语义）
##
## 设定：caster 装备 [Thorn + WardBuff]，enemy 用 Strike 攻击 caster。
## enemy.atk = 100，无暴击 100 / 暴击 150；ward capacity 30，必然破裂。
class_name ShieldBasicAbsorbScenario
extends SkillScenario


func get_name() -> String:
	return "Shield absorbs first, life damage = damage - absorbed, thorn still reflects"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": 100, "hp": 500}],
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
		ctx.fail("no damage event captured (Strike never fired)")
		return

	var first: Dictionary = dmgs[0]
	var damage_value: float = first.get("damage", 0.0) as float
	var absorbed: float = first.get("shield_absorbed", -1.0) as float
	var actual_life: float = first.get("actual_life_damage", -1.0) as float

	# damage 100 (no crit) 或 150 (crit)，ward 容量 30 必然全部吸完
	ctx.assert_float_eq(absorbed, HexBattleWardBuff.SHIELD_CAPACITY,
		"shield_absorbed = ward capacity (full broken)")
	ctx.assert_float_eq(actual_life, damage_value - HexBattleWardBuff.SHIELD_CAPACITY,
		"actual_life_damage = damage - absorbed")

	# 主伤害 + crit bonus 都应携带正确字段；至少有一个 broken record
	var records: Array = first.get("consumption_records", [])
	ctx.assert_true(records.size() >= 1, "at least 1 consumption record")
	if records.size() >= 1:
		var r: Dictionary = records[0]
		ctx.assert_eq(r.get("shield_config_id", ""), HexBattleWardBuff.CONFIG_ID,
			"record shield_config_id = buff_ward")
		ctx.assert_eq(r.get("broken", false), true, "ward broken in record")

	# shield_broken 事件至少 1 条（V1 没有 on_break 回调，仅事件入流）
	var broken_events := ctx.events_of_kind("shield_broken")
	ctx.assert_true(broken_events.size() >= 1, "shield_broken event pushed at least once")

	# Thorn 在 actual_life_damage > 0 时正常反弹
	var enemy := ctx.enemy_id(0)
	var reflected := ctx.filter_damage_events({
		"target_actor_id": enemy,
		"damage_type": "pure",
	})
	ctx.assert_true(reflected.size() >= 1,
		"thorn reflects when actual_life_damage > 0 (got %d)" % reflected.size())
