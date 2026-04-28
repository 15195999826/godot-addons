## Shield 完全吸收时 Thorn 不触发反伤
##
## 验证 on-damage-taken 反应（如 Thorn）的 filter 规则：
##   actual_life_damage > 0 才触发；若伤害被护盾完全吸收，反伤静默。
##
## 设定：enemy.atk = 20（< ward 30），enemy 用 Strike 攻击。
##
## ⚠ Strike 在暴击路径下会 fire 两段独立 DamageAction（见 skills/strike.gd）：
##   1. 主伤（atk 或 atk×1.5）
##   2. on_critical 回调：固定 +10 物理（CRITICAL_BONUS）
## 因此本 scenario 必须按主伤是否暴击分两条断言路径：
##
##   no-crit 路径（主伤 20）：
##     主伤 20 < ward 30 → 全吸 + ward 未破
##     无第二段（无 crit bonus）
##     actual_life_damage = 0 → Thorn 静默 → reflected 0 次
##
##   crit 路径（主伤 30 + crit bonus 10）：
##     主伤 30 = ward 30 → 全吸 + ward 破（这是本 scenario 真正要验证的"全吸不反弹"）
##     crit bonus 10 → 此时 ward 已空 → 直接打肉 10 → 触发 Thorn 反弹 1 次
##     这条路径 reflected.size() == 1 是 framework 设计行为, 不是 bug
##
## 核心契约（两条路径都成立）：第一段 damage event 被全吸时, Thorn filter 必须
## 在该 event 上静默（即 dmgs[0] 这一发不引发反弹）, 这才是本 scenario 的断言目标。
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

	# 主伤事件: 20 (no crit) 或 30 (crit), 都 ≤ ward 30 → 全部吸收
	# 这是本 scenario 的核心契约 —— "全吸的伤害不应触发 Thorn"
	var first: Dictionary = dmgs[0]
	var damage_value: float = first.get("damage", 0.0) as float
	var absorbed: float = first.get("shield_absorbed", -1.0) as float
	var actual_life: float = first.get("actual_life_damage", -1.0) as float
	var is_crit: bool = first.get("is_critical", false) as bool

	ctx.assert_float_eq(absorbed, damage_value,
		"primary damage fully absorbed (damage=%.0f)" % damage_value)
	ctx.assert_float_eq(actual_life, 0.0, "primary actual_life_damage = 0 on full absorption")

	# Thorn 反弹断言分路径:
	#   no-crit: 只有主伤(全吸) → 0 reflect
	#   crit:    主伤(全吸,ward 破) + crit bonus 10 击穿空 ward 打肉 → 1 reflect (= 2 pure)
	# 都不违反"全吸的事件不触发反弹"契约 —— crit 路径的反弹来自 *第二段* 已穿肉的事件。
	var enemy := ctx.enemy_id(0)
	var reflected := ctx.filter_damage_events({
		"target_actor_id": enemy,
		"damage_type": "pure",
	})
	var expected_reflects := 1 if is_crit else 0
	ctx.assert_eq(reflected.size(), expected_reflects,
		"thorn reflects on crit-bonus leak only (is_crit=%s, expected %d, got %d)" % [
			is_crit, expected_reflects, reflected.size()
		])
