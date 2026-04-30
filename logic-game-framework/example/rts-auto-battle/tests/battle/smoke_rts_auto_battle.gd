## RTS auto-battle 4v4 acceptance smoke (M0.7 — AC1 / AC2 / AC3 gate)
##
## 期望产出:
##   AC1: SMOKE_TEST_RESULT: PASS - left_win | right_win
##   AC2: 至少有 1 个抽样单位的 path_length_traveled / 起止直线距离 ≥ 1.03 (绕路证据)
##   AC3: melee 单位的所有 attack 距离 ≤ MELEE_RANGE_THRESHOLD × 1.05;
##        ranged 单位至少 1 次 attack 距离 > MELEE_RANGE_THRESHOLD (拉开了距离打)
##
## MAX_TICKS 触发 → SMOKE_TEST_RESULT: FAIL - timeout (不允许平局/死循环)。
##
## 阵容(出生坐标见 RtsBattleMap.sample_team_spawn):
##   左队 (team 0, x≈50): 2 melee + 2 ranged 沿 y=[80, 420] 均分
##   右队 (team 1, x≈450): 同上
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 60.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _logger: RtsBattleLogger = null
var _agents: Dictionary = {}     # actor.id → RtsNavAgent
var _ais: Dictionary = {}        # actor.id → RtsBasicAI
var _spawn_positions: Dictionary = {}  # actor.id → Vector2 (起点, 服务 AC2)


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance

	await get_tree().physics_frame
	_world.set_navigation_region(_battle_map.navigation_region)

	_logger = RtsBattleLogger.new()

	# Spawn 4v4: 左队 [melee, melee, ranged, ranged] @ x≈50; 右队对称 @ x≈450
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	for i in range(roster.size()):
		var left_pos := RtsBattleMap.sample_team_spawn(0, i, roster.size())
		var right_pos := RtsBattleMap.sample_team_spawn(1, i, roster.size())
		left_actors.append(_spawn(roster[i], 0, left_pos))
		right_actors.append(_spawn(roster[i], 1, right_pos))

	_procedure = RtsAutoBattleProcedure.new(_world, left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"per_tick": _per_tick,
	})
	_procedure.start()

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		_procedure.tick_once()
		if i % 4 == 0:
			await get_tree().physics_frame
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== AC1: winner 必为 left_win / right_win =====
	var result := _procedure.get_result()
	if result == "timeout":
		_fail("battle did not converge within %d ticks (MAX_TICKS)" % max_ticks)
		return
	if result != "left_win" and result != "right_win":
		_fail("unexpected procedure result '%s'" % result)
		return

	# ===== AC3: 兵种行为断言 =====
	# Melee: 全部 attack 距离 ≤ MELEE_RANGE_THRESHOLD × 1.05
	var melee_dists := _logger.get_attack_distances_for_class(int(Config.UnitClass.MELEE))
	if melee_dists.is_empty():
		_fail("AC3: no melee attack events recorded")
		return
	var melee_max: float = _max_in(melee_dists)
	if melee_max > Config.MELEE_RANGE_THRESHOLD * 1.05:
		_fail("AC3 violated: melee attack at distance %.2f > %.2f (range×1.05)" % [
			melee_max, Config.MELEE_RANGE_THRESHOLD * 1.05,
		])
		return

	# Ranged: 至少 1 次 attack 距离 > MELEE_RANGE_THRESHOLD
	var ranged_dists := _logger.get_attack_distances_for_class(int(Config.UnitClass.RANGED))
	if ranged_dists.is_empty():
		_fail("AC3: no ranged attack events recorded")
		return
	var any_ranged_long: bool = false
	for d in ranged_dists:
		if d > Config.MELEE_RANGE_THRESHOLD:
			any_ranged_long = true
			break
	if not any_ranged_long:
		_fail("AC3 violated: no ranged attack > MELEE_RANGE_THRESHOLD (%.2f); max ranged dist=%.2f" % [
			Config.MELEE_RANGE_THRESHOLD, _max_in(ranged_dists),
		])
		return

	# ===== AC2: 至少 1 个起点在障碍 y 范围 (200..300) 内的单位 max_y_deviation ≥ 30 =====
	# (单位若直线穿墙, max_y_deviation ≈ 0; 真正绕过障碍 y 必发生 30+ 偏移)
	var detour_evidence := _check_detour_for_blocked_units()
	if detour_evidence.is_empty():
		_fail("AC2 violated: no unit with spawn-y in [200, 300] showed y deviation ≥ 30 (units likely walked through wall)")
		return

	# ===== 报告 =====
	print("rts smoke: result=%s ticks=%d attacks=%d (melee=%d ranged=%d) deaths=%d melee_max_dist=%.2f ranged_max_dist=%.2f detoured=%d" % [
		result,
		_procedure.get_current_tick(),
		_logger.get_attack_count(),
		melee_dists.size(),
		ranged_dists.size(),
		_logger.get_death_count(),
		melee_max,
		_max_in(ranged_dists),
		detour_evidence.size(),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - %s" % result)
	get_tree().quit(0)


func _spawn(unit_class: Config.UnitClass, team_id: int, pos: Vector2) -> RtsCharacterActor:
	var actor := RtsCharacterActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos
	_spawn_positions[actor.get_id()] = pos

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(actor)
	_agents[actor.get_id()] = agent

	var ai := RtsBasicAI.new()
	ai.bind(actor, agent)
	_ais[actor.get_id()] = ai

	return actor


func _per_tick(_proc: RtsAutoBattleProcedure, dt: float) -> void:
	for actor in _world.get_alive_actors():
		if not (actor is RtsCharacterActor):
			continue
		var character := actor as RtsCharacterActor
		var ai := _ais.get(actor.get_id(), null) as RtsBasicAI
		var agent := _agents.get(actor.get_id(), null) as RtsNavAgent

		if ai != null:
			ai.tick(dt, _world)
		if agent != null:
			agent.tick(dt)
		character.tick_attack_cooldown(dt)

		if ai != null and ai.last_decision == "in_range" and character.can_attack():
			var target_id := character.current_target_id
			if target_id != "":
				var target := _world.get_actor(target_id) as RtsCharacterActor
				if target != null and not target.is_dead():
					RtsBasicAttackAction.execute(character, target, _world)
					character.reset_attack_cooldown()

	_logger.ingest_frame_events(GameWorld.event_collector.collect())


## AC2: 找出 spawn-y 在 (200, 300) 障碍水平区内 + max_y_deviation ≥ 30 的单位 id 列表
func _check_detour_for_blocked_units() -> Array[String]:
	var result: Array[String] = []
	for actor_id in _agents.keys():
		var agent := _agents[actor_id] as RtsNavAgent
		if agent == null:
			continue
		var spawn_pos: Vector2 = _spawn_positions.get(actor_id, Vector2.ZERO)
		# 仅检查起点在障碍 y 范围内的单位 (slot 1/2): 这些单位必须绕路才能向 x 方向前进
		if spawn_pos.y < 200.0 or spawn_pos.y > 300.0:
			continue
		if agent.max_y_deviation >= 30.0:
			result.append(actor_id)
	return result


func _max_in(arr: Array[float]) -> float:
	var m: float = -INF
	for v in arr:
		if v > m:
			m = v
	return m if m != -INF else 0.0


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
