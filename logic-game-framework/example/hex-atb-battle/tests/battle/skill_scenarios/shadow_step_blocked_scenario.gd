## Shadow Step blocked-all-around scenario (Phase 02)
##
## enemy_0 周身全 6 邻格被 stone_walls 占据 → teleport_success=false; caster 留在原位,
## 无 ActorDisplacedEvent(teleport), 无 damage event.
##
## enemy_0 at [3,2]; 6 邻格 = [4,2]/[4,1]/[3,1]/[2,2]/[2,3]/[3,3]
## caster at [0,2] (距离 = 3, 在 range 4 内). 全 6 邻格全部用 stone_wall 阻挡.
class_name ShadowStepBlockedScenario
extends SkillScenario


func get_name() -> String:
	return "ShadowStep blocked-all-around: 全 6 邻格阻挡 → teleport 失败 + 无伤害"


func get_scene_config() -> Dictionary:
	# radius=5; enemy_0[3,0]; 6 邻格 = E[4,0] NE[4,-1] NW[3,-1] W[2,0] SW[2,1] SE[3,1]
	return {
		"map": {"radius": 5},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [3, 0], "hp": 1000, "max_hp": 1000},
		],
		"environment": [
			{"type": "stone_wall", "pos": [4, 0]},   # E
			{"type": "stone_wall", "pos": [4, -1]},  # NE
			{"type": "stone_wall", "pos": [3, -1]},  # NW
			{"type": "stone_wall", "pos": [2, 0]},   # W
			{"type": "stone_wall", "pos": [2, 1]},   # SW
			{"type": "stone_wall", "pos": [3, 1]},   # SE
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleShadowStep.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 没有 teleport 事件
	var displaceds: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "actor_displaced" \
				and str(e.get("displacement_kind", "")) == HexBattleShadowStep.DISPLACEMENT_KIND_TELEPORT \
				and str(e.get("source_actor_id", "")) == ctx.caster_id:
			displaceds.append(e)
	ctx.assert_eq(displaceds.size(), 0,
		"全 6 邻格阻挡时不应触发 teleport displacement")

	# enemy_0 不受伤
	var damages := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	ctx.assert_eq(damages.size(), 0,
		"teleport 失败时不造伤 (FlowAction.if_(teleport_success) 阻挡)")

	# caster 仍在 hp 满 (没被打)
	ctx.assert_true(ctx.actor_final_hp(ctx.caster_id) >= 1000.0,
		"caster 不应受伤 (没移动也没被打)")
