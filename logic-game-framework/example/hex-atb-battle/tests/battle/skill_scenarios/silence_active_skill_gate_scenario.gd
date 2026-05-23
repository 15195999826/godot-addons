## Phase B · Silence · ActiveGateway gate
##
## Silence 阻挡"真正的 active skill" (Fireball / Poison / Stun / etc),
## 但不挡 Strike / Move / passive / buff tick。
##
## 时序:
##   t=0     caster cast Silence enemy_0 → HIT @ t=300 → SilenceBuff grant
##   t=600   enemy_0 try Fireball caster → FAIL (cant_use_skill)
##   t=1000  enemy_0 Strike caster      → SUCCESS (Strike 无 cant_use_skill condition,不被挡)
##   t=2300  SilenceBuff expire (300 + 2000)
##   t=3000  enemy_0 Fireball caster    → SUCCESS (silence 已清)
##
## 断言:
##   - enemy_0 上 1 次 buff_silence grant + 1 次 remove
##   - 1 次 AbilityActivateFailed for enemy_0 fireball, reason 含 cant_use_skill
##   - Strike → damage event caster (silence 不挡 Strike)
##   - 后段 Fireball → damage event caster (silence 已 expire)
##   - 战斗结束 enemy_0 无 silence_buff
class_name SilenceActiveSkillGateScenario
extends SkillScenario


const SILENCE_DUR_MS := 2000.0


func get_name() -> String:
	return "Silence gates active skill (Fireball blocked, Strike NOT blocked)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 4, "cols": 4},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 30},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 25}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		# caster 沉默 enemy_0
		{
			"caster": "caster",
			"skill": HexBattleSilence.create_config(SILENCE_DUR_MS),
			"target": "enemy_0",
			"time_ms": 0,
		},
		# 沉默期内: Fireball 应被挡
		{
			"caster": "enemy_0",
			"skill": HexBattleFireball.ABILITY,
			"target": "caster",
			"time_ms": 600,
		},
		# 沉默期内: Strike 不应被挡
		{
			"caster": "enemy_0",
			"skill": HexBattleStrike.ABILITY,
			"target": "caster",
			"time_ms": 1000,
		},
		# 沉默已 expire (2300ms): Fireball 应成功
		{
			"caster": "enemy_0",
			"skill": HexBattleFireball.ABILITY,
			"target": "caster",
			"time_ms": 3000,
		},
	]


## 3000 + Fireball cast/projectile + post_buffer ~5000ms; 60 ticks=6000ms 安全。
func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. enemy_0 上 1 次 buff_silence grant
	var silence_grants := _filter_grants_on(ctx, ctx.enemy_id(0), HexBattleSilenceBuff.CONFIG_ID)
	ctx.assert_eq(silence_grants.size(), 1,
		"Expect 1 HexBattleSilenceBuff grant on enemy_0 (got %d)" % silence_grants.size())

	# 2. enemy_0 上 1 次 buff_silence remove (duration expire)
	if silence_grants.size() == 1:
		var silence_inst := str((silence_grants[0].get("ability", {}) as Dictionary).get("id", ""))
		var silence_removes := _filter_removes_of(ctx, ctx.enemy_id(0), silence_inst)
		ctx.assert_eq(silence_removes.size(), 1,
			"Expect SilenceBuff to expire by end of run (got %d removes)" % silence_removes.size())

	# 3. enemy_0 Fireball 在沉默期内应失败, reason 含 cant_use_skill
	var fireball_failed := _filter_activate_failed_for(ctx, ctx.enemy_id(0), HexBattleFireball.CONFIG_ID)
	ctx.assert_true(fireball_failed.size() >= 1,
		"Expect Fireball to fail during Silence (got %d failures)" % fireball_failed.size())
	if fireball_failed.size() >= 1:
		var reason := str(fireball_failed[0].get("reason", ""))
		ctx.assert_true(reason.contains(HexBattleSilenceBuff.TAG_CANT_USE_SKILL),
			"Fireball fail reason contains 'cant_use_skill' (got %s)" % reason)

	# 4. enemy_0 Strike 在沉默期内应成功 → damage event caster
	# Fireball 在沉默后应成功 → damage event caster
	# (检查至少 1 个 damage caster 来自 enemy_0; Strike 是物理, Fireball 是魔法)
	var damages_to_caster := ctx.filter_damage_events({
		"source_actor_id": ctx.enemy_id(0),
		"target_actor_id": ctx.caster_id,
	})
	# 期望: Strike 25 phys (t=1000 内) + Fireball ? magic (t=3000 后)
	# 至少 2 次 damage event (1 strike + 1 fireball)
	ctx.assert_true(damages_to_caster.size() >= 2,
		"Expect Strike (during silence) + Fireball (after silence) both deal damage to caster (got %d events)" % damages_to_caster.size())

	# 5. 战斗结束 enemy_0 无 silence_buff
	ctx.assert_actor_ability_absent(
		ctx.enemy_id(0), HexBattleSilenceBuff.CONFIG_ID,
		"SilenceBuff revoked after duration expire"
	)

	# 6. Strike 不该 AbilityActivateFailed (Strike 不挂 cant_use_skill condition)
	var strike_failed := _filter_activate_failed_for(ctx, ctx.enemy_id(0), HexBattleStrike.CONFIG_ID)
	ctx.assert_eq(strike_failed.size(), 0,
		"Strike must NOT be blocked by Silence (got %d failures)" % strike_failed.size())


# ============================================================
# helpers
# ============================================================

func _filter_grants_on(ctx: ScenarioAssertContext, actor_id: String, config_id: String) -> Array:
	var out: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != actor_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != config_id:
			continue
		out.append(e)
	return out


func _filter_removes_of(ctx: ScenarioAssertContext, actor_id: String, instance_id: String) -> Array:
	var out: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("actorId", "")) != actor_id:
			continue
		if str(e.get("abilityInstanceId", "")) == instance_id:
			out.append(e)
	return out


func _filter_activate_failed_for(ctx: ScenarioAssertContext, actor_id: String, config_id: String) -> Array:
	var out: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_ACTIVATE_FAILED_EVENT):
		if str(e.get("sourceId", "")) != actor_id:
			continue
		if str(e.get("abilityConfigId", "")) != config_id:
			continue
		out.append(e)
	return out
