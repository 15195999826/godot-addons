## Phase E · Grid Cone StageCueAction.params 携带 target-origin fixed footprint 检查区域
##
## 契约:
## - on_timeline_start 的 StageCue (cueId='grid_cone_cast') params 字段含:
##     shape="grid_cone"
##     origin_coord={q,r} = event.target_coord
##     caster_coord={q,r} = caster.hex_position
##     target_coord={q,r} = event.target_coord
##     checked_coords=[{q,r}, ...] = HexBattleGridCone.compute_checked_coords(...) 输出
##     range=CONE_RANGE
##     cast_direction (0..5)
##     direction_edges=[2 boundary dirs]
## - checked_coords ⊋ targetActorIds 所在格 (cone 内不一定都有 enemy)
class_name ConeGridStageCueParamsScenario
extends SkillScenario


func get_name() -> String:
	return "Cone Grid: StageCue.params carries target-origin checked_coords"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 6},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000, "atk": 40},
		"enemies": [
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "atk": 0},
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

	var origin: Dictionary = params.get("origin_coord", {}) as Dictionary
	ctx.assert_eq(int(origin.get("q", 99)), 2, "origin_coord.q = target_coord.q (2)")
	ctx.assert_eq(int(origin.get("r", 99)), 0, "origin_coord.r = target_coord.r (0)")

	var caster_coord: Dictionary = params.get("caster_coord", {}) as Dictionary
	ctx.assert_eq(int(caster_coord.get("q", 99)), 0, "caster_coord.q = caster (0)")
	ctx.assert_eq(int(caster_coord.get("r", 99)), 0, "caster_coord.r = caster (0)")

	var target_coord: Dictionary = params.get("target_coord", {}) as Dictionary
	ctx.assert_eq(int(target_coord.get("q", 99)), 2, "target_coord.q = 2")
	ctx.assert_eq(int(target_coord.get("r", 99)), 0, "target_coord.r = 0")

	ctx.assert_eq(int(params.get("cast_direction", -1)), HexFacing.DIR_EAST,
		"cast_direction = EAST(0)")

	ctx.assert_true(not params.has("direction_sector"),
		"grid_cone params should not carry old broad-sector field")
	var edges: Array = params.get("direction_edges", []) as Array
	ctx.assert_eq(edges.size(), 2, "direction_edges has 2 entries")
	if edges.size() == 2:
		ctx.assert_eq(int(edges[0]), HexFacing.DIR_NORTHEAST, "edge[0] = NE(1)")
		ctx.assert_eq(int(edges[1]), HexFacing.DIR_SOUTHEAST, "edge[1] = SE(5)")

	var checked: Array = params.get("checked_coords", []) as Array
	ctx.assert_eq(checked.size(), 9, "range=3 includes origin and yields 1+3+5 checked cells")
	ctx.assert_true(_contains_coord(checked, 2, 0), "checked_coords contains cone origin (2,0)")
	ctx.assert_true(_contains_coord(checked, 3, 0), "checked_coords contains layer 2 E center (3,0)")
	ctx.assert_true(_contains_coord(checked, 3, -1), "checked_coords contains layer 2 NE boundary (3,-1)")
	ctx.assert_true(_contains_coord(checked, 2, 1), "checked_coords contains layer 2 SE boundary (2,1)")
	ctx.assert_true(_contains_coord(checked, 4, 0), "checked_coords contains layer 3 E center (4,0)")
	ctx.assert_true(_contains_coord(checked, 4, -1), "checked_coords contains layer 3 NE interior (4,-1)")
	ctx.assert_true(_contains_coord(checked, 4, -2), "checked_coords contains layer 3 NE boundary (4,-2)")
	ctx.assert_true(_contains_coord(checked, 3, 1), "checked_coords contains layer 3 SE interior (3,1)")
	ctx.assert_true(_contains_coord(checked, 2, 2), "checked_coords contains layer 3 SE boundary (2,2)")
	ctx.assert_true(not _contains_coord(checked, 4, 1),
		"checked_coords excludes old broad-sector spillover (4,1)")
	ctx.assert_true(not _contains_coord(checked, 1, 0),
		"checked_coords excludes caster-side cell (1,0)")

	var target_actor_ids: Array = cue.get("targetActorIds", []) as Array
	ctx.assert_eq(target_actor_ids.size(), 1,
		"stageCue carries only caster as 1 owner target (no enemy actor)")
	ctx.assert_true(checked.size() > target_actor_ids.size(),
		"checked_coords (%d) strictly > targetActorIds (%d) — distinct semantics" % [checked.size(), target_actor_ids.size()])


func _contains_coord(coords: Array, q: int, r: int) -> bool:
	for coord_var in coords:
		var coord: Dictionary = coord_var as Dictionary
		if int(coord.get("q", 999999)) == q and int(coord.get("r", 999999)) == r:
			return true
	return false
