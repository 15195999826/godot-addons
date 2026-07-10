## Chain Lightning 标准三跳基线(行为快照)。
##
## 收敛计划 W4 步骤 1: 在 execution_state 重写**之前**先锁定现状行为——
## 伤害序列 60 / 48 / 38.4、跳跃目标顺序、不重复命中、MAX_HITS 停链。
## 重写后本 scenario 必须原样全绿(用户硬性要求: 游戏内现有行为不得改变)。
##
## 站位: caster(0,0), 敌人一字排开 (1,0)/(2,0)/(3,0) → 首跳 enemy_0,
## 最近未命中依次 enemy_1 / enemy_2, 跳满 MAX_HITS=3 停链。
class_name ChainLightningBaselineScenario
extends SkillScenario


const EXPECTED_DAMAGES: Array[float] = [60.0, 48.0, 38.4]


func get_name() -> String:
	return "ChainLightning 基线: 三跳 60/48/38.4 顺序命中不重复, MAX_HITS 停链"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 6},
		"caster": {"class": "MAGE", "pos": [0, 0], "atk": 50, "hp": 100, "max_hp": 100},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "max_hp": 1000},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "max_hp": 1000},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 1000, "max_hp": 1000},
			{"class": "WARRIOR", "pos": [4, 0], "hp": 1000, "max_hp": 1000},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleChainLightning.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


func get_max_ticks() -> int:
	return 100


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 按事件流顺序收集 caster 造成的 damage(目标, 数值)
	var hit_targets: Array[String] = []
	var hit_damages: Array[float] = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "damage":
			continue
		if str(e.get("source_actor_id", "")) != ctx.caster_id:
			continue
		hit_targets.append(str(e.get("target_actor_id", "")))
		hit_damages.append(float(e.get("damage", 0.0)))

	# MAX_HITS=3 停链: 恰好 3 段, enemy_3(第 4 个敌人)绝不被波及
	ctx.assert_eq(hit_targets.size(), 3, "链应恰好命中 3 段(MAX_HITS 停链)")
	ctx.assert_eq(ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(3),
	}).size(), 0, "第 4 个敌人不应被第 4 跳波及")

	# 跳跃顺序: 首跳 enemy_0 → 最近未命中 enemy_1 → enemy_2(不重复命中)
	var expected_order: Array[String] = [ctx.enemy_id(0), ctx.enemy_id(1), ctx.enemy_id(2)]
	for i in range(mini(hit_targets.size(), expected_order.size())):
		ctx.assert_eq(hit_targets[i], expected_order[i], "第 %d 跳目标" % (i + 1))

	# 伤害序列 60 / 48 / 38.4(每跳 ×0.8 衰减)
	for i in range(mini(hit_damages.size(), EXPECTED_DAMAGES.size())):
		ctx.assert_float_eq(hit_damages[i], EXPECTED_DAMAGES[i], "第 %d 跳伤害" % (i + 1))

	# 终态 HP 复核(伤害确实入账)
	ctx.assert_float_eq(ctx.actor_final_hp(ctx.enemy_id(0)), 1000.0 - 60.0, "enemy_0 终态 HP")
	ctx.assert_float_eq(ctx.actor_final_hp(ctx.enemy_id(1)), 1000.0 - 48.0, "enemy_1 终态 HP")
	ctx.assert_float_eq(ctx.actor_final_hp(ctx.enemy_id(2)), 1000.0 - 38.4, "enemy_2 终态 HP")
	ctx.assert_float_eq(ctx.actor_final_hp(ctx.enemy_id(3)), 1000.0, "enemy_3 不掉血")
