## RTS Resource Nodes smoke (M2.1 Phase B → Phase C 重定位)
##
## **Phase C 重定位**: 主旨从"worker mask=NONE 让 basic_attack idle"改为"worker 走 RtsHarvestStrategy
## fallback to IdleActivity (找不到 ResourceNode 时)" — 同样验 worker max_drift=0, 但通过策略
## 不同分支。原 Phase B 主张 worker 永远 idle 在 Phase C 后不再成立 (worker 见到 node 就采集)。
##
## 验证目标 (Phase C 后):
##   1. RtsHarvestStrategy 找不到 ResourceNode → 返 IdleActivity (AC4 fallback 分支)
##   2. UnitClass.WORKER 起手 + factory get_strategy(WORKER) 链路无 SCRIPT ERROR
##   3. RtsResourceNode actor 类型仍可 instantiate (AC1-3 注册不退化) — 通过 import 而非 smoke 跑覆盖
##
## 设计 (Phase C 后):
##   - 起手:
##     - 5 worker (左方 team 0, spawn 在 (100, 200) 附近, 间隔 30 px)
##     - 右方 1 crystal_tower (hp=2000 永远不死) — 让 _check_battle_end ct 模式右方不败,
##       左方 fallback 全灭 worker alive 不败 → 战斗持续 200 tick (10 真实秒)
##     - **不放** ResourceNode — RtsHarvestStrategy 的 _find_closest_resource_node 返空 → IdleActivity
##   - 跑 200 tick @ 50ms = 10 真实秒
##   - 验证: worker 5 alive, max_drift ≤ 50 px, 无 SCRIPT ERROR
##
## smoke_harvest_loop (Phase C C.7) 覆盖 worker + ResourceNode + harvest cycle 主链路。
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

const RIGHT_CT_POS: Vector2 = Vector2(450.0, 250.0)


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _worker_spawn_positions: Array[Vector2] = []
var _workers: Array[RtsUnitActor] = []


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

	# 右方 1 ct (hp=2000 永远不死) — 让 _check_battle_end ct 模式右方不败 (procedure.start
	# 自动绑 right cfg.crystal_tower_id); 左方 fallback 全灭 worker alive 不败
	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = RIGHT_CT_POS

	# Team configs: 默认 unconfigured (双方都没起手 starting_resources, build_zone 空)
	var left_cfg := RtsTeamConfig.unconfigured(0)
	var right_cfg := RtsTeamConfig.unconfigured(1)

	# left_team 含 5 worker; right_team 含 ct
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
	# 1. 5 worker 全部 alive
	var alive_workers: int = 0
	for w in _workers:
		if not w.is_dead():
			alive_workers += 1
	if alive_workers != NUM_WORKERS:
		_fail("expected %d alive workers, got %d" % [NUM_WORKERS, alive_workers])
		return

	# 2. worker 距 spawn ≤ SPAWN_DRIFT_TOLERANCE (HarvestStrategy 找不到 node → IdleActivity → 不主动远离)
	var max_drift: float = 0.0
	for i in range(_workers.size()):
		var w := _workers[i]
		var spawn_pos := _worker_spawn_positions[i]
		var drift: float = w.position_2d.distance_to(spawn_pos)
		if drift > max_drift:
			max_drift = drift
		if drift > SPAWN_DRIFT_TOLERANCE:
			_fail("worker %d drifted %.2f px from spawn (limit %.2f); HarvestStrategy 应在找不到 node 时返 IdleActivity" % [
				i, drift, SPAWN_DRIFT_TOLERANCE,
			])
			return

	# 3. worker carrying 始终空 (没找到 ResourceNode → 不会切到 ReturnAndDrop, 也不会有 carrying)
	for i in range(_workers.size()):
		var w := _workers[i]
		if not w.carrying.is_empty():
			_fail("worker %d unexpectedly has carrying=%s (找不到 node 不应有 carrying)" % [i, str(w.carrying)])
			return

	# 报告
	print("rts resource_nodes smoke: ticks=%d alive_workers=%d max_drift=%.2f" % [
		_procedure.get_current_tick(), alive_workers, max_drift,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 5 workers idle near spawn (HarvestStrategy fallback to IdleActivity 找不到 node)")
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_worker(pos: Vector2, controllers: Dictionary) -> RtsUnitActor:
	var worker := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.WORKER)
	worker.set_team_id(0)
	_world.add_actor(worker)
	worker.position_2d = pos

	var motion_component := RtsMotionComponent.attach_default(worker, _world)

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(worker.unit_class)
	var controller := RtsUnitController.new(worker, motion_component, strategy)
	controllers[worker.get_id()] = controller

	return worker


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
