## Phase D · Cleanse · priority control > passive_break > other 验证
##
## V1 契约:
## - target 同时持 Stun (control) + Poison (other negative)
## - Cleanse 应优先移除 Stun (control 优先级最高)
## - Poison 保留
##
## 时序:
##   t=0     enemy_0 cast Stun caster (3000ms control)  → HIT @ t=300  → stun_buff grant
##   t=200   enemy_1 cast Poison caster (DOT)          → HIT @ t=500  → poison_buff grant
##   t=600   ally_0 cast Cleanse caster                → HIT @ t=900  → Cleanse 移除 Stun
##           (control 优先级最高, control > passive_break > other)
##
## 期望:
##   - stun_buff revoke 帧 ~ 9 (cleanse hit @ 900ms; 不是自然 expire ~ 33 frame)
##   - poison_buff 仍 grant 但不被 cleanse 移除 (期末仍可能 expire 自然消失)
##   - 1 个 cleanse 事件成功移除 stun
class_name CleansePriorityScenario
extends SkillScenario


const STUN_DUR_MS := 3000.0


func get_name() -> String:
	return "Cleanse priority: control (Stun) > other (Poison) - Stun removed first"


func get_scene_config() -> Dictionary:
	# ally cast Cleanse caster: ally 必须能在 caster 被 stun 时 cast cleanse
	# caster [0,0]; ally_0 [-1,0]; enemy_0 [1,0]; enemy_1 [0,1]
	# Cleanse range=3, ally_0 → caster distance=1 OK
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 30},
		"allies":  [{"class": "WARRIOR", "pos": [-1, 0], "hp": 2000, "atk": 30}],
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10},
			{"class": "WARRIOR", "pos": [0, 1], "hp": 2000, "atk": 10},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		# enemy_0 Stun caster @ t=0 (control 优先级最高)
		{
			"caster": "enemy_0",
			"skill": HexBattleStun.create_config(STUN_DUR_MS),
			"target": "caster",
			"time_ms": 0,
		},
		# enemy_1 Poison caster @ t=200 (other negative)
		{
			"caster": "enemy_1",
			"skill": HexBattlePoison.ABILITY,
			"target": "caster",
			"time_ms": 200,
		},
		# ally_0 Cleanse caster @ t=600 (target "caster" string; cleanse 选 Stun 移除)
		{
			"caster": "ally_0",
			"skill": HexBattleCleanse.ABILITY,
			"target": "caster",
			"time_ms": 600,
		},
	]


func get_max_ticks() -> int:
	return 50


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. caster 上 stun_buff + poison_buff 各 1 grant
	var stun_grant: Dictionary = {}
	var poison_grant: Dictionary = {}
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		var cfg := str(ability_data.get("configId", ""))
		if cfg == HexBattleStunBuff.CONFIG_ID:
			stun_grant = e
		elif cfg == HexBattlePoisonBuff.CONFIG_ID:
			poison_grant = e
	ctx.assert_true(not stun_grant.is_empty(), "Expect Stun buff granted on caster")
	ctx.assert_true(not poison_grant.is_empty(), "Expect Poison buff granted on caster")
	if stun_grant.is_empty() or poison_grant.is_empty():
		return

	# 2. Stun expire frame 必须 < natural expire frame (3300/100=33)
	# Cleanse hit @ ~t=900ms = frame ~9. Stun natural expire @ t=3300ms = frame ~33.
	# 期望 stun remove frame ≈ 9 (cleanse 强制), < 33 (natural).
	var stun_inst := str((stun_grant.get("ability", {}) as Dictionary).get("id", ""))
	var stun_remove_frame := -1
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("abilityInstanceId", "")) == stun_inst:
			stun_remove_frame = int(e.get("replay_frame", -1))
			break
	ctx.assert_true(stun_remove_frame > 0, "Stun should be removed (got frame %d)" % stun_remove_frame)
	# Stun 必须在 cleanse hit (~ frame 9) 附近被 dispel, 远早于 natural expire (~ frame 33)
	ctx.assert_true(stun_remove_frame < 25,
		"Stun removed by Cleanse (frame %d), MUST be earlier than natural expire (~frame 33) — proves control priority" % stun_remove_frame)

	# 3. Poison 没被 Cleanse 移除 (Cleanse 只清最高优先级 1 个)
	# Poison natural expire 取决于 3 stacks * 2000ms tick = ~ 6000ms. max_ticks=50 (5000ms) 内
	# Poison 可能还没自然完结 → 期末仍 present。验证: poison_remove frame > cleanse hit frame
	# (没被 cleanse 移除, 自然 tick 进度)
	var poison_inst := str((poison_grant.get("ability", {}) as Dictionary).get("id", ""))
	var poison_remove_frame := -1
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("abilityInstanceId", "")) == poison_inst:
			poison_remove_frame = int(e.get("replay_frame", -1))
			break
	# Poison expire 应远晚于 cleanse hit, 或战斗结束时仍在 (no remove event)
	if poison_remove_frame >= 0:
		ctx.assert_true(poison_remove_frame > stun_remove_frame,
			"Poison NOT cleansed first (frame %d), Stun removed first (frame %d) — control priority works" % [poison_remove_frame, stun_remove_frame])
