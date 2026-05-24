## Phase D · Angle Cone 比 Grid Cone 窄: 45° 半角不命中 NE/SE 邻格
##
## V1 契约:
## - target_coord=(3,0) (东向) → forward = +x
## - half_angle = 45° + epsilon
## - candidate NE/SE 邻格在 grid sector 内, 但真实 world 角度 ≈ 60°(flat-top hex), 超过 45°,不命中
## - 直 east 方向的 enemy 命中
##
## 同 ConeGridHitsSectorScenario 站位, 改 cast skill_angle_cone.
class_name ConeAngleNarrowScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "Cone Angle: 45° half-angle hits only forward-east enemies (narrower than grid)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 5},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000, "atk": CASTER_ATK},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [1, -1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [-1, 0], "hp": 1000, "atk": 0},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [{
		"caster": "caster",
		"skill": HexBattleAngleCone.ABILITY,
		"target_coord": {"q": 3, "r": 0},
		"time_ms": 0,
	}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var hits := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"damage_type": "physical",
	})
	var hit_targets: Array[String] = []
	for h in hits:
		var tid := str(h.get("target_actor_id", ""))
		if tid not in hit_targets:
			hit_targets.append(tid)
	# 仅命中正东 enemy_0 (1,0) + enemy_1 (2,0); NE enemy_2 (60° > 45°) 不命中.
	ctx.assert_eq(hit_targets.size(), 2,
		"Angle cone narrower: hit 2 strictly forward enemies, got %d" % hit_targets.size())
	ctx.assert_true(ctx.enemy_id(0) in hit_targets,
		"enemy_0 (1,0) directly east is in 45° cone")
	ctx.assert_true(ctx.enemy_id(1) in hit_targets,
		"enemy_1 (2,0) directly east is in 45° cone")
	ctx.assert_true(ctx.enemy_id(2) not in hit_targets,
		"enemy_2 (1,-1) NE at ~60° world angle, OUTSIDE 45° half-angle")
	ctx.assert_true(ctx.enemy_id(3) not in hit_targets,
		"enemy_3 (-1,0) W far behind cone")
