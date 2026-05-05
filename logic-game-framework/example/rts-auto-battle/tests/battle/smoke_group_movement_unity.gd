## RTS M8.4 group movement unity acceptance smoke (M8 spec §M8.4 #2)
##
## 验证 10 unit team A 同时下命令到同一目标后,5s 内全部到达 + 队形不散。
##
## **AC5 子项**(spec §M8.4):
##   - AC5.1: 10 unit team A 全部 alive 抵达 goal_radius 内(每 unit 距 goal ≤ 100 px)
##   - AC5.2: 队形紧凑 — 终态 unit 位置标准差(从 centroid 测) ≤ 50 px
##   - AC5.3: 同 control_group(同 team_id)互相不绕(M8.1 已确认 group filter 在 ShortPath 生效;
##           本 smoke 不显式断言 short_path 长度,仅作为 smoke 通过反向证明 — 否则到达时间 + 队形会差)
##
## Setup:
##   - map 800×800,team 0 spawn (100, 100..100+9*30) 列状散布(spacing 30 = 不重叠起步)
##   - team 1 enemy barracks (790, 50) 远端不挡 path 不参战
##   - tick 1 → MoveUnitsCommand → goal (700, 400)
##   - 跑 100 tick (5s @ 50ms)
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 7070
const GOAL: Vector2 = Vector2(700.0, 400.0)
const SPAWN_X: float = 100.0
const SPAWN_Y_BASE: float = 100.0
const SPAWN_Y_SPACING: float = 30.0
const UNIT_COUNT: int = 10
const MAX_TICKS: int = 200  # 10s @ 50ms tick(spawn → goal ≈ 600 px,melee 80 px/s 需 7.5s+;给 10s 收敛余量)

const ARRIVAL_RADIUS: float = 100.0  # AC5.1 阈值:每 unit 距 goal ≤ 100 px
const MAX_FORMATION_STDDEV: float = 50.0  # AC5.2 阈值:终态 stddev ≤ 50 px


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null
var _controllers: Dictionary = {}
var _unit_ids: Array[String] = []


func _ready() -> void:
	GameWorld.init()
	IdGenerator.reset_id_counter()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(800.0, 800.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)
	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 10 melee team 0 列状(spacing 30 起步不重叠)
	var team0_units: Array[RtsBattleActor] = []
	for i in range(UNIT_COUNT):
		var pos := Vector2(SPAWN_X, SPAWN_Y_BASE + float(i) * SPAWN_Y_SPACING)
		var u := _spawn_unit(RtsUnitClassConfig.UnitClass.MELEE, 0, pos)
		team0_units.append(u)
		_unit_ids.append(u.get_id())

	# 1 enemy barracks team 1 远端不挡 path
	var enemy_b := RtsBuildings.create_barracks()
	enemy_b.set_team_id(1)
	_world.add_actor(enemy_b)
	enemy_b.position_2d = Vector2(790.0, 50.0)
	enemy_b.sync_obstruction_shape()

	var left: Array[RtsBattleActor] = team0_units
	var right: Array[RtsBattleActor] = [enemy_b]

	_procedure = _world.start_rts_battle(left, right, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"rng_seed": RNG_SEED,
	})

	# tick 1 → MoveUnitsCommand 10 unit 走到 GOAL
	_procedure.enqueue_player_command(RtsMoveUnitsCommand.new(
		1, 0, _unit_ids.duplicate(), GOAL,
	))

	# 跑 MAX_TICKS
	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	# AC5.1: 10 unit 全 alive + 距 goal ≤ ARRIVAL_RADIUS
	var max_dist_to_goal: float = 0.0
	var alive_count: int = 0
	for uid in _unit_ids:
		var u: RtsUnitActor = _world.get_actor(uid) as RtsUnitActor
		if u == null or u.is_dead():
			continue
		alive_count += 1
		var d: float = u.position_2d.distance_to(GOAL)
		if d > max_dist_to_goal:
			max_dist_to_goal = d

	if alive_count != UNIT_COUNT:
		_fail("AC5.1: alive_count %d != %d after %d ticks" % [alive_count, UNIT_COUNT, MAX_TICKS])
		return
	if max_dist_to_goal > ARRIVAL_RADIUS:
		_fail("AC5.1: max_dist_to_goal %.2f > %.1f after %d ticks (5 unit not arriving)" % [max_dist_to_goal, ARRIVAL_RADIUS, MAX_TICKS])
		return

	# AC5.2: 队形 stddev ≤ 50 px(从 centroid 测距,unit 不散开过远)
	var centroid: Vector2 = Vector2.ZERO
	for uid in _unit_ids:
		var u: RtsUnitActor = _world.get_actor(uid) as RtsUnitActor
		centroid += u.position_2d
	centroid /= float(UNIT_COUNT)
	var sum_sq_dist: float = 0.0
	for uid in _unit_ids:
		var u: RtsUnitActor = _world.get_actor(uid) as RtsUnitActor
		var d: float = u.position_2d.distance_to(centroid)
		sum_sq_dist += d * d
	var stddev: float = sqrt(sum_sq_dist / float(UNIT_COUNT))
	if stddev > MAX_FORMATION_STDDEV:
		_fail("AC5.2: formation stddev %.2f > %.1f (unit 散开过远)" % [stddev, MAX_FORMATION_STDDEV])
		return

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - smoke_group_movement_unity — 10/10 alive, max_dist_to_goal=%.1f ≤%.1f, stddev=%.1f ≤%.1f" % [
		max_dist_to_goal, ARRIVAL_RADIUS, stddev, MAX_FORMATION_STDDEV,
	])
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var u := RtsUnitActor.new(unit_class)
	u.set_team_id(team_id)
	_world.add_actor(u)
	u.position_2d = pos
	u.stance = RtsUnitActor.Stance.HOLD_FIRE  # 不主动开火 → 只走移动 path

	var motion_component := RtsMotionComponent.attach_default(u, _world)

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(u, motion_component, strategy)
	_controllers[u.get_id()] = controller
	return u


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	if _world != null:
		_world.end()
	GameWorld.destroy()
	get_tree().quit(1)
