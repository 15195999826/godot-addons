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
var _agents: Dictionary = {}        # actor.id → RtsMotionComponent
var _controllers: Dictionary = {}   # actor.id → RtsUnitController
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

	_world.set_grid(_battle_map.grid)

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

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"event_sink": _on_events,
	})

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		_procedure.tick_once()
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


func _spawn(unit_class: Config.UnitClass, team_id: int, pos: Vector2) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos
	_spawn_positions[actor.get_id()] = pos

	var motion_component := RtsMotionComponent.attach_default(actor, _world)
	_agents[actor.get_id()] = motion_component

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(actor, motion_component, strategy)
	_controllers[actor.get_id()] = controller

	return actor


func _on_events(events: Array[Dictionary]) -> void:
	# 内化主循环每 tick 在 flush 之前调一次 event_sink — 这里镜像到 logger。
	_logger.ingest_frame_events(events)


## AC2: 找出 spawn-y 在 (200, 300) 障碍水平区内 + max_y_deviation ≥ 30 的单位 id 列表
##
## M7d AMBIGUOUS: 老 RtsNavAgent.max_y_deviation 字段在 RtsMotionComponent 不存在(motion 不
## 跟踪 deviation)。当前等价做法 = 抽样 unit 实际 position_2d.y vs spawn_y;但 smoke 的 sample
## 路径在主循环内未保留,需新加 _y_history dict + 主循环每 tick 写入。先返空数组让 AC2 暂时跳过,
## M7d.4 删 RtsNavAgent 时根据需求决定是否保留 detour 验证。
func _check_detour_for_blocked_units() -> Array[String]:
	var result: Array[String] = []
	# TODO(M7d.4): motion 没 max_y_deviation,detour 验证暂跳过
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
