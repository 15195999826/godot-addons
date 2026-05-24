## Phase E · Angle Cone StageCueAction.params 携带 selector 检查区域
##
## V1 契约:
## - on_timeline_start StageCue (cueId='angle_cone_cast') params 字段含:
##     shape="angle_cone"
##     origin_coord, target_coord
##     checked_coords (Array of {q,r}) = compute_checked_coords output
##     range=CONE_RANGE
##     half_angle_deg=HALF_ANGLE_DEG
##   不含 cast_direction / direction_sector (那是 grid_cone 字段)
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
		"angle_cone params should NOT carry direction_sector (grid-only field)")

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
