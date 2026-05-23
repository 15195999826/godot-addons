## Phase A · Stun · Case 2: 长前短后
##
## 对称 case (per Goal.md Case 2): 长 Stun 先施加, 短 Stun 后施加, 短 Stun 先到期但
## cant_act 仍由长 Stun 维持。
##
## 时序:
##   t=0     enemy_0 cast Stun_long (dur=3000ms) → HIT @ t=300 → Stun A grant
##   t=500   enemy_1 cast Stun_short(dur=1000ms) → HIT @ t=800 → Stun B grant
##   t=1500  caster try Strike enemy_0 → FAIL (cant_act, A 还在)
##   t=1800  Stun B expire (800 + 1000)
##   t=3300  Stun A expire (300 + 3000)
##   t=4500  caster try Strike enemy_0 → SUCCESS (cant_act 清)
class_name StunIndependentInstancesLongFirstScenario
extends SkillScenario


const STUN_DUR_LONG_MS  := 3000.0
const STUN_DUR_SHORT_MS := 1000.0


func get_name() -> String:
	return "Stun independent instances (long first, short second)"


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
			"skill": HexBattleStun.create_config(STUN_DUR_LONG_MS),
			"target": "caster",
			"time_ms": 0,
		},
		{
			"caster": "enemy_1",
			"skill": HexBattleStun.create_config(STUN_DUR_SHORT_MS),
			"target": "caster",
			"time_ms": 500,
		},
		# 短 Stun 已过期但长 Stun 未过期: cant_act 仍生效, Strike 失败
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 2200,
		},
		# 两 Stun 都过期后: Strike 成功
		{
			"caster": "caster",
			"skill": HexBattleStrike.ABILITY,
			"target": "enemy_0",
			"time_ms": 4500,
		},
	]


func get_max_ticks() -> int:
	return 70


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var stun_grants := _filter_stun_grants(ctx, HexBattleStunBuff.CONFIG_ID)
	ctx.assert_eq(stun_grants.size(), 2,
		"Expect 2 independent HexBattleStunBuff grants on caster")
	if stun_grants.size() != 2:
		return

	# stun_grants[0] = enemy_0 (长), stun_grants[1] = enemy_1 (短)
	var inst_long  := str((stun_grants[0].get("ability", {}) as Dictionary).get("id", ""))
	var inst_short := str((stun_grants[1].get("ability", {}) as Dictionary).get("id", ""))
	ctx.assert_true(inst_long != inst_short,
		"Long Stun id != Short Stun id (independent instances)")

	var stun_removes := _filter_stun_removes(ctx, [inst_long, inst_short])
	ctx.assert_eq(stun_removes.size(), 2,
		"Expect both Stun instances to expire (got %d removes)" % stun_removes.size())
	if stun_removes.size() != 2:
		return

	var remove_long_frame  := _find_remove_frame(stun_removes, inst_long)
	var remove_short_frame := _find_remove_frame(stun_removes, inst_short)
	ctx.assert_true(remove_long_frame > 0, "Long Stun has a remove frame")
	ctx.assert_true(remove_short_frame > 0, "Short Stun has a remove frame")
	# Case 2 关键: 短 Stun (后挂) 先到期, 长 Stun (先挂) 后到期 — 与 grant 顺序相反
	ctx.assert_true(remove_short_frame < remove_long_frame,
		"Short Stun (granted later) expires (frame %d) before long Stun (frame %d)" % [
			remove_short_frame, remove_long_frame
		])

	ctx.assert_actor_ability_absent(
		ctx.caster_id, HexBattleStunBuff.CONFIG_ID,
		"All Stun buffs revoked after duration"
	)

	# t=2200 时长 Stun 还在 → Strike 应失败
	var failed := _filter_activate_failed_for(ctx, ctx.caster_id, HexBattleStrike.CONFIG_ID)
	ctx.assert_true(failed.size() >= 1,
		"Strike while long Stun in flight should produce AbilityActivateFailed (got %d)" % failed.size())
	if failed.size() >= 1:
		var reason := str(failed[0].get("reason", ""))
		ctx.assert_true(
			reason.contains(HexBattleActionLockStatus.TAG_CANT_ACT),
			"Strike failed reason contains 'cant_act' (got %s)" % reason
		)

	# t=4500 Strike 成功 → damage event
	var strike_damage_to_enemy0 := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_true(strike_damage_to_enemy0.size() >= 1,
		"After both Stuns expire, Strike should deal damage (got %d events)" % strike_damage_to_enemy0.size())


# ============================================================
# helpers (与 short-first scenario 同结构, 各自独立避免跨文件依赖)
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
