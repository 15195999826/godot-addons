## RTS Resource Nodes smoke (M2.1 Phase B — AC6 gate)
##
## 验证 Phase B 6 个 acceptance 项的端到端联动:
##   1. RtsResourceNodeConfig + RtsResourceNode actor + RtsResourceNodes 工厂能正常实例化 (AC1-3)
##   2. UnitClass.WORKER 起手 idle (target_layer_mask=NONE → AutoTargetSystem mover skip,
##      _cached_target_id 永远空, basic_attack.decide 返 IdleActivity) (AC4-5)
##   3. ResourceNode amount 起手 = max_amount, Phase B 不会减 (Phase C HarvestActivity 才消费)
##
## 设计:
##   - 起手:
##     - 5 worker (左方 team 0, spawn 在 (100, 200) 附近, 间隔 30 px)
##     - 1 gold node + 1 wood node (中立 team_id=-1, 在中央但远离 worker spawn)
##     - 右方 1 crystal_tower (hp=2000 永远不死) — 让 _check_battle_end 走 ct 模式右方不败,
##       左方 fallback 全灭模式 worker alive 不败 → 战斗持续 200 tick (10 真实秒)
##   - 跑 200 tick @ 50ms = 10 真实秒
##   - 验证: worker 5 alive, 距 spawn ≤ 50 px, gold/wood amount = 1500, 无 SCRIPT ERROR
##
## 与 Phase A 既有 6 smoke + replay 双 smoke 的 regression gate 由 phase-b §Validation 顺序覆盖,
## 此 smoke 仅做 Phase B 新能力的最小可行验证。
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 31337
const MAX_TICKS: int = 200  # 10s @ 50ms

const MAP_WIDTH: float = 500.0
const MAP_HEIGHT: float = 500.0

const NUM_WORKERS: int = 5
const WORKER_SPAWN_BASE: Vector2 = Vector2(100.0, 200.0)
const WORKER_SPAWN_DELTA: Vector2 = Vector2(0.0, 30.0)
const SPAWN_DRIFT_TOLERANCE: float = 50.0  # idle 容许 group_formation 推开微移

const GOLD_NODE_POS: Vector2 = Vector2(250.0, 200.0)
const WOOD_NODE_POS: Vector2 = Vector2(250.0, 300.0)
const RIGHT_CT_POS: Vector2 = Vector2(450.0, 250.0)


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _worker_spawn_positions: Array[Vector2] = []
var _workers: Array[RtsUnitActor] = []
var _gold_node: RtsResourceNode = null
var _wood_node: RtsResourceNode = null


func _ready() -> void:
	GameWorld.init()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(MAP_WIDTH, MAP_HEIGHT), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 起手 5 个 worker (左方 team 0)
	var controllers: Dictionary = {}
	for i in range(NUM_WORKERS):
		var pos: Vector2 = WORKER_SPAWN_BASE + WORKER_SPAWN_DELTA * float(i)
		var worker := _spawn_worker(pos, controllers)
		_workers.append(worker)
		_worker_spawn_positions.append(worker.position_2d)

	# 起手 1 gold node + 1 wood node (中立 team_id=-1)
	_gold_node = RtsResourceNodes.create_gold_node()
	_gold_node.set_team_id(-1)
	_world.add_actor(_gold_node)
	_gold_node.position_2d = GOLD_NODE_POS

	_wood_node = RtsResourceNodes.create_wood_node()
	_wood_node.set_team_id(-1)
	_world.add_actor(_wood_node)
	_wood_node.position_2d = WOOD_NODE_POS

	# 右方 1 ct (hp=2000 永远不死) — 让 _check_battle_end ct 模式右方不败 (procedure.start
	# 自动绑 right cfg.crystal_tower_id); 左方 fallback 全灭 worker alive 不败
	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = RIGHT_CT_POS

	# Team configs: 默认 unconfigured (双方都没起手 starting_resources, build_zone 空)
	var left_cfg := RtsTeamConfig.unconfigured(0)
	var right_cfg := RtsTeamConfig.unconfigured(1)

	# left_team 含 5 worker; right_team 含 ct (ResourceNode 中立, 不入任一方)
	var left_actors: Array[RtsBattleActor] = []
	for w in _workers:
		left_actors.append(w)
	var right_actors: Array[RtsBattleActor] = [right_ct]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": controllers,
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
	})

	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		if _procedure.should_end():
			_fail("battle ended unexpectedly at tick %d (worker idle + ct alive should keep both teams alive); result=%s" % [
				_procedure.get_current_tick(), _procedure.get_result(),
			])
			return

	_procedure.finish()

	# ===== 验证 =====
	# AC6.1: 5 worker 全部 alive
	var alive_workers: int = 0
	for w in _workers:
		if not w.is_dead():
			alive_workers += 1
	if alive_workers != NUM_WORKERS:
		_fail("expected %d alive workers, got %d" % [NUM_WORKERS, alive_workers])
		return

	# AC6.2: worker 距 spawn ≤ SPAWN_DRIFT_TOLERANCE (idle 不主动远离)
	var max_drift: float = 0.0
	for i in range(_workers.size()):
		var w := _workers[i]
		var spawn_pos := _worker_spawn_positions[i]
		var drift: float = w.position_2d.distance_to(spawn_pos)
		if drift > max_drift:
			max_drift = drift
		if drift > SPAWN_DRIFT_TOLERANCE:
			_fail("worker %d drifted %.2f px from spawn (limit %.2f); strategy may have side-effect" % [
				i, drift, SPAWN_DRIFT_TOLERANCE,
			])
			return

	# AC6.3: worker 起手没 cached_target_id (mask=NONE 让 AutoTargetSystem 永不写)
	for i in range(_workers.size()):
		var w := _workers[i]
		if not w._cached_target_id.is_empty():
			_fail("worker %d unexpectedly has cached_target_id=%s (mask=NONE 不应被 AutoTargetSystem 选中)" % [
				i, w._cached_target_id,
			])
			return

	# AC6.4: gold node amount 不变
	if _gold_node.amount != _gold_node.max_amount:
		_fail("gold node amount changed (Phase B 不应消减): %d / %d" % [_gold_node.amount, _gold_node.max_amount])
		return
	if _gold_node.is_dead() or _gold_node.is_depleted():
		_fail("gold node unexpectedly dead/depleted")
		return

	# AC6.5: wood node amount 不变
	if _wood_node.amount != _wood_node.max_amount:
		_fail("wood node amount changed (Phase B 不应消减): %d / %d" % [_wood_node.amount, _wood_node.max_amount])
		return
	if _wood_node.is_dead() or _wood_node.is_depleted():
		_fail("wood node unexpectedly dead/depleted")
		return

	# 报告
	print("rts resource_nodes smoke: ticks=%d alive_workers=%d gold_amount=%d wood_amount=%d max_drift=%.2f" % [
		_procedure.get_current_tick(), alive_workers, _gold_node.amount, _wood_node.amount, max_drift,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 5 workers idle near spawn + gold/wood nodes intact at max_amount")
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_worker(pos: Vector2, controllers: Dictionary) -> RtsUnitActor:
	var worker := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.WORKER)
	worker.set_team_id(0)
	_world.add_actor(worker)
	worker.position_2d = pos

	var agent := RtsNavAgent.new()
	_host.add_child(agent)
	agent.bind_actor(worker, _grid)

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(worker.unit_class)
	var controller := RtsUnitController.new(worker, agent, strategy)
	controllers[worker.get_id()] = controller

	return worker


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
