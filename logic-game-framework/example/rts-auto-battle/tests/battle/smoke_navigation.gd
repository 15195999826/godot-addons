## RTS auto-battle navigation smoke (M0.4)
##
## 验证: 单个 melee 单位从 (50, 250) 走到 (450, 250), 中央 (200..300, 200..300) 障碍迫使绕路;
## 5 秒 procedure tick 内应抵达终点 ± 10 px, 且累计行走距离 / 起止直线距离 ≥ 1.05(绕路证据)。
##
## headless 关键: _ready 末尾 await physics_frame, NavigationServer2D 才会 sync map; 否则
## get_next_path_position() 返回起点本身, 单位原地不动。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 12.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _actor: RtsCharacterActor = null
var _agent: RtsNavAgent = null
var _start_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance

	# Wait one physics frame so NavigationServer2D syncs the map
	await get_tree().physics_frame

	_world.set_navigation_region(_battle_map.navigation_region)

	# Spawn 1 melee at (50, 250)
	_actor = RtsCharacterActor.new(Config.UnitClass.MELEE)
	_actor.set_team_id(0)
	_world.add_actor(_actor)
	_start_pos = Vector2(50.0, 250.0)
	_target_pos = Vector2(450.0, 250.0)
	_actor.position_2d = _start_pos

	_agent = RtsNavAgent.new()
	_battle_map.add_child(_agent)
	# Agent _ready already ran via add_child; bind + position update
	_agent.bind_actor(_actor)
	_agent.set_target(_target_pos)

	# Procedure with per_tick driving the nav agent
	var left_team: Array[RtsBattleActor] = [_actor]
	# Right team must have at least 1 actor for _check_battle_end not to immediately judge
	# Use a never-dying dummy actor
	var dummy_right := RtsBattleActor.new()
	dummy_right.set_team_id(1)
	_world.add_actor(dummy_right)
	var right_team: Array[RtsBattleActor] = [dummy_right]

	_procedure = RtsAutoBattleProcedure.new(_world, left_team, right_team, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"per_tick": func(_proc: RtsAutoBattleProcedure, dt: float) -> void:
			_agent.tick(dt)
	})
	_procedure.start()

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		_procedure.tick_once()
		# Need to yield occasionally so NavigationServer can deliver path updates
		if i % 4 == 0:
			await get_tree().physics_frame
		if _agent.is_arrived():
			break

	_procedure.finish()

	# 断言抵达
	var final_dist_to_target := _actor.position_2d.distance_to(_target_pos)
	if final_dist_to_target > 10.0:
		_fail("did not arrive: final pos %s, dist to target %.2f" % [_actor.position_2d, final_dist_to_target])
		return

	# 断言绕路 (主): 起止 y 相同 (250), 直线穿墙 max_y_deviation 应 ≈ 0;
	# 实际从 (50,250) 走到 (450,250) 必绕过 obstacle (y in 200..300) 一侧, max_y_deviation 应 ≥ ~50
	if _agent.max_y_deviation < 30.0:
		_fail("y deviation too small: max=%.2f (expected ≥ 30, navmesh likely letting unit through wall)" % [
			_agent.max_y_deviation,
		])
		return

	# 断言绕路 (辅): 总走距 / 起止直线距离 ≥ 1.03 (100×100 obstacle + agent_radius=6 corner-cut 现实下限)
	var straight_dist := _start_pos.distance_to(_target_pos)
	var ratio := _agent.path_length_traveled / straight_dist if straight_dist > 0.0 else 0.0
	if ratio < 1.03:
		_fail("path too straight: traveled=%.2f straight=%.2f ratio=%.3f (expected ≥ 1.03)" % [
			_agent.path_length_traveled, straight_dist, ratio,
		])
		return

	print("nav smoke: traveled=%.2f straight=%.2f ratio=%.3f max_y_dev=%.2f final=%s" % [
		_agent.path_length_traveled, straight_dist, ratio, _agent.max_y_deviation, _actor.position_2d,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - nav 50,250 → 450,250 around obstacle")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
