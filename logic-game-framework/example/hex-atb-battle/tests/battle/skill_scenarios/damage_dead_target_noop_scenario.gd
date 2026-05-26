## §0.5 DamageAction dead/null target no-op 通用合同验证
##
## map 3x6, caster(WARRIOR atk=50)[0,0] + enemy(WARRIOR hp=1, max=100)[1,0]。
## 两次 Strike：t=0 致死 enemy_0；t=2500 再次 Strike 同 enemy_0 (已死)。
##
## §0.5 合同:
## - 第二次 DamageAction.execute 时 target 已死 → 全跳过
## - 不产生 damage event (除第一击)
## - 不产生 death event (enemy_0 只死一次,不重复)
## - on_hit / on_critical / on_kill 回调不触发 (本 case strike 无 on_kill)
##
## 注意: Strike COOLDOWN_MS=2000, timeline 500ms. t=2500 第二击对 caster 满足 cooldown。
## scenario harness 通过 abilityActivate event 直接传 target_actor_id, 即使 enemy_0
## 已死, ability timeline 仍能 spawn 并 reach HIT tag, 然后 DamageAction.execute
## 在 §0.5 guard 跳过。
class_name DamageDeadTargetNoOpScenario
extends SkillScenario


const CASTER_ATK := 50.0


func get_name() -> String:
	return "DamageAction §0.5: 对已死目标的二次 Strike 全部跳过 (不产生 damage / death event)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 6},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": CASTER_ATK, "hp": 1000},
		"enemies": [
			# hp=1, 一击必死;max_hp=100 保持死亡记录字段稳定
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1, "max_hp": 100},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0},
		# 第二次 strike: enemy_0 已死,§0.5 应让 DamageAction skip
		{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 2500},
	]


## t=2500 + timeline 500ms + buffer ≈ 3200ms / 100ms tick ≈ 32, 取 50。
func get_max_ticks() -> int:
	return 50


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var damages := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	# 仅第一击命中,第二击对死者必须 skip
	ctx.assert_eq(damages.size(), 1,
		"§0.5: 对已死 enemy_0 的第二次 Strike 不应产生 damage event")

	# 死亡事件只应有 1 个 (第一击致死,第二次跳过)
	var deaths: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "death" and str(e.get("actor_id", "")) == ctx.enemy_id(0):
			deaths.append(e)
	ctx.assert_eq(deaths.size(), 1,
		"§0.5: enemy_0 只 die 一次,第二次 Strike 不应触发额外 DeathEvent")

	# enemy_0 最终 hp <= 0
	ctx.assert_true(ctx.actor_final_hp(ctx.enemy_id(0)) <= 0.0,
		"enemy_0 应已死 (hp <= 0)")
