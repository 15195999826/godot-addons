## scenario_dynamic_obstacle_repath (P3.3 寻路验证 4/4)
##
## 验证: harness add_static_obstacle 路径 (绕过 RtsBuildingPlacement.validate) 在 tick 1 与
## MoveUnitsCommand 同时生效, A* 算 path 时已感知 grid blocking, 让 unit 绕过中央 obstacle
## 抵达远端目标。
##
## (注: 真正的"unit 已在路径上后 obstacle 出现 → stuck → repath" 在当前架构无法纯 tick-loop
## 验证 — RtsNavAgent.integrate 不查 grid blocking, unit 会穿过 footprint 继续走旧 path,
## stuck_detector 不会触发. stuck recovery 行为已由 smoke_stuck_recovery 覆盖 — 那里 3 单位
## 被建筑包围, 起跑就动不了, 才能触发 stuck 检测。本 scenario 验证 add_static_obstacle 路径
## 与 grid blocking-aware A* 协作, 是"obstacle 来源不同"的另一种 dynamic 形态。)
##
## Setup:
##   - 600x500 map
##   - team 0: 1 melee at (50, 250) HOLD_FIRE
##   - team 1: 1 barracks at (590, 480) (角落 dummy 占位)
##   - player_commands:
##       - tick 1: MoveUnitsCommand([unit], (550, 250))
##       - tick 1: add_static_obstacle barracks @ (300, 250) (在 player command 之前 inject;
##                 走 harness 直接 add_actor + place_building, 绕过 build_zone 校验 — 验证
##                 这条命令路径 + grid blocking 立即生效让 A* 绕过)
##   - 250 ticks (50ms × 250 = 12.5s)
extends RtsScenario


const START: Vector2 = Vector2(50.0, 250.0)
const TARGET: Vector2 = Vector2(550.0, 250.0)
const OBSTACLE: Vector2 = Vector2(300.0, 250.0)


func get_scene_config() -> Dictionary:
	return {
		"map_size": Vector2(600.0, 500.0),
		"rng_seed": 1004,
		"tick_interval_ms": 50.0,
		"buildings": [
			{"kind": RtsBuildingConfig.KIND_BARRACKS, "team": 1, "pos": Vector2(590.0, 480.0)},
		],
		"units": [
			{
				"class": RtsUnitClassConfig.UnitClass.MELEE,
				"team": 0,
				"pos": START,
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
		"target_pos": TARGET,
	})
	# 在 tick 1 (与 MoveUnitsCommand 同时) inject obstacle: harness 走 add_static_obstacle
	# 路径直接 add_actor + grid.place_building, 绕过 RtsBuildingPlacement.validate 校验 —
	# 这是"obstacle 来源不同 (非玩家 PlaceBuildingCommand)" 的 dynamic 形态验证。
	cmds.append({
		"tick": 1,
		"kind": "add_static_obstacle",
		"team_id": 1,
		"building_kind": RtsBuildingConfig.KIND_BARRACKS,
		"pos": OBSTACLE,
	})
	return cmds


func get_max_ticks() -> int:
	return 250


func get_name() -> String:
	return "scenario_dynamic_obstacle_repath"


func assert_replay(ctx: RtsScenarioAssertContext) -> void:
	var unit: RtsUnitActor = ctx.get_unit_by_index(0, 0)
	if unit == null:
		ctx.fail("unit not found at team 0 index 0")
		return
	var uid: String = unit.get_id()

	if unit.is_dead():
		ctx.fail("unit died unexpectedly")
		return

	# 单位最终抵达 (放宽到 80 — 动态障碍 + stuck 等待让抵达精度比静态差一点)
	ctx.assert_within(uid, TARGET, 80.0, "unit should arrive within 80px of target after detour")
	if ctx.has_failed():
		return

	# 走过的总路径明显长于直线 — 说明绕过了新障碍
	var ratio: float = ctx.detour_ratio(uid, TARGET)
	ctx.assert_ge(ratio, 1.05,
		"detour_ratio should be >= 1.05 (path re-routed around dynamic obstacle)")
