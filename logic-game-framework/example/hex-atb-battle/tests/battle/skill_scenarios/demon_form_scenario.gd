## Demon Form scenario (Phase 04) - passive 每 3s +2 atk
##
## radius=3 grid, caster (WARRIOR atk=50, hp=1000) + 1 弱 enemy (防早终止)。
## caster passives = [HexBattleDemonForm.ABILITY]。
## max_ticks 110 * 100ms = 11000ms; 期望 tick 触发 3 次 (t=3000, 6000, 9000)。
##
## 断言:
## - caster 终态 atk = initial_atk + tick_count * 2
##   (通过 §0.X scenario attribute snapshot final_actor_attribute 直接读)
## - AbilityStacksChanged 事件数 == tick_count
## - stageCue(demon_form_pulse) 事件数 == tick_count
class_name DemonFormScenario
extends SkillScenario


const ATK_PER_STACK := HexBattleDemonForm.ATK_PER_STACK
const TICK_INTERVAL_MS := HexBattleDemonForm.TICK_INTERVAL_MS


func get_name() -> String:
	return "DemonForm: 每 3s +2 atk; 3 tick → atk +6 + AbilityStacksChanged ×3 + stageCue ×3"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			# 弱 enemy 不会主动攻击 (scenario harness 不跑 AI); 仅占位防 scenario 提前结束
			{"class": "WARRIOR", "pos": [2, 0], "hp": 100, "max_hp": 100},
		],
	}


func get_passives() -> Array[AbilityConfig]:
	var arr: Array[AbilityConfig] = [HexBattleDemonForm.ABILITY]
	return arr


func get_actions() -> Array[Dictionary]:
	# smoke runner 要求 actions non-empty; 给 caster 一个 t=0 Strike enemy 占位,
	# Demon Form 仍通过 GRANTED_SELF trigger 自启 tick loop。Strike 在 Wrath 等
	# 状态外, 单击就走 caster.atk = 50 默认值。enemy hp=100 单击 50 还活着, 不影响。
	return [
		{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


func get_max_ticks() -> int:
	# 11000ms / 100ms = 110 ticks; 含 grant 后第一次 tick 在 t=3000 (TICK_INTERVAL_MS).
	return 110


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 收集 AbilityStacksChanged (event kind 是 "abilityStacksChanged" camelCase)
	var stacks_changed: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "abilityStacksChanged" \
				and str(e.get("abilityConfigId", "")) == HexBattleDemonForm.CONFIG_ID:
			stacks_changed.append(e)

	# 收集 stageCue(demon_form_pulse)
	var pulses: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "stageCue" \
				and str(e.get("cueId", "")) == HexBattleDemonForm.CUE_DEMON_FORM_PULSE:
			pulses.append(e)

	# tick 数 — 期望 3 (t=3s/6s/9s in 11s window)
	var tick_count := stacks_changed.size()
	ctx.assert_true(tick_count >= 3,
		"DemonForm 应至少 tick 3 次 (实际 %d)" % tick_count)
	ctx.assert_eq(pulses.size(), tick_count,
		"stageCue 数应等于 tick 数")

	# atk = initial + tick_count * 2 (用 §0.X attribute snapshot)
	# WARRIOR 默认 atk = 50 (scenario 也设 atk=50, 没 vigor/vitality 干扰)
	var initial_atk := 50.0
	var expected_atk := initial_atk + tick_count * ATK_PER_STACK
	var final_atk := ctx.final_actor_attribute(ctx.caster_id, "atk")
	ctx.assert_float_eq(final_atk, expected_atk,
		"DemonForm: caster final atk = initial %.1f + stacks(%d) * 2 = %.1f" % [initial_atk, tick_count, expected_atk])

	# stacks_changed event 序列 — old/new 应递增 0→1, 1→2, 2→3, ...
	for i in range(stacks_changed.size()):
		var e := stacks_changed[i]
		ctx.assert_eq(int(e.get("oldStacks", -1)), i,
			"stacks_changed[%d] oldStacks = %d" % [i, i])
		ctx.assert_eq(int(e.get("newStacks", -1)), i + 1,
			"stacks_changed[%d] newStacks = %d" % [i, i + 1])
