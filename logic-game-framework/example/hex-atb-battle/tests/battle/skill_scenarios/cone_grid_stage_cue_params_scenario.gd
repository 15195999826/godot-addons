## Phase E · Grid Cone StageCueAction.params 携带 selector 检查区域
##
## V1 契约:
## - on_timeline_start 的 StageCue (cueId='grid_cone_cast') params 字段含:
##     shape="grid_cone"
##     origin_coord={q,r} = caster.hex_position
##     target_coord={q,r} = event.target_coord
##     checked_coords=[{q,r}, ...] = HexBattleGridCone.compute_checked_coords(...) 输出
##     range=CONE_RANGE
##     cast_direction (0..5)
##     direction_sector=[3 dirs]
## - checked_coords ⊋ targetActorIds 所在格 (cone 内不一定都有 enemy)
class_name ConeGridStageCueParamsScenario
extends SkillScenario


func get_name() -> String:
	return "Cone Grid: StageCue.params carries selector checked_coords / shape / cast_direction"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 5},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000, "atk": 40},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "atk": 0},
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
	# Find stageCue event for grid_cone_cast
	var cue: Dictionary = {}
	for e in ctx.events:
		if str(e.get("kind", "")) != "stageCue":
			continue
		if str(e.get("cueId", "")) != "grid_cone_cast":
			continue
		cue = e
		break
	ctx.assert_true(not cue.is_empty(), "grid_cone_cast stageCue event present")
	if cue.is_empty():
		return
	var params: Dictionary = cue.get("params", {}) as Dictionary
	ctx.assert_eq(params.get("shape", ""), "grid_cone", "shape = grid_cone")
	ctx.assert_eq(params.get("range", 0), HexBattleGridCone.CONE_RANGE,
		"range = %d" % HexBattleGridCone.CONE_RANGE)

	# origin_coord = caster pos (0,0)
	var origin: Dictionary = params.get("origin_coord", {}) as Dictionary
	ctx.assert_eq(int(origin.get("q", 99)), 0, "origin_coord.q = caster (0)")
	ctx.assert_eq(int(origin.get("r", 99)), 0, "origin_coord.r = caster (0)")

	# target_coord = (3, 0)
	var tc: Dictionary = params.get("target_coord", {}) as Dictionary
	ctx.assert_eq(int(tc.get("q", 99)), 3, "target_coord.q = 3")
	ctx.assert_eq(int(tc.get("r", 99)), 0, "target_coord.r = 0")

	# cast_direction = EAST (0)
	ctx.assert_eq(int(params.get("cast_direction", -1)), 0, "cast_direction = EAST(0)")

	# direction_sector = [SE(5), E(0), NE(1)]
	var sector: Array = params.get("direction_sector", []) as Array
	ctx.assert_eq(sector.size(), 3, "direction_sector has 3 entries")
	if sector.size() == 3:
		ctx.assert_eq(int(sector[0]), 5, "sector[0] = SE(5)")
		ctx.assert_eq(int(sector[1]), 0, "sector[1] = E(0)")
		ctx.assert_eq(int(sector[2]), 1, "sector[2] = NE(1)")

	# checked_coords = HexBattleGridCone.compute_checked_coords((0,0), (3,0))
	# 数量应 ≥ 1 (至少 (1,0) 在前方 sector 内)
	var checked: Array = params.get("checked_coords", []) as Array
	ctx.assert_true(checked.size() > 0, "checked_coords non-empty (got %d)" % checked.size())
	# 验证 (1,0) (target direction near caster) 在 checked_coords 内
	var contains_1_0 := false
	for c in checked:
		if int(c.get("q", 99)) == 1 and int(c.get("r", 99)) == 0:
			contains_1_0 = true
			break
	ctx.assert_true(contains_1_0, "checked_coords contains (1,0) — adjacent in cast direction")

	# targetActorIds 仅含真正命中的 actor (== enemy_0), 不等于 checked_coords
	var target_actor_ids: Array = cue.get("targetActorIds", []) as Array
	ctx.assert_eq(target_actor_ids.size(), 1, "stageCue carries only caster as 1 owner target (no enemy actor)")
	ctx.assert_true(checked.size() > target_actor_ids.size(),
		"checked_coords (%d) strictly > targetActorIds (%d) — distinct semantics" % [checked.size(), target_actor_ids.size()])
