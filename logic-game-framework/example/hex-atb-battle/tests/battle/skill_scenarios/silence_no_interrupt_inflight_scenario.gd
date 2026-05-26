## Phase B · Silence · in-flight execution NOT cancelled
##
## Silence 与 Stun 的关键差别: silence_buff.gd 的 NoInstanceConfig.on_apply_actions 故意
## 不挂 CancelActiveExecutionsAction (cf. stun_buff.gd:55 — Stun 显式取消)。
## 因此 silence 命中时, 目标已在 in-flight 的 active execution 应继续完成,
## 不被 cancel。Goal doc:
##   "silence 不影响已在执行中的 timeline"。
##
## 时序 (利用 Crushing Blow 长 cast 1000ms / HIT@600ms):
##   t=0     enemy_0 cast Crushing Blow caster → cast 0→1000, HIT @ t=600
##   t=100   caster cast Silence enemy_0     → cast 100→600, HIT @ t=400 → SilenceBuff grant
##                                             此时 enemy_0 的 Crushing Blow execution 已 in-flight,
##                                             silence 不取消 (区别于 Stun)
##   t=600   enemy_0 Crushing Blow HIT @ t=600 → damage event caster (无视 silence)
##
## 断言:
##   - SilenceBuff grant on enemy_0 frame < Crushing Blow damage event frame
##     (silence 在 crushing_blow HIT 之前落地)
##   - >=1 damage event source=enemy_0 target=caster (Crushing Blow HIT 仍发生)
##   - damage 数值与 Crushing Blow 基础值 90 一致
class_name SilenceNoInterruptInflightScenario
extends SkillScenario


func get_name() -> String:
	return "Silence does NOT cancel in-flight execution (Crushing Blow finishes)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 25},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 25}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		# enemy_0 cast Crushing Blow on caster (cast 1000ms, HIT @ 600ms)
		{
			"caster": "enemy_0",
			"skill": HexBattleCrushingBlow.ABILITY,
			"target": "caster",
			"time_ms": 0,
		},
		# caster cast Silence on enemy_0 (cast 500ms, HIT @ 300ms)
		# Silence apply 时间 ≈ t=400ms, 早于 Crushing Blow HIT @ t=600ms
		{
			"caster": "caster",
			"skill": HexBattleSilence.create_config(2000.0),
			"target": "enemy_0",
			"time_ms": 100,
		},
	]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. SilenceBuff 在 enemy_0 上 grant
	var silence_grants: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.enemy_id(0):
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) != HexBattleSilenceBuff.CONFIG_ID:
			continue
		silence_grants.append(e)
	ctx.assert_eq(silence_grants.size(), 1,
		"Expect 1 SilenceBuff grant on enemy_0 (got %d)" % silence_grants.size())
	if silence_grants.size() != 1:
		return

	var silence_grant_frame := int(silence_grants[0].get("replay_frame", -1))

	# 2. Crushing Blow damage event source=enemy_0 target=caster 仍发生 (in-flight 不被 cancel)
	var crushing_damage := ctx.filter_damage_events({
		"source_actor_id": ctx.enemy_id(0),
		"target_actor_id": ctx.caster_id,
	})
	ctx.assert_true(crushing_damage.size() >= 1,
		"Expect Crushing Blow damage to caster despite silence (got %d events)" % crushing_damage.size())
	if crushing_damage.size() == 0:
		return

	# 3. silence grant frame < crushing blow damage frame
	# (Silence 在 Crushing Blow HIT 之前 land, 但 in-flight execution 继续完成)
	var damage_frame := int(crushing_damage[0].get("replay_frame", -1))
	ctx.assert_true(silence_grant_frame < damage_frame,
		"SilenceBuff grant frame %d should land BEFORE Crushing Blow damage frame %d (proving silence didn't cancel in-flight)" % [
			silence_grant_frame, damage_frame
		])

	# 4. damage 数值 = Crushing Blow 基础值 90
	var damage_value := crushing_damage[0].get("damage", 0.0) as float
	ctx.assert_float_eq(damage_value, 90.0,
		"Crushing Blow damage should be 90, got %.1f" % damage_value)
