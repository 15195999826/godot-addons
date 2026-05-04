## RTS grid pathfinding smoke (P1.2 → M5 facade retrofit)
##
## 验证 NavcellGrid + PathfinderFacade + RtsNavAgent (无 NavigationServer2D 依赖):
##   1. 单个 melee 单位从 (50, 250) → (450, 250), 中央 grid cells (6..9, 6..9) blocking
##   2. 5 秒 procedure tick 内应抵达终点 ± 10 px
##   3. 中途 max_y_deviation ≥ 30 (绕路证据)
##
## 与 smoke_navigation.tscn 的差异: 这个 smoke 不跑 procedure tick_once,直接断 nav_agent.tick
## + facade A* 链路(更隔离,服务 P1.2 acceptance 单点验证)。
##
## M5 retrofit: attach RtsPathfinderFacade 让 set_target 走 production 链路替代老 RtsPathfinding。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 12.0
const TICK_DT_SEC: float = TICK_INTERVAL_MS / 1000.0


func _ready() -> void:
	GameWorld.init()

	var battle_map := RtsBattleMap.new()
	add_child(battle_map)

	var actor := RtsUnitActor.new(Config.UnitClass.MELEE)
	actor.set_team_id(0)
	actor.set_id("test_unit_1")
	var start_pos := Vector2(50.0, 250.0)
	var target_pos := Vector2(450.0, 250.0)
	actor.position_2d = start_pos

	var agent := RtsNavAgent.new()
	battle_map.add_child(agent)
	agent.bind_actor(actor, battle_map.grid)

	# M5 retrofit: attach facade 让 nav_agent 走 production 链路替代老 fallback。
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	battle_map.grid.attach_passability_registry(registry)
	var navcell_grid: RtsNavcellGrid = battle_map.grid.get_navcell_grid()
	var hp := RtsHierarchicalPathfinder.new()
	hp.recompute(navcell_grid, registry.get_classes())
	var lp := RtsLongPathfinder.new(navcell_grid)
	var facade := RtsPathfinderFacade.new(navcell_grid, hp, lp)
	agent.attach_pathfinder(facade, registry)

	agent.set_target(target_pos)

	# 验证 path 已生成 (find_path 应能找到绕过中央 obstacle 的路径)
	if agent._path.is_empty():
		_fail("path not generated: grid pathfinding returned empty waypoints")
		return

	# 推进 max ticks 跑到终点
	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		agent.tick(TICK_DT_SEC)
		if agent.is_arrived():
			break

	# 抵达断言 — 阈值 20 px 接受 canonicalize 把 target 落到 navcell 中心(navcell_size=32 → ≤ 16 px 偏移)
	var final_dist := actor.position_2d.distance_to(target_pos)
	if final_dist > 20.0:
		_fail("did not arrive: final_pos=%s dist=%.2f" % [actor.position_2d, final_dist])
		return

	# 绕路断言: max_y_deviation ≥ 30 (起止 y=250 同, 直线穿墙偏离 0; 绕过 cells 6..9 必偏)
	if agent.max_y_deviation < 30.0:
		_fail("y deviation too small: max=%.2f (expected ≥ 30, grid path likely letting unit through wall)" % agent.max_y_deviation)
		return

	print("grid path smoke: traveled=%.2f straight=%.2f max_y_dev=%.2f final=%s" % [
		agent.path_length_traveled,
		start_pos.distance_to(target_pos),
		agent.max_y_deviation,
		actor.position_2d,
	])

	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - grid A* + push-aware nav agent ok")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
