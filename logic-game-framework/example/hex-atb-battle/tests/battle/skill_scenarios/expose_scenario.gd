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
	var all_dmg := ctx.filter_damage_events({"target_actor_id": ctx.caster_id})
	var main_hits: Array = all_dmg
	ctx.assert_eq(main_hits.size(), 2, "exactly 2 main-hit damage events on caster")
	if main_hits.size() != 2:
		return

	# Strike #1 - buff 内: 50 * 1.5 = 75
	var inside_dmg := main_hits[0].get("damage", 0.0) as float
	var inside_expected := ENEMY_ATK * EXPOSE_MULT
	ctx.assert_float_eq(
		inside_dmg, inside_expected,
		"Strike #1 damage amplified by Expose +50%"
	)

	# Strike #2 - buff 已过期: 50
	var outside_dmg := main_hits[1].get("damage", 0.0) as float
	ctx.assert_float_eq(
		outside_dmg, ENEMY_ATK,
		"Strike #2 damage NOT amplified (buff expired)"
	)

	# duration 到期后 ExposeBuff 自动 revoke
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleExposeBuff.CONFIG_ID,
		"ExposeBuff revoked after duration"
	)
