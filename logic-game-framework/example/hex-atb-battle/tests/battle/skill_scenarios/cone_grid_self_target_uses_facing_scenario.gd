## Phase D · Grid Cone 支持 target_coord == caster, 此时使用 caster 当前 facing
## range=3 包含 origin, NE-facing footprint 以 NE 为中心线, E/NW 为两侧边界。
class_name ConeGridSelfTargetUsesFacingScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "Cone Grid: self target uses caster facing direction"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 5},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000, "atk": CASTER_ATK},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, -1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [0, -1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, -2], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [1, -2], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [0, -2], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, -1], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "atk": 0},
			{"class": "WARRIOR", "pos": [-1, 0], "hp": 1000, "atk": 0},
		],
	}


func setup_battle(
	_battle: Object,
	caster: Object,
	_ally_actors: Array,
	_enemy_actors: Array,
	setup_errors: Array,
) -> bool:
	var caster_actor := caster as CharacterActor
	if caster_actor == null:
		setup_errors.append("caster is not CharacterActor")
		return false
	caster_actor.set_facing_direction(HexFacing.DIR_NORTHEAST)
	return true


func get_actions() -> Array[Dictionary]:
	return [{
		"caster": "caster",
		"skill": HexBattleGridCone.ABILITY,
		"target_coord": {"q": 0, "r": 0},
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

	ctx.assert_eq(hit_targets.size(), 8,
		"Expect 8 self-target facing cone targets, got %d" % hit_targets.size())
	ctx.assert_true(ctx.enemy_id(0) in hit_targets,
		"enemy_0 (1,-1) NE from caster/facing origin hit")
	ctx.assert_true(ctx.enemy_id(1) in hit_targets,
		"enemy_1 (0,-1) NW edge from caster/facing origin hit")
	ctx.assert_true(ctx.enemy_id(2) in hit_targets,
		"enemy_2 (2,-2) NE edge layer 3 hit")
	ctx.assert_true(ctx.enemy_id(3) in hit_targets,
		"enemy_3 (1,-2) layer 3 interior hit")
	ctx.assert_true(ctx.enemy_id(4) in hit_targets,
		"enemy_4 (0,-2) NW edge layer 3 hit")
	ctx.assert_true(ctx.enemy_id(5) in hit_targets,
		"enemy_5 (1,0) E boundary layer 2 hit")
	ctx.assert_true(ctx.enemy_id(6) in hit_targets,
		"enemy_6 (2,-1) E-side layer 3 interior hit")
	ctx.assert_true(ctx.enemy_id(7) in hit_targets,
		"enemy_7 (2,0) E boundary layer 3 hit")
	ctx.assert_true(ctx.enemy_id(8) not in hit_targets,
		"enemy_8 (-1,0) behind NE-facing cone NOT hit")
