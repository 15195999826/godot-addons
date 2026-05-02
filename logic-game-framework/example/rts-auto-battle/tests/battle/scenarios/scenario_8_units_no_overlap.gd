## scenario_8_units_no_overlap (P3.3 寻路验证 2/4)
##
## 验证: 8 单位同令到同一目标 (formation), 抵达后 pairwise_min_distance ≥ 2r-0.5
## (= 23.5 for melee r=12), 不互相重叠。
##
## Setup:
##   - 600x500 map
##   - team 0: 8 melee 起始 (50, 130)..(50, 480) 列状散布 (每 50 px 一行)
##   - team 1: 1 barracks at (590, 50) (远端不挡 path 但占位让 fallback 不立即判败)
##   - player_commands: tick 1 → MoveUnitsCommand([all 8 ids], (450, 250))
##   - 250 ticks (50ms × 250 = 12.5s)
extends RtsScenario


const MIN_PAIR_DIST: float = 23.5  # 2 × melee_collision_radius - 0.5
const TARGET: Vector2 = Vector2(450.0, 250.0)


func get_scene_config() -> Dictionary:
	var units: Array[Dictionary] = []
	for i in 8:
		units.append({
			"class": RtsUnitClassConfig.UnitClass.MELEE,
			"team": 0,
			"pos": Vector2(50.0, 130.0 + float(i) * 50.0),
			"stance": RtsUnitActor.Stance.HOLD_FIRE,
		})
	return {
		"map_size": Vector2(600.0, 500.0),
		"rng_seed": 1002,
		"tick_interval_ms": 50.0,
		"buildings": [
			{"kind": RtsBuildingConfig.KIND_BARRACKS, "team": 1, "pos": Vector2(590.0, 50.0)},
		],
		"units": units,
	}


func get_player_commands() -> Array[Dictionary]:
	var cmds: Array[Dictionary] = []
	cmds.append({
		"tick": 1,
		"kind": "move_units",
		"team_id": 0,
		"unit_selector": {"team": 0, "all": true},
		"target_pos": TARGET,
	})
	return cmds


func get_max_ticks() -> int:
	return 250


func get_name() -> String:
	return "scenario_8_units_no_overlap"


func assert_replay(ctx: RtsScenarioAssertContext) -> void:
	var ids: Array = ctx.get_unit_ids_by_team(0)
	if ids.size() != 8:
		ctx.fail("expected 8 team-0 units, got %d" % ids.size())
		return

	# 全 alive
	for uid in ids:
		var actor := ctx.get_actor(uid as String) as RtsUnitActor
		if actor == null or actor.is_dead():
			ctx.fail("unit %s died (final_hp=%.1f)" % [uid, ctx.final_hp(uid as String)])
			return

	# pairwise min distance ≥ 2r - 0.5
	var min_dist: float = ctx.pairwise_min_distance(ids)
	ctx.assert_ge(min_dist, MIN_PAIR_DIST, "pairwise_min_distance should be >= %.1f" % MIN_PAIR_DIST)
	if ctx.has_failed():
		return

	# formation centroid 距 TARGET ≤ 50 (8 单位方阵 spacing=30 → 几何中心应在 TARGET ±误差)
	var centroid: Vector2 = ctx.formation_centroid(ids)
	var d: float = centroid.distance_to(TARGET)
	ctx.assert_le(d, 50.0, "formation_centroid should be within 50px of target")
