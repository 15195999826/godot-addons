## Execute 场景:斩杀阈值分支 + 护盾参与有效血量判定 + 击杀特效
##
## 4 case(WARRIOR 默认 atk=50;harness 现支持 hp≠max_hp):
##   1 低血秒杀  enemy_0 hp=15  max=100 (15%<20%)        → 斩杀,dmg=effective+1=16(暴击24),死,execute_kill cue
##   2 高血普攻  enemy_1 hp=80  max=100 (80%)            → 普攻 caster.atk=50(暴击75),不死,无 execute_kill cue
##   3 临界外侧  enemy_2 hp=20  max=100 (20% 严格 < 不触发) → 普攻 50(非 21)→ 证明 strict <;普攻击杀(语义内,允许 cue)
##   4 带 ward 抗斩杀  enemy_3 hp=15 max=100 + 自挂 ward(吸 PURE,cap30)
##                      → effective=(15+30)/100=45% → 普攻 50(非 16)→ 证明护盾计入有效血量(你点出的 bug 修复核心)
##
## 三次 Execute 间隔 ≥ 6500ms > COOLDOWN_MS(6000)互不干扰;enemy_3 在被斩前自挂 ward。
class_name ExecuteScenario
extends SkillScenario


const CASTER_ATK := 50.0
const STRIKE_CRIT_MULT := 1.5
const KILL_CUE := "execute_kill"


func get_name() -> String:
	return "Execute: <20% 有效血量 → 斩杀(护盾计入);否则 caster.atk;击杀放 execute_kill 特效"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 6},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": CASTER_ATK, "hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 15, "max_hp": 100},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 80, "max_hp": 100},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 20, "max_hp": 100},
			{"class": "WARRIOR", "pos": [4, 0], "hp": 15, "max_hp": 100},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleExecute.ABILITY, "target": "enemy_0", "time_ms": 0},
		{"caster": "caster", "skill": HexBattleExecute.ABILITY, "target": "enemy_1", "time_ms": 6500},
		{"caster": "caster", "skill": HexBattleExecute.ABILITY, "target": "enemy_2", "time_ms": 13000},
		# enemy_3 在被斩前给自己挂 universal ward(吸 PURE),验证有效血量算护盾
		{"caster": "enemy_3", "skill": HexBattleWard.ABILITY, "target": "enemy_3", "time_ms": 16000},
		{"caster": "caster", "skill": HexBattleExecute.ABILITY, "target": "enemy_3", "time_ms": 19500},
	]


## 末个 action 19500ms + 500ms timeline + buffer ≈ 20500ms / 100ms tick ≈ 205,取 250。
func get_max_ticks() -> int:
	return 250


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# ---- Case 1:低血秒杀 ----
	var d0 := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	if d0.is_empty():
		ctx.fail("Case1: enemy_0 未收到 damage event")
	else:
		var dmg0: float = d0[0].get("damage", -1.0) as float
		ctx.assert_float_in(dmg0, [16.0, 16.0 * STRIKE_CRIT_MULT],
			"Case1: enemy_0(15%) 斩杀伤害 = effective+1=16(暴击24)")
		ctx.assert_eq(str(d0[0].get("damage_type", "")), "pure",
			"Case1: 斩杀 damage_type = pure")
	ctx.assert_true(_kill_cue_targets(ctx, ctx.enemy_id(0)),
		"Case1: enemy_0 被斩杀 → execute_kill 特效 cue 命中它")

	# ---- Case 2:高血普攻,不死,无斩杀特效 ----
	var d1 := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(1)})
	if d1.is_empty():
		ctx.fail("Case2: enemy_1 未收到 damage event")
	else:
		var dmg1: float = d1[0].get("damage", -1.0) as float
		ctx.assert_float_in(dmg1, [CASTER_ATK, CASTER_ATK * STRIKE_CRIT_MULT],
			"Case2: enemy_1(80%) 普攻 = caster.atk=50(暴击75)")
	ctx.assert_true(ctx.actor_final_hp(ctx.enemy_id(1)) > 0.0,
		"Case2: enemy_1 普攻未致死(80hp > 75 暴击上限)")
	ctx.assert_true(not _kill_cue_targets(ctx, ctx.enemy_id(1)),
		"Case2: enemy_1 未被击杀 → 无 execute_kill 特效")

	# ---- Case 3:严格临界 20% 不触发斩杀(伤害 = 普攻 50,而非 effective+1=21) ----
	var d2 := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(2)})
	if d2.is_empty():
		ctx.fail("Case3: enemy_2 未收到 damage event")
	else:
		var dmg2: float = d2[0].get("damage", -1.0) as float
		ctx.assert_float_in(dmg2, [CASTER_ATK, CASTER_ATK * STRIKE_CRIT_MULT],
			"Case3: enemy_2(=20% 严格 <) 未斩杀,伤害 = caster.atk 50 而非 21")

	# ---- Case 4:ward 计入有效血量 → 不走斩杀分支(核心 bug 修复) ----
	var d3 := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(3)})
	if d3.is_empty():
		ctx.fail("Case4: enemy_3 未收到 damage event")
	else:
		var dmg3: float = d3[0].get("damage", -1.0) as float
		ctx.assert_float_in(dmg3, [CASTER_ATK, CASTER_ATK * STRIKE_CRIT_MULT],
			"Case4: enemy_3(15hp+ward30→有效45%) 走普攻 50,非斩杀 16 —— 证明护盾计入有效血量判定")
		ctx.assert_true((d3[0].get("shield_absorbed", 0.0) as float) > 0.0,
			"Case4: ward 实际参与吸收(确认 ward 在场且被算入)")


## events 里是否存在 cueId=execute_kill 且 target 包含 actor_id 的 stageCue
func _kill_cue_targets(ctx: ScenarioAssertContext, actor_id: String) -> bool:
	if actor_id == "":
		return false
	for e in ctx.events_of_kind(GameEvent.STAGE_CUE_EVENT):
		if str(e.get("cueId", "")) != KILL_CUE:
			continue
		var targets: Array = e.get("targetActorIds", [])
		if actor_id in targets:
			return true
	return false
