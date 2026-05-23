## Phase A · Stun · Case 1: 短前长后
##
## 多个 Stun 实例并存 → 各自独立 lifetime, 互不干扰 cant_act gate。
##
## 时序:
##   t=0     enemy_0 cast Stun_short(dur=1000ms) → HIT @ t=300 → Stun A grant
##   t=500   enemy_1 cast Stun_long (dur=3000ms) → HIT @ t=800 → Stun B grant
##   t=1000  caster try Strike enemy_0 → FAIL (cant_act, A+B 都在)
##   t=1300  Stun A expire (300 + 1000)
##   t=3800  Stun B expire (800 + 3000)
##   t=4500  caster try Strike enemy_0 → SUCCESS (cant_act 已清)
##
## 断言:
##   - caster 上 2 次独立 stun_buff grant (instance id 不同)
##   - 2 次独立 stun_buff remove, 短 Stun 先 remove (frame 顺序)
##   - 战斗结束 caster 无 stun_buff
##   - t=1000 Strike 失败 (cant_act gate 生效, 有 AbilityActivateFailed event)
##   - t=4500 Strike 成功 (有 damage 事件 caster → enemy_0)
##
## 后段 Strike 既验证 cant_act 行为切换, 也拖住 harness 让 buff 跑到 expire
## (stun buff 不创建 in-flight execution, 需主动占据 still_executing)。
class_name StunIndependentInstancesScenario
extends SkillScenario


const STUN_DUR_SHORT_MS := 1000.0
const STUN_DUR_LONG_MS  := 3000.0


func get_name() -> String:
	return "Stun independent instances (short first, long second)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000, "atk": 50},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1500, "atk": 10},
			{"class": "WARRIOR", "pos": [0, 1], "hp": 1500, "atk": 10},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "enemy_0",
			"skill": HexBattleStun.create_config(STUN_DUR_SHORT_MS),
			"target": "caster",
			"time_ms": 0,
		},
		{
			"caster": "enemy_1",
			"skill": HexBattleStun.create_config(STUN_DUR_LONG_MS),
			"target": "caster",
			"time_ms": 500,
		},
		# 长 Stun 期内: cant_act gate 应阻止 Strike
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 1000,
		},
		# 所有 Stun 过期后: cant_act 清, Strike 成功
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 4500,
		},
	]


## 4500 + Strike timeline(500) + post_buffer(1000) = 6000ms; max_ticks 70 = 7000ms 安全余量。
func get_max_ticks() -> int:
	return 70


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. caster 上 stun_buff grant 事件 (按 ability.configId 过滤)
	var stun_grants := _filter_stun_grants(ctx, HexBattleStunBuff.CONFIG_ID)
	ctx.assert_eq(stun_grants.size(), 2,
		"Expect 2 independent HexBattleStunBuff grants on caster (Stun A + Stun B)")
	if stun_grants.size() != 2:
		return

	var inst_a := str((stun_grants[0].get("ability", {}) as Dictionary).get("id", ""))
	var inst_b := str((stun_grants[1].get("ability", {}) as Dictionary).get("id", ""))
	ctx.assert_true(not inst_a.is_empty() and not inst_b.is_empty(),
		"Both Stun grants carry non-empty ability ids")
	ctx.assert_true(inst_a != inst_b,
		"Stun A id (%s) != Stun B id (%s) — independent instances" % [inst_a, inst_b])

	var grant_a_frame := int(stun_grants[0].get("replay_frame", -1))
	var grant_b_frame := int(stun_grants[1].get("replay_frame", -1))
	ctx.assert_true(grant_a_frame < grant_b_frame,
		"Stun A granted (frame %d) before Stun B (frame %d)" % [grant_a_frame, grant_b_frame])

	# 2. stun_buff remove 事件 (按 abilityInstanceId in [inst_a, inst_b])
	var stun_removes := _filter_stun_removes(ctx, [inst_a, inst_b])
	ctx.assert_eq(stun_removes.size(), 2,
		"Expect both Stun instances to expire (got %d removes)" % stun_removes.size())
	if stun_removes.size() != 2:
		return

	var remove_a_frame := _find_remove_frame(stun_removes, inst_a)
	var remove_b_frame := _find_remove_frame(stun_removes, inst_b)
	ctx.assert_true(remove_a_frame > 0, "Stun A has a remove frame (got %d)" % remove_a_frame)
	ctx.assert_true(remove_b_frame > 0, "Stun B has a remove frame (got %d)" % remove_b_frame)
	ctx.assert_true(remove_a_frame < remove_b_frame,
		"Short Stun A expires (frame %d) before long Stun B (frame %d)" % [
			remove_a_frame, remove_b_frame
		])

	# 3. 战斗结束 caster 无 stun_buff
	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleStunBuff.CONFIG_ID,
		"All Stun buffs revoked after duration"
	)

	# 4. cant_act gate: t=1000 Strike 应失败, t=4500 Strike 应成功
	var caster_activate_failed := _filter_activate_failed_for(ctx, ctx.caster_id, HexBattleStrike.CONFIG_ID)
	ctx.assert_true(caster_activate_failed.size() >= 1,
		"Strike during Stun should produce >=1 AbilityActivateFailed event (got %d)" % caster_activate_failed.size())
	if caster_activate_failed.size() >= 1:
		var reason := str(caster_activate_failed[0].get("reason", ""))
		ctx.assert_true(
			reason.contains(HexBattleActionLockStatus.TAG_CANT_ACT),
			"Strike failed reason contains 'cant_act' (got %s)" % reason
		)

	var strike_damage_to_enemy0 := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_true(strike_damage_to_enemy0.size() >= 1,
		"After Stun expires, Strike should deal damage to enemy_0 (got %d damage events)" % strike_damage_to_enemy0.size())


# ============================================================
# helpers
# ============================================================

func _filter_stun_grants(ctx: ScenarioAssertContext, config_id: String) -> Array:
	var out: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != config_id:
			continue
		out.append(e)
	return out


func _filter_stun_removes(ctx: ScenarioAssertContext, instance_ids: Array) -> Array:
	var out: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		if str(e.get("abilityInstanceId", "")) in instance_ids:
			out.append(e)
	return out


func _find_remove_frame(removes: Array, target_inst: String) -> int:
	for e in removes:
		if str(e.get("abilityInstanceId", "")) == target_inst:
			return int(e.get("replay_frame", -1))
	return -1


## 过滤 actor 触发的 AbilityActivateFailed 事件 (config_id 匹配)
## AbilityActivateFailed 的 source actor 字段名是 `sourceId` (来自 ActiveUseComponent._push_activate_failed)。
func _filter_activate_failed_for(ctx: ScenarioAssertContext, actor_id: String, config_id: String) -> Array:
	var out: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_ACTIVATE_FAILED_EVENT):
		if str(e.get("sourceId", "")) != actor_id:
			continue
		if str(e.get("abilityConfigId", "")) != config_id:
			continue
		out.append(e)
	return out
