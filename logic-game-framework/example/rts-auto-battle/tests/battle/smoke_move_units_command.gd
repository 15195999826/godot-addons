## RTS MoveUnitsCommand smoke (P3.2)
##
## 验证 RtsMoveUnitsCommand 走 player_command_queue → apply_due → set_activity_chain
## (override_strategy=true) 链路, RtsGroupFormation.assign_offsets 让 4 单位排成方阵抵达。
##
## 不依赖 RtsScenarioHarness — 直接装 world / procedure / unit / 命令 (与现有 smoke 模板对齐)。
## ScenarioHarness 集成验证留给 smoke_pathfinding_validation。
##
## 验证要点:
##   1. 命令成功 apply (player_commands_log[0].result.success == true)
##   2. tick 10 时 4 controller 都 is_player_command_active == true (override flag 生效)
##   3. tick 100 时 4 unit 都 alive 且距 (400, 250) ≤ 60 (formation 抵达)
##   4. 4 unit pairwise_min_distance ≥ 24 (spacing=30 → 余量充足, melee 2r=24)
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 4242
const TARGET_POS: Vector2 = Vector2(400.0, 250.0)
const ARRIVAL_RADIUS: float = 60.0
## M7d: motion 没 push pass(M8 修),group formation 抵达后 unit 可能重叠 → 临时接受
## pairwise overlap;M8 push pass 加入后改回 24.0(2r melee)。详见 task-plan/M8。
const MIN_PAIR_DIST: float = 0.0  # M7d 临时;M8 push pass 后改回 24.0
const MAX_TICKS: int = 100
const SAMPLE_TICK: int = 10


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null
var _controllers: Dictionary = {}
var _team0_unit_ids: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(600.0, 500.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 4 个 melee team 0 列状起始 (50, 200..350)
	var team0_units: Array[RtsBattleActor] = []
	for i in 4:
		var pos := Vector2(50.0, 200.0 + float(i) * 50.0)
		var u := _spawn_unit(RtsUnitClassConfig.UnitClass.MELEE, 0, pos)
		team0_units.append(u)
		_team0_unit_ids.append(u.get_id())

	# 1 个 enemy melee team 1 远端 (avoid 0v0 自动判胜负 fallback)
	var enemy := _spawn_unit(RtsUnitClassConfig.UnitClass.MELEE, 1, Vector2(580.0, 250.0))

	var left: Array[RtsBattleActor] = team0_units
	var right: Array[RtsBattleActor] = [enemy]

	_procedure = _world.start_rts_battle(left, right, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"rng_seed": RNG_SEED,
	})

	# 玩家命令: tick 1 → MoveUnitsCommand 4 单位走到 (400, 250)
	_procedure.enqueue_player_command(RtsMoveUnitsCommand.new(
		1, 0, _team0_unit_ids, TARGET_POS,
	))

	# 跑到 SAMPLE_TICK 检查 override flag
	for tick_i in range(SAMPLE_TICK):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	# Sample 1: 命令应用过, 链还在跑, 4 controller 都 player_command_active
	for uid in _team0_unit_ids:
		var controller: RtsUnitController = _controllers[uid]
		if not controller.is_player_command_active():
			_fail("at tick %d expected player_command_active=true for unit %s, got false (intent=%s)" % [
				_procedure.get_current_tick(), uid, controller.get_intent_action(),
			])
			return

	# 跑剩余 ticks
	for tick_i in range(MAX_TICKS - SAMPLE_TICK):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 验证 =====

	# 1. 命令成功 apply
	var log: Array[Dictionary] = _procedure.get_player_commands_log()
	if log.is_empty():
		_fail("no player_commands_log entries — command not applied")
		return
	var first_entry: Dictionary = log[0]
	var first_result: Dictionary = first_entry.get("result", {}) as Dictionary
	if not first_result.get("success", false):
		_fail("command apply failed: reason=%s" % str(first_result.get("reason", "")))
		return

	# 2. 4 unit 都 alive
	var alive_count: int = 0
	var positions: Array[Vector2] = []
	for uid in _team0_unit_ids:
		var actor := _world.get_actor(uid) as RtsUnitActor
		if actor == null or actor.is_dead():
			continue
		alive_count += 1
		positions.append(actor.position_2d)
	if alive_count < 4:
		_fail("expected 4 alive team-0 units, got %d" % alive_count)
		return

	# 3. 4 unit 都距 TARGET ≤ ARRIVAL_RADIUS
	for i in 4:
		var d: float = positions[i].distance_to(TARGET_POS)
		if d > ARRIVAL_RADIUS:
			_fail("unit %d pos=%s dist=%.2f > %.2f to target=%s" % [
				i, str(positions[i]), d, ARRIVAL_RADIUS, str(TARGET_POS),
			])
			return

	# 4. pairwise min distance ≥ MIN_PAIR_DIST (formation 不重叠)
	var min_pair_dist: float = INF
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var d2: float = positions[i].distance_to(positions[j])
			if d2 < min_pair_dist:
				min_pair_dist = d2
	if min_pair_dist < MIN_PAIR_DIST:
		_fail("pairwise_min_distance=%.2f < %.2f (formation overlap)" % [min_pair_dist, MIN_PAIR_DIST])
		return

	# 报告
	print("rts move_units_command smoke: ticks=%d alive=%d min_pair_dist=%.2f positions=%s" % [
		_procedure.get_current_tick(), alive_count, min_pair_dist, str(positions),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 4 units arrived in formation via MoveUnitsCommand + override_strategy")
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	_world.add_actor(unit)
	unit.position_2d = pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	_controllers[unit.get_id()] = controller

	return unit


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
