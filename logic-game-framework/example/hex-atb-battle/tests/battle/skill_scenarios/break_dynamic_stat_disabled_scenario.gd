## Phase B2 · Break · DynamicStatModifier (Vigor) disabled
##
## Vigor passive: max_hp += atk * 0.1 (DynamicStatModifierComponent)。
## Break 期间 max_hp 应回到无 Vigor 的 base 值; Break 结束后恢复增益。
##
## 验证 DynamicStatModifierComponent.on_passive_disabled (取消 register_dynamic_dep +
## remove_modifier) / on_passive_enabled (重新 register_dynamic_dep + add_modifier)。
##
## 时序:
##   t=0     enemy_0 cast Break caster → HIT @ t=300 → BreakBuff grant
##                                       → caster Vigor disabled
##                                       → max_hp 增益撤销
##   t=2300  BreakBuff expire → Vigor 重新激活 → max_hp 恢复增益
class_name BreakDynamicStatDisabledScenario
extends SkillScenario


const CASTER_ATK := 100.0
const CASTER_BASE_HP := 200.0
const VIGOR_RATIO := 0.1


func get_name() -> String:
	return "Break disables DynamicStatModifier (Vigor max_hp bonus)"


func get_scene_config() -> Dictionary:
	# caster atk=100, base max_hp 200 → Vigor 加成 100 * 0.1 = 10 → final max_hp 210
	# Break 期间 max_hp 应回到 200; Break 结束后回到 210
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": CASTER_BASE_HP, "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVigor.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(2000.0),
			"target": "caster",
			"time_ms": 0,
		},
		# 拖时间到 t≥2300 (Break expire 后); break 本身不创建 in-flight execution,
		# 不加 sentinel pending action 的话 harness 在 Break cast 结束 (~500ms) 后立刻 countdown 退出。
		{
			"caster": "enemy_0",
			"skill": HexBattleStrike.ABILITY,
			"target": "caster",
			"time_ms": 3000,
		},
	]


func get_max_ticks() -> int:
	return 60


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

	# 2. Vigor passive 仍在 caster ability list (不 revoke, 只 disabled)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleVigor.CONFIG_ID,
		"Vigor passive remains on caster after break expire"
	)

	# 3. 战斗结束 Break 已 expire → Vigor 恢复, max_hp = base + atk * 0.1
	#    期末 max_hp 应为 200 + 100*0.1 = 210
	var final_max_hp := ctx.final_actor_attribute(ctx.caster_id, "max_hp")
	var expected_after := CASTER_BASE_HP + CASTER_ATK * VIGOR_RATIO
	ctx.assert_float_eq(final_max_hp, expected_after,
		"After Break expire, Vigor restored: max_hp = base %.1f + atk %.1f * %.2f = %.1f (got %.1f)" % [
			CASTER_BASE_HP, CASTER_ATK, VIGOR_RATIO, expected_after, final_max_hp
		], 0.5)

	# 4. 战斗结束 caster 无 BreakBuff
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleBreakBuff.CONFIG_ID,
		"BreakBuff revoked after duration"
	)
