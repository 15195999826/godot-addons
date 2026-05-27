## Phase D · Grid Cone 以 target_coord 为 origin, 命中固定中心锥形 footprint 的 alive 敌人
##
## 契约:
## - caster=(0,0), target_coord=(2,0) → cast_dir = HexFacing.DIR_EAST (0)
## - cone origin = target_coord=(2,0), 不是 caster
## - range=3 包含 target_coord 自身, 选区是 1+3+5 格固定中心锥形 footprint
## - footprint 以 EAST 为中心线, NORTHEAST/SOUTHEAST 为两侧边界
## - 同 hit keyframe 多目标共一 DamageAction.execute → 多 DamageEvent
##
## 站位 (caster 在 (0,0)):
##   enemy_0 (2,0)  origin                 — hit
##   enemy_1 (3,0)  layer 2 EAST center    — hit
##   enemy_2 (3,-1) layer 2 NE boundary    — hit
##   enemy_3 (2,1)  layer 2 SE boundary    — hit
##   enemy_4 (4,0)  layer 3 EAST center    — hit
##   enemy_5 (4,-1) layer 3 NE interior    — hit
##   enemy_6 (4,-2) layer 3 NE boundary    — hit
##   enemy_7 (3,1)  layer 3 SE interior    — hit
##   enemy_8 (2,2)  layer 3 SE boundary    — hit
##   enemy_9 (4,1)  old broad-sector cell  — NOT hit
##   enemy_10 (1,0) caster-side cell       — NOT hit
class_name ConeGridHitsSectorScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "Cone Grid: target coord is cone origin, not caster"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 6},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000, "atk": CASTER_ATK},
		"enemies": [
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [3, -1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, 1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [4, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [4, -1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [4, -2], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [3, 1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, 2], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [4, 1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [{
		"caster": "caster",
		"skill": HexBattleGridCone.ABILITY,
		"target_coord": {"q": 2, "r": 0},
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

	ctx.assert_eq(hit_targets.size(), 9,
		"Expect 9 fixed-footprint cone targets, got %d" % hit_targets.size())
	ctx.assert_true(ctx.enemy_id(0) in hit_targets,
		"enemy_0 (2,0) cone origin hit")
	ctx.assert_true(ctx.enemy_id(1) in hit_targets,
		"enemy_1 (3,0) EAST center layer hit")
	ctx.assert_true(ctx.enemy_id(2) in hit_targets,
		"enemy_2 (3,-1) NORTHEAST boundary hit")
	ctx.assert_true(ctx.enemy_id(3) in hit_targets,
		"enemy_3 (2,1) SOUTHEAST boundary hit")
	ctx.assert_true(ctx.enemy_id(4) in hit_targets,
		"enemy_4 (4,0) EAST center layer hit even outside caster range")
	ctx.assert_true(ctx.enemy_id(5) in hit_targets,
		"enemy_5 (4,-1) NORTHEAST interior hit")
	ctx.assert_true(ctx.enemy_id(6) in hit_targets,
		"enemy_6 (4,-2) NORTHEAST boundary hit")
	ctx.assert_true(ctx.enemy_id(7) in hit_targets,
		"enemy_7 (3,1) SOUTHEAST interior hit")
	ctx.assert_true(ctx.enemy_id(8) in hit_targets,
		"enemy_8 (2,2) SOUTHEAST boundary hit")
	ctx.assert_true(ctx.enemy_id(9) not in hit_targets,
		"enemy_9 (4,1) was old broad-sector spillover and must NOT hit")
	ctx.assert_true(ctx.enemy_id(10) not in hit_targets,
		"enemy_10 (1,0) is behind cone origin and must NOT hit")
