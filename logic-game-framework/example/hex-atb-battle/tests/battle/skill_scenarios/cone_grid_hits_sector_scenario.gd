## Phase D · Grid Cone 命中前向 sector 的 alive 敌人, 不命中后方
##
## V1 契约:
## - target_coord=(3,0) (东向) → cast_dir = HexFacing.DIR_EAST (0)
## - sector = {SE(5), E(0), NE(1)} 三方向 hex sector
## - range=3 内, direction_between(caster→candidate) 落在 sector 才命中
## - 同 hit keyframe 多目标共一 DamageAction.execute → 多 DamageEvent
##
## 站位 (caster 在 (0,0)):
##   enemy_0 (1,0)  E  dist 1 — sector ✓
##   enemy_1 (2,0)  E  dist 2 — sector ✓
##   enemy_2 (1,-1) NE dist 1 — sector ✓
##   enemy_3 (-1,0) W  dist 1 — NOT in sector ✗
class_name ConeGridHitsSectorScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "Cone Grid: hits 3 enemies in front sector, NOT enemy in back"


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
		"skill": HexBattleGridCone.ABILITY,
		"target_coord": {"q": 3, "r": 0},
		"time_ms": 0,
	}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 收集 caster 发出的 PHYSICAL damage events
	var hits := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"damage_type": "physical",
	})
	var hit_targets: Array[String] = []
	for h in hits:
		var tid := str(h.get("target_actor_id", ""))
		if tid not in hit_targets:
			hit_targets.append(tid)
	# 命中前方 3 个: enemy_0 enemy_1 enemy_2 (各 1 次 main damage)
	ctx.assert_eq(hit_targets.size(), 3,
		"Expect 3 distinct front targets, got %d" % hit_targets.size())
	ctx.assert_true(ctx.enemy_id(0) in hit_targets,
		"enemy_0 (1,0) E sector hit")
	ctx.assert_true(ctx.enemy_id(1) in hit_targets,
		"enemy_1 (2,0) E sector hit")
	ctx.assert_true(ctx.enemy_id(2) in hit_targets,
		"enemy_2 (1,-1) NE sector hit")
	# 后方 enemy_3 不应被命中
	ctx.assert_true(ctx.enemy_id(3) not in hit_targets,
		"enemy_3 (-1,0) W back NOT hit by grid cone")
