## Phase D · 同站位下, skill_grid_cone 与 skill_angle_cone 命中集合可区分
##
## 当前契约:
## - grid cone: origin = target_coord, direction = caster→target_coord, fixed 1+3+5 footprint
## - angle cone: origin = caster, forward = caster→target_coord
## - 两者不再是包含关系; 这个 scenario 只证明它们的 origin 语义不同。
class_name ConeGridVsAngleDistinguishableScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "Cone: grid target-origin differs from angle caster-origin"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 6},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": CASTER_ATK},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 2000, "atk": 0},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 2000, "atk": 0},
			{"class": "WARRIOR", "pos": [4, 0], "hp": 2000, "atk": 0},
			{"class": "WARRIOR", "pos": [4, -1], "hp": 2000, "atk": 0},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattleGridCone.ABILITY,
			"target_coord": {"q": 2, "r": 0},
			"time_ms": 0,
		},
		{
			"caster": "caster",
			"skill": HexBattleAngleCone.ABILITY,
			"target_coord": {"q": 2, "r": 0},
			"time_ms": 10000,
		},
	]


func get_max_ticks() -> int:
	return 120


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var all_hits := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"damage_type": "physical",
	})
	var grid_targets: Array[String] = []
	var angle_targets: Array[String] = []
	for h in all_hits:
		var tid := str(h.get("target_actor_id", ""))
		var frame := int(h.get("replay_frame", 0))
		if frame < 50:
			if tid not in grid_targets:
				grid_targets.append(tid)
		else:
			if tid not in angle_targets:
				angle_targets.append(tid)

	ctx.assert_true(grid_targets.size() > 0,
		"grid cone hit at least 1 enemy (got %d)" % grid_targets.size())
	ctx.assert_true(angle_targets.size() > 0,
		"angle cone hit at least 1 enemy (got %d)" % angle_targets.size())

	ctx.assert_true(ctx.enemy_id(3) in grid_targets,
		"grid target-origin footprint reaches enemy_3 (4,0)")
	ctx.assert_true(ctx.enemy_id(3) not in angle_targets,
		"angle caster-origin cone range does not reach enemy_3 (4,0)")
	ctx.assert_true(ctx.enemy_id(0) not in grid_targets,
		"grid target-origin cone excludes caster-side enemy_0 (1,0)")
	ctx.assert_true(ctx.enemy_id(0) in angle_targets,
		"angle caster-origin cone includes caster-side enemy_0 (1,0)")
