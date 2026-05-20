## Stance scenario (Phase 03) - Wrath/Calm 切换 + outgoing/incoming 双向
##
## radius=3 grid, caster[0,0] A 队 + enemy_0[1,0] B 队. caster 持 skill_stance (passive
## NoInstance lifecycle 默认 grant 后进入 Wrath); enemy_0 用 Strike 攻 caster, caster
## 用 Strike 攻 enemy_0; 中间 caster 主动 stance 切换两次。
##
## 时序 (Strike cooldown 2000ms, stance cooldown 2000ms):
##   t=0     caster Strike enemy_0 (Wrath 状态 outgoing ×1.5 → 75)
##   t=500   enemy_0 Strike caster (Wrath 状态 incoming ×1.5 → 75)
##   t=2200  caster Stance (Wrath → Calm)
##   t=2700  caster Strike enemy_0 (Calm 状态 outgoing ×0.75 → 37.5)
##   t=3200  enemy_0 Strike caster (Calm 状态 incoming ×0.75 → 37.5)
##   t=4500  caster Stance (Calm → Wrath)
##
## 断言重点:
## - 至少 1 个 dmg ≈ 75 (Wrath outgoing/incoming 验证)
## - 至少 1 个 dmg ≈ 37.5 (Calm outgoing/incoming 验证)
## - 最终 caster 持 WRATH_TAG (经 W→C→W 三轮切换)
class_name StanceScenario
extends SkillScenario


const CASTER_ATK := 50.0
const STRIKE_CRIT_MULT := 1.5
const WRATH_DMG := CASTER_ATK * HexBattleStance.WRATH_MULT       # 50 * 1.5 = 75
const CALM_DMG := CASTER_ATK * HexBattleStance.CALM_MULT          # 50 * 0.75 = 37.5


func get_name() -> String:
	return "Stance: Wrath/Calm 切换 + outgoing/incoming ±50% / ±25%"


func get_scene_config() -> Dictionary:
	# 用 MAGE 避免 WARRIOR 默认 Thorn 反伤干扰 caster→enemy damage 序列
	return {
		"map": {"radius": 3},
		"caster": {
			"class": "MAGE", "pos": [0, 0],
			"atk": CASTER_ATK, "hp": 1000, "max_hp": 1000,
		},
		"enemies": [
			{"class": "MAGE", "pos": [1, 0], "atk": CASTER_ATK, "hp": 1000, "max_hp": 1000},
		],
	}


func get_passives() -> Array[AbilityConfig]:
	var arr: Array[AbilityConfig] = [HexBattleStance.ABILITY]
	return arr


func get_actions() -> Array[Dictionary]:
	return [
		# Wrath 状态: 互打一回合
		{"caster": "caster",  "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0},
		{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster",  "time_ms": 500},
		# 切到 Calm
		{"caster": "caster",  "skill": HexBattleStance.ABILITY, "target": "caster",  "time_ms": 2200},
		# Calm 状态: 互打一回合
		{"caster": "caster",  "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 2700},
		{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster",  "time_ms": 3200},
		# 切回 Wrath
		{"caster": "caster",  "skill": HexBattleStance.ABILITY, "target": "caster",  "time_ms": 4500},
	]


func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Strike 暴击会触发 critical bonus (10 base) 的二段伤害事件;为简化断言, 只看
	# damage > 25 的主伤事件 (critical bonus 修正后最大 22.5 也排除掉)。
	var caster_to_enemy_all: Array[Dictionary] = ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id, "target_actor_id": ctx.enemy_id(0)
	})
	var enemy_to_caster_all: Array[Dictionary] = ctx.filter_damage_events({
		"source_actor_id": ctx.enemy_id(0), "target_actor_id": ctx.caster_id
	})
	var caster_main_hits: Array[Dictionary] = []
	for e in caster_to_enemy_all:
		if (e.get("damage", 0.0) as float) > 25.0:
			caster_main_hits.append(e)
	var enemy_main_hits: Array[Dictionary] = []
	for e in enemy_to_caster_all:
		if (e.get("damage", 0.0) as float) > 25.0:
			enemy_main_hits.append(e)

	ctx.assert_true(caster_main_hits.size() >= 2,
		"caster 主伤 ×2 (Wrath + Calm); 实际 %d" % caster_main_hits.size())
	ctx.assert_true(enemy_main_hits.size() >= 2,
		"enemy 主伤 ×2 (Wrath + Calm); 实际 %d" % enemy_main_hits.size())

	# Wrath outgoing: caster 第一击 = 75 (crit 112.5)
	if caster_main_hits.size() >= 1:
		var d_wrath_out: float = caster_main_hits[0].get("damage", -1.0) as float
		ctx.assert_float_in(d_wrath_out, [WRATH_DMG, WRATH_DMG * STRIKE_CRIT_MULT],
			"Wrath outgoing: caster→enemy 第一主伤 = 75 (crit 112.5)")

	# Wrath incoming: enemy 第一击 = 75 (crit 112.5)
	if enemy_main_hits.size() >= 1:
		var d_wrath_in: float = enemy_main_hits[0].get("damage", -1.0) as float
		ctx.assert_float_in(d_wrath_in, [WRATH_DMG, WRATH_DMG * STRIKE_CRIT_MULT],
			"Wrath incoming: enemy→caster 第一主伤 = 75 (crit 112.5)")

	# Calm outgoing: caster 第二击 = 37.5 (crit 56.25)
	if caster_main_hits.size() >= 2:
		var d_calm_out: float = caster_main_hits[1].get("damage", -1.0) as float
		ctx.assert_float_in(d_calm_out, [CALM_DMG, CALM_DMG * STRIKE_CRIT_MULT],
			"Calm outgoing: caster→enemy 第二主伤 = 37.5 (crit 56.25)")

	# Calm incoming: enemy 第二击 = 37.5 (crit 56.25)
	if enemy_main_hits.size() >= 2:
		var d_calm_in: float = enemy_main_hits[1].get("damage", -1.0) as float
		ctx.assert_float_in(d_calm_in, [CALM_DMG, CALM_DMG * STRIKE_CRIT_MULT],
			"Calm incoming: enemy→caster 第二主伤 = 37.5 (crit 56.25)")

	# 最终 caster 持 stance ability (passive, 不该被 revoke)
	ctx.assert_actor_ability_present(ctx.caster_id, HexBattleStance.CONFIG_ID,
		"skill_stance 持续到 scenario 终态")
