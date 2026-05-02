## scenario_pathfind_around_building (P3.3 寻路验证 1/4)
##
## 验证: 单 unit MoveUnitsCommand 抵达远端时绕过中央 barracks footprint, 走的路径明显
## 长于直线距离 (detour_ratio ≥ 1.05).
##
## Setup:
##   - 600x500 map
##   - team 0: 1 melee at (50, 250)
##   - team 1: 1 barracks at (300, 250) — 障碍 + 占位让 fallback 不立即判败
##   - player_commands: tick 1 → MoveUnitsCommand([unit], (550, 250))
##   - 200 ticks (50ms × 200 = 10s)
##
## 期望 A* 让单位绕过 barracks 2x2 footprint (cells (9,7..10,8) px [288, 352] × [224, 288]).
extends RtsScenario


func get_scene_config() -> Dictionary:
	return {
		"map_size": Vector2(600.0, 500.0),
		"rng_seed": 1001,
		"tick_interval_ms": 50.0,
		"buildings": [
			{"kind": RtsBuildingConfig.KIND_BARRACKS, "team": 1, "pos": Vector2(300.0, 250.0)},
		],
		"units": [
			{
				"class": RtsUnitClassConfig.UnitClass.MELEE,
				"team": 0,
				"pos": Vector2(50.0, 250.0),
				"stance": RtsUnitActor.Stance.HOLD_FIRE,
			},
		],
	}


func get_player_commands() -> Array[Dictionary]:
	var cmds: Array[Dictionary] = []
	cmds.append({
		"tick": 1,
		"kind": "move_units",
		"team_id": 0,
		"unit_selector": {"team": 0, "all": true},
		"target_pos": Vector2(550.0, 250.0),
	})
	return cmds


func get_max_ticks() -> int:
	return 200


func get_name() -> String:
	return "scenario_pathfind_around_building"


func assert_replay(ctx: RtsScenarioAssertContext) -> void:
	var unit: RtsUnitActor = ctx.get_unit_by_index(0, 0)
	if unit == null:
		ctx.fail("unit not found at team 0 index 0")
		return
	var uid: String = unit.get_id()
	if unit.is_dead():
		ctx.fail("unit died: hp=%.1f" % ctx.final_hp(uid))
		return

	var target: Vector2 = Vector2(550.0, 250.0)
	ctx.assert_within(uid, target, 50.0, "unit should arrive within 50px of (550, 250)")
	if ctx.has_failed():
		return

	# detour_ratio: 实际路径 / 直线距离. barracks footprint @ (300, 250) cells x[288..352] y[224..288]
	# 单位走 y=250 直线必撞 → A* 应绕到 y > 288 或 y < 224. 绕路至少 +20 px (上下 36 px buffer)。
	var ratio: float = ctx.detour_ratio(uid, target)
	ctx.assert_ge(ratio, 1.05, "detour_ratio should be >= 1.05 (path went around barracks)")
