## Expose 场景: caster 自施 Expose,enemy 在 buff 期内 + 过期后各 Strike 一次。
##
## 时序设计:
##   t=0      caster 施 Expose(timeline 500ms, HIT @300ms 给自己挂 ExposeBuff)
##   t=600    enemy_0 Strike #1 → HIT @ t=900, buff 已在 → damage *1.5
##   t=6000   enemy_0 Strike #2 → HIT @ t=6300, buff 已过期 (300+5000=5300) → 原始伤害
##
## 这样设计的原因:
##   - PreEventComponent 拦截"target == owner"的 pre_damage, 给 caster 自挂 buff 验证最直接
##   - harness 提前结束逻辑 still_executing 不看 buff(buff 无 timeline), 用 time_ms 调度
##     强制延后 enemy 的 Strike, 同时把战斗时长撑到 buff 过期之后
##   - 二段 (buff 期内 + 期外) 一次性覆盖"放大"+"自动过期 revoke"两条断言
class_name ExposeScenario
extends SkillScenario


const ENEMY_ATK := 50.0
const EXPOSE_MULT := 1.5  # 与 HexBattleExposeBuff.DAMAGE_AMP_MULT 同步, const 不能跨脚本引用
const STRIKE_CRIT_MULT := 1.5


func get_name() -> String:
	return "Expose +50% pre_damage modify (target = caster)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": ENEMY_ATK, "hp": 500}],
	}


## 三步走: caster 自施 Expose, enemy 在 buff 内 / 过期后各 Strike 一次
func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster",  "skill": HexBattleExpose.ABILITY, "target": "caster",  "time_ms": 0},
		{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster",  "time_ms": 600},
		{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster",  "time_ms": 6000},
	]


## 6000ms strike 过 + 500ms timeline + 1000ms post-execution buffer 共 ~7500ms
## max_ticks=100 (10000ms) 安全余量
func get_max_ticks() -> int:
	return 100


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Strike crit 时 _on_critical_callbacks 会 push 一个 CRITICAL_BONUS=10 的 damage event
	# (也走 pre_damage 也吃 Expose 放大), 让事件总数随机 ∈ [2,4]。
	# 用 damage > 30 过滤掉 crit bonus(10/15), 只看每次 Strike 的主伤害(50/75/112.5)。
	var all_dmg := ctx.filter_damage_events({"target_actor_id": ctx.caster_id})
	var main_hits: Array = []
	for e in all_dmg:
		if (e.get("damage", 0.0) as float) > 30.0:
			main_hits.append(e)
	ctx.assert_eq(main_hits.size(), 2, "exactly 2 main-hit damage events on caster (crit bonus filtered)")
	if main_hits.size() != 2:
		return

	# Strike #1 - buff 内: 50 * 1.5 = 75 (or crit: 112.5)
	var inside_dmg := main_hits[0].get("damage", 0.0) as float
	var inside_no_crit := ENEMY_ATK * EXPOSE_MULT
	var inside_crit := ENEMY_ATK * EXPOSE_MULT * STRIKE_CRIT_MULT
	ctx.assert_float_in(
		inside_dmg, [inside_no_crit, inside_crit],
		"Strike #1 damage amplified by Expose +50% (no-crit %.1f / crit %.1f)" % [inside_no_crit, inside_crit]
	)

	# Strike #2 - buff 已过期: 50 (or crit: 75)
	var outside_dmg := main_hits[1].get("damage", 0.0) as float
	var outside_no_crit := ENEMY_ATK
	var outside_crit := ENEMY_ATK * STRIKE_CRIT_MULT
	ctx.assert_float_in(
		outside_dmg, [outside_no_crit, outside_crit],
		"Strike #2 damage NOT amplified (buff expired) (no-crit %.1f / crit %.1f)" % [outside_no_crit, outside_crit]
	)

	# duration 到期后 ExposeBuff 自动 revoke
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleExposeBuff.CONFIG_ID,
		"ExposeBuff revoked after duration"
	)
