## scenario_formation_preserved (P3.3 寻路验证 3/4)
##
## 验证: 4 单位长距移动后 formation 保形 — 抵达后单位围绕 centroid 平均偏移在阈值内
## (formation_offset_avg ≤ 50; spacing=30 方阵理论平均偏移 ~21).
##
## Setup:
##   - 600x500 map
##   - team 0: 4 melee 起始紧密 (50, 240) (50, 250) (50, 260) (50, 270)
##   - team 1: 1 barracks at (590, 480) (角落 dummy)
##   - player_commands: tick 1 → MoveUnitsCommand([all 4 ids], (500, 250))
##   - 200 ticks (50ms × 200 = 10s)
extends RtsScenario


const TARGET: Vector2 = Vector2(500.0, 250.0)
const MAX_OFFSET_AVG: float = 50.0  # 4-unit 2x2 formation spacing 30 → avg offset to centroid ≈ 21


func get_scene_config() -> Dictionary:
	var units: Array[Dictionary] = []
	for i in 4:
		units.append({
			"class": RtsUnitClassConfig.UnitClass.MELEE,
			"team": 0,
			"pos": Vector2(50.0, 240.0 + float(i) * 10.0),
			"stance": RtsUnitActor.Stance.HOLD_FIRE,
		})
	return {
		"map_size": Vector2(600.0, 500.0),
		"rng_seed": 1003,
		"tick_interval_ms": 50.0,
		"buildings": [
			{"kind": RtsBuildingConfig.KIND_BARRACKS, "team": 1, "pos": Vector2(590.0, 480.0)},
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
	return 200


func get_name() -> String:
	return "scenario_formation_preserved"


func assert_replay(ctx: RtsScenarioAssertContext) -> void:
	var ids: Array = ctx.get_unit_ids_by_team(0)
	if ids.size() != 4:
		ctx.fail("expected 4 team-0 units, got %d" % ids.size())
		return

	# 全 alive
	for uid in ids:
		var actor := ctx.get_actor(uid as String) as RtsUnitActor
		if actor == null or actor.is_dead():
			ctx.fail("unit %s died" % uid)
			return

	# formation_offset_avg 保形
	var offset_avg: float = ctx.formation_offset_avg(ids)
	ctx.assert_le(offset_avg, MAX_OFFSET_AVG,
		"formation_offset_avg should be <= %.1f (formation tight)" % MAX_OFFSET_AVG)
	if ctx.has_failed():
		return

	# 4 unit 都距 target ≤ 60 px
	for uid in ids:
		ctx.assert_within(uid as String, TARGET, 60.0,
			"unit %s should arrive within 60px of target" % uid)
