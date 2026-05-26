## Phase B2 · Break · DynamicStatModifier (Vitality) disabled during break window
##
## Vitality passive: atk += max_hp * 0.01 (DynamicStatModifierComponent)。
## Break 期间 atk 应回到 base 值; Break 结束后恢复增益。
##
## 验证 DynamicStatModifierComponent.on_passive_disabled (取消 register_dynamic_dep +
## remove_modifier) / on_passive_enabled (重新 register_dynamic_dep + add_modifier)
## **同时验证 during-break 状态** — 通过 caster 在 break 期内 / 期后 各 Strike 一次,
## damage 数值差异化反映 atk 是否被 disable (Strike main damage = caster.atk)。
##
## 时序:
##   t=0     enemy_0 cast Break caster → HIT @ t=300 → BreakBuff grant
##                                       → caster Vitality disabled
##                                       → atk = base 20 (Vitality 加成被撤销)
##   t=600   caster Strike enemy_0       → damage = 20 (期内 atk_base)
##   t=2300  BreakBuff expire → Vitality 重新激活 → atk = 20 + 1000*0.01 = 30
##   t=3000  caster Strike enemy_0       → damage = 30 (期后 atk_boosted)
class_name BreakDynamicStatDisabledScenario
extends SkillScenario


const CASTER_ATK_BASE := 20.0
const CASTER_MAX_HP := 1000.0
const VITALITY_RATIO := 0.01


func get_name() -> String:
	return "Break disables DynamicStatModifier during break window (Vitality atk bonus)"


func get_scene_config() -> Dictionary:
	# caster max_hp=1000, atk=20 → Vitality 加成 atk += 1000 * 0.01 = 10 → 期外 atk = 30
	# 期内 atk = 20; 期后 atk = 30。Strike main damage 直接反映 atk。
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": CASTER_MAX_HP, "atk": CASTER_ATK_BASE},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 5000, "atk": 10}],
	}


func get_passives() -> Array[AbilityConfig]:
	return [HexBattleVitality.ABILITY]


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "enemy_0",
			"skill": HexBattleBreak.create_config(2000.0),
			"target": "caster",
			"time_ms": 0,
		},
		# 期内 (break window) Strike: damage = atk_base 20 (Vitality disabled)
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 600,
		},
		# 期后 Strike: damage = atk_boosted 30 (Vitality restored)
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
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
	if break_grants.size() != 1:
		return

	# 1b. 拿 break remove frame
	var break_inst_id := str((break_grants[0].get("ability", {}) as Dictionary).get("id", ""))
	var break_remove_frame := -1
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		if str(e.get("abilityInstanceId", "")) == break_inst_id:
			break_remove_frame = int(e.get("replay_frame", -1))
			break

	# 2. Vitality passive 仍在 caster ability list (不 revoke, 只 disabled)
	ctx.assert_actor_ability_present(
		ctx.caster_id, HexBattleVitality.CONFIG_ID,
		"Vitality passive remains on caster after break expire"
	)

	# 3. caster Strike 主伤害事件 (期内 + 期后)
	var all_strikes := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	var main_strikes: Array = []
	for e in all_strikes:
		if (e.get("damage", 0.0) as float) >= 18.0:
			main_strikes.append(e)
	ctx.assert_eq(main_strikes.size(), 2,
		"Expect 2 caster Strike main hits on enemy_0 (期内 + 期后), got %d" % main_strikes.size())
	if main_strikes.size() != 2:
		return

	# 4. KEY contract (during-break Vitality disabled):
	#    main_strikes[0] (期内) damage 主 ≈ 20 (atk_base, Vitality disabled)
	#    main_strikes[1] (期后) damage 主 ≈ 30 (atk_boosted, Vitality restored)
	#    Phase G 起 Strike 本身不 crit-scale main damage, 所以 main damage 严格等于 atk。
	var damage_in := main_strikes[0].get("damage", 0.0) as float
	var damage_out := main_strikes[1].get("damage", 0.0) as float

	# 期内 strike frame 必须 在 break_remove_frame 之前
	# 期后 strike frame 必须 在 break_remove_frame 之后
	var frame_in := int(main_strikes[0].get("replay_frame", -1))
	var frame_out := int(main_strikes[1].get("replay_frame", -1))
	ctx.assert_true(frame_in < break_remove_frame,
		"Strike #1 must fire BEFORE break remove (frame %d < %d)" % [frame_in, break_remove_frame])
	ctx.assert_true(frame_out > break_remove_frame,
		"Strike #2 must fire AFTER break remove (frame %d > %d)" % [frame_out, break_remove_frame])

	var atk_in := CASTER_ATK_BASE  # 20
	var atk_out := CASTER_ATK_BASE + CASTER_MAX_HP * VITALITY_RATIO  # 30
	ctx.assert_float_eq(damage_in, atk_in,
		"DURING break: Strike damage = atk_base %.1f (Vitality disabled)" % atk_in)
	ctx.assert_float_eq(damage_out, atk_out,
		"AFTER break: Strike damage = %.1f (Vitality restored)" % atk_out)
	# KEY contract: damage_out 必定 > damage_in (Vitality 在期外恢复加成, 主 atk 提升)
	ctx.assert_true(damage_out > damage_in,
		"After Break damage (%.1f) should be > during-Break damage (%.1f) — Vitality bonus restored" % [
			damage_out, damage_in
		])

	# 5. 战斗结束 caster atk 应为 boosted (Vitality 已 restored)
	var final_atk := ctx.final_actor_attribute(ctx.caster_id, "atk")
	ctx.assert_float_eq(final_atk, CASTER_ATK_BASE + CASTER_MAX_HP * VITALITY_RATIO,
		"After break, final caster atk = boosted",
		0.5)

	# 6. 战斗结束 BreakBuff revoked
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleBreakBuff.CONFIG_ID,
		"BreakBuff revoked after duration"
	)
