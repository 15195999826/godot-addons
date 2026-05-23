## Phase B2 · Break · DemonForm (stacks-scaled StatModifier + periodic timeline) disabled
##
## DemonForm passive: 每 3s +1 stack, atk += stacks * 2 (StatModifierComponent
## scales_by_stacks + ActivateInstanceConfig periodic timeline)。
##
## Break 期间:
## - stacks 不增长 (Ability.tick_executions() 顶层短路, periodic timeline 冻结)
## - atk bonus 撤销 (StatModifierComponent.on_passive_disabled remove modifiers)
##
## Break 结束后:
## - atk bonus 按当前 stacks 重建 (on_passive_enabled)
## - periodic timeline 从冻结位置继续 (不 catch-up missed tick)
##
## 时序:
##   t=0     caster grant DemonForm (passive); enemy_0 cast Break caster → HIT @ t=300
##                                       → BreakBuff grant on caster, DemonForm disabled
##                                       → atk +0 撤销 (此时 stacks=0)
##           DemonForm tick @ t=3000, t=6000, t=9000... 但 break 期内不增长
##   t=2300  BreakBuff expire → DemonForm 恢复
##           DemonForm tick @ t=5300 (从冻结位置继续, 不补 break 期间 t=3000 missed tick)
##           → stacks 1 → atk +2
class_name BreakDemonFormDisabledScenario
extends SkillScenario


const CASTER_ATK_BASE := 30.0
const DEMON_ATK_PER_STACK := 2.0


func get_name() -> String:
	return "Break disables DemonForm (stacks frozen + atk bonus suspended)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": CASTER_ATK_BASE},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleDemonForm.ABILITY]


func get_actions() -> Array[Dictionary]:
	# Break duration 2000ms, demon form tick interval 3000ms
	# t=0 Break apply (HIT @ 300) → break window 300~2300
	# DemonForm GRANTED_SELF 立刻启动 periodic timeline, first tick @ t=3000
	# Break 期间 timeline 冻结; t=2300 unfreeze, 继续推进
	# 战斗结束前的最后 tick 数取决于 max_ticks
	return [
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(2000.0),
			"target": "caster",
			"time_ms": 0,
		},
		# Sentinel action: 拖 harness 到 ~6000ms, 让 DemonForm 在 break 解除后能再 tick 一次
		# (DemonForm tick @ 3000ms 因 break 冻结到 2300ms, resume 后约 5300ms 累一次)。
		# 同时确保 BreakBuff 有时间 expire (duration 2000ms)。
		# DemonForm 是 passive periodic timeline 永不停, scenario 借 demon form passive 自身
		# 让 still_executing 保持 true; harness max_ticks 触发 timeout, 但 smoke runner
		# 已实现 only_timeout 允许策略 (per smoke_skill_scenarios.gd line 96-105)。
	]


## 80 ticks = 8000ms; DemonForm passive periodic timeline 永不停, harness 会 max_ticks
## timeout — 这是允许的, runner 仅在 only_timeout 时允许 assert_replay 继续 (per harness 注释)。
func get_max_ticks() -> int:
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. Break grant 出现
	var break_grants: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != HexBattleBreakBuff.CONFIG_ID:
			continue
		break_grants.append(e)
	ctx.assert_eq(break_grants.size(), 1, "Expect 1 Break grant on caster")

	# 2. DemonForm passive 仍在 caster ability list
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleDemonForm.CONFIG_ID,
		"DemonForm passive remains on caster after break expire"
	)

	# 3. 收集 caster 的 abilityStacksChanged 事件 (DemonForm tick 触发)
	# Break 期内 (frame 4 ~ 24, 即 t=300~2300) 不应产生 stacks_changed; 之后才有。
	var break_grant_frame := int(break_grants[0].get("replay_frame", -1))
	var stacks_changes_during_break: Array = []
	var stacks_changes_after_break: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_STACKS_CHANGED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		if str(e.get("abilityConfigId", "")) != HexBattleDemonForm.CONFIG_ID:
			continue
		var frame := int(e.get("replay_frame", -1))
		# Break window = [grant_frame, grant_frame + 20] = [4, 24]
		if frame >= break_grant_frame and frame < break_grant_frame + 20:
			stacks_changes_during_break.append(e)
		else:
			stacks_changes_after_break.append(e)

	ctx.assert_eq(stacks_changes_during_break.size(), 0,
		"DemonForm should NOT tick (gain stacks) during break window (got %d)" % stacks_changes_during_break.size())
	ctx.assert_true(stacks_changes_after_break.size() >= 1,
		"DemonForm should resume ticking after break expire (got %d post-break stacks changes)" % stacks_changes_after_break.size())

	# 4. 期末 stacks ≥ 1 (DemonForm 在 break 解除后继续 periodic tick)
	if stacks_changes_after_break.size() >= 1:
		var last: Dictionary = stacks_changes_after_break[-1]
		var stacks_final := int(last.get("newStacks", 0))
		ctx.assert_true(stacks_final >= 1,
			"DemonForm stacks ≥ 1 after break expire (got %d)" % stacks_final)

	# 5. 期末 BreakBuff 已 revoke
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleBreakBuff.CONFIG_ID,
		"BreakBuff revoked after duration"
	)
