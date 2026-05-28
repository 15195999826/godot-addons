## Phase E · Angle Cone StageCueAction.params 携带 selector 检查区域
##
## V1 契约:
## - on_timeline_start StageCue (cueId='angle_cone_cast') params 字段含:
##     shape="angle_cone"
##     origin_coord, target_coord
##     checked_coords (Array of {q,r}) = compute_checked_coords output
##     edge_segments (2 world-space lines) = left/right angle boundary rays
##     range=CONE_RANGE
##     half_angle_deg=HALF_ANGLE_DEG
##   不含 cast_direction / direction_edges (那是 grid_cone 字段)
class_name ConeAngleStageCueParamsScenario
extends SkillScenario


func get_name() -> String:
	return "Cone Angle: StageCue.params carries shape / checked_coords / half_angle_deg"


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
		"skill": HexBattleAngleCone.ABILITY,
		"target_coord": {"q": 3, "r": 0},
		"time_ms": 0,
	}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var cue: Dictionary = {}
	for e in ctx.events:
		if str(e.get("kind", "")) != "stageCue":
			continue
		if str(e.get("cueId", "")) != "angle_cone_cast":
			continue
		cue = e
		break
	ctx.assert_true(not cue.is_empty(), "angle_cone_cast stageCue event present")
	if cue.is_empty():
		return
	var params: Dictionary = cue.get("params", {}) as Dictionary
	ctx.assert_eq(params.get("shape", ""), "angle_cone", "shape = angle_cone")
	ctx.assert_eq(params.get("range", 0), HexBattleAngleCone.CONE_RANGE,
		"range = %d" % HexBattleAngleCone.CONE_RANGE)
	ctx.assert_float_eq(params.get("half_angle_deg", -1.0) as float,
		HexBattleAngleCone.HALF_ANGLE_DEG,
		"half_angle_deg = %.1f" % HexBattleAngleCone.HALF_ANGLE_DEG, 0.01)

	# origin / target coord
	var origin: Dictionary = params.get("origin_coord", {}) as Dictionary
	ctx.assert_eq(int(origin.get("q", 99)), 0, "origin.q = 0")
	ctx.assert_eq(int(origin.get("r", 99)), 0, "origin.r = 0")
	var tc: Dictionary = params.get("target_coord", {}) as Dictionary
	ctx.assert_eq(int(tc.get("q", 99)), 3, "target_coord.q = 3")
	ctx.assert_eq(int(tc.get("r", 99)), 0, "target_coord.r = 0")

	# 不应含 grid-only 字段
	ctx.assert_true(not params.has("cast_direction"),
		"angle_cone params should NOT carry cast_direction (grid-only field)")
	ctx.assert_true(not params.has("direction_sector"),
		"angle_cone params should NOT carry old direction_sector field")
	ctx.assert_true(not params.has("direction_edges"),
		"angle_cone params should NOT carry direction_edges (grid-only field)")

	# checked_coords 非空
	var checked: Array = params.get("checked_coords", []) as Array
	ctx.assert_true(checked.size() > 0,
		"angle_cone checked_coords non-empty (got %d)" % checked.size())
	# (1,0) 直 east 必在 cone 内 (0° world angle < 45°)
	var contains_1_0 := false
	for c in checked:
		if int(c.get("q", 99)) == 1 and int(c.get("r", 99)) == 0:
			contains_1_0 = true
			break
	ctx.assert_true(contains_1_0, "checked_coords contains (1,0) directly forward")

	# angle_cone 需要携带两条真实角度边界线, frontend 不能只靠 checked cell footprint 反推.
	var edge_segments: Array = params.get("edge_segments", []) as Array
	ctx.assert_eq(edge_segments.size(), 2, "angle_cone carries exactly 2 edge_segments")
	for i in range(edge_segments.size()):
		var edge: Dictionary = edge_segments[i] as Dictionary
		var start_dict: Dictionary = edge.get("start", {}) as Dictionary
		var end_dict: Dictionary = edge.get("end", {}) as Dictionary
		ctx.assert_true(start_dict.has("x") and start_dict.has("y"),
			"edge_segments[%d].start has x/y" % i)
		ctx.assert_true(end_dict.has("x") and end_dict.has("y"),
			"edge_segments[%d].end has x/y" % i)
		var start_pos := Vector2(
			float(start_dict.get("x", 0.0)),
			float(start_dict.get("y", 0.0))
		)
		var end_pos := Vector2(
			float(end_dict.get("x", 0.0)),
			float(end_dict.get("y", 0.0))
		)
		ctx.assert_true(start_pos.distance_to(end_pos) > 0.1,
			"edge_segments[%d] should be a non-zero guide ray" % i)
