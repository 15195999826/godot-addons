## RTS Harvest Loop smoke (M2.1 Phase C — AC6 主 gate)
##
## 验证 Phase C 经济闭环主链路:
##   1. RtsHarvestActivity + RtsReturnAndDropActivity 两 Activity 串联切换
##   2. RtsHarvestStrategy.decide (carry 总和 ≥ 1 → ReturnAndDrop; 否则找最近 ResourceNode → Harvest; 找不到 → Idle)
##   3. RtsAutoBattleProcedure.add_team_resources (worker 抵达 drop-off 时调) 对称 spend
##   4. RtsBuildingActor.is_drop_off=true (create_crystal_tower 工厂自动设) 让 worker 找 ct 作为 drop-off
##   5. RtsResourceNode.amount 实际被 harvest 消耗
##
## 设计:
##   - 起手 (左 team 0):
##     - 5 worker 在 (160, 200), (160, 230), (160, 260), (160, 290), (160, 320) — y 间隔 30 px
##     - 1 left ct @ (200, 250) hp=2000 (drop-off; create_crystal_tower 自动 is_drop_off=true)
##   - 中立 (team_id=-1):
##     - 1 gold node @ (220, 220) — worker 0,1 距 < 100 px 选此
##     - 1 wood node @ (220, 280) — worker 3,4 距 < 100 px 选此 (worker 2 距两 node 等距, tiebreak by actor_id)
##   - 右 (team 1):
##     - 1 right ct @ (440, 260) hp=2000 — 防右方全灭判负 (worker mask=NONE 不主动打 ct)
##   - 跑 600 tick @ TICK_INTERVAL_MS = 1000/30 ≈ 33.33ms ≈ 20 真实秒 (D13)
##   - 验证 (AC6):
##     - 5 worker 全 alive
##     - team_resources[0]["gold"] >= GOLD_THRESHOLD
##     - team_resources[0]["wood"] >= WOOD_THRESHOLD
##     - 至少 1 worker 经历过完整 cycle (carrying 曾经非空 → 已 drop)
##     - gold/wood node amount 减少 (Phase C 实际消费)
##     - SMOKE_TEST_RESULT: PASS
##
## 决策来源: phase-c-harvest-activity.md §AC6 + §设计决策 D8 (hardcode spawn) /
## D12 (HARVEST_RADIUS / DROP_OFF_RADIUS = 32) / D13 (600 tick + 阈值 ≥100 each)
extends Node


const TICK_INTERVAL_MS: float = 1000.0 / 30.0  # ~33.33ms (D13: @30 Hz fixed-tick)
const RNG_SEED: int = 27182
const MAX_TICKS: int = 600  # ≈ 20s @ 30Hz (D13)

const MAP_WIDTH: float = 600.0
const MAP_HEIGHT: float = 500.0

const NUM_WORKERS: int = 5
const WORKER_SPAWN_BASE: Vector2 = Vector2(160.0, 200.0)
const WORKER_SPAWN_DELTA: Vector2 = Vector2(0.0, 30.0)

const GOLD_NODE_POS: Vector2 = Vector2(220.0, 220.0)
const WOOD_NODE_POS: Vector2 = Vector2(220.0, 280.0)
const LEFT_CT_POS: Vector2 = Vector2(200.0, 250.0)  # drop-off (is_drop_off=true)
const RIGHT_CT_POS: Vector2 = Vector2(440.0, 260.0)  # 防右方全灭

const GOLD_THRESHOLD: int = 100
const WOOD_THRESHOLD: int = 100


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _workers: Array[RtsUnitActor] = []
var _gold_node: RtsResourceNode = null
var _wood_node: RtsResourceNode = null

# 跟踪每 worker 是否曾经 carrying 非空 (HarvestActivity 触发 transfer 后即非空)
var _worker_ever_carried: Array[bool] = []


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

	# 起手 5 worker (左方 team 0)
	var controllers: Dictionary = {}
	for i in range(NUM_WORKERS):
		var pos: Vector2 = WORKER_SPAWN_BASE + WORKER_SPAWN_DELTA * float(i)
		var worker := _spawn_worker(pos, controllers)
		_workers.append(worker)
		_worker_ever_carried.append(false)

	# 中立 ResourceNode (team_id=-1)
	_gold_node = RtsResourceNodes.create_gold_node()
	_gold_node.set_team_id(-1)
	_world.add_actor(_gold_node)
	_gold_node.position_2d = GOLD_NODE_POS

	_wood_node = RtsResourceNodes.create_wood_node()
	_wood_node.set_team_id(-1)
	_world.add_actor(_wood_node)
	_wood_node.position_2d = WOOD_NODE_POS

	# 左 ct (drop-off; create_crystal_tower 工厂自动 is_drop_off=true)
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = LEFT_CT_POS

	# 右 ct (hp=2000 永远不死 — worker atk=0 不主动打, 但 procedure._check_battle_end 走 ct 模式时
	# 右方 ct alive ⇒ 右方不败; 防左方"全灭"判负也走 ct 模式 (左方 ct 也 alive))
	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = RIGHT_CT_POS

	# Team configs (起手 starting_resources={} 让 add_team_resources 从 0 起加)
	var left_cfg := RtsTeamConfig.unconfigured(0)
	var right_cfg := RtsTeamConfig.unconfigured(1)

	# left_team: 5 worker + left ct; right_team: right ct
	var left_actors: Array[RtsBattleActor] = [left_ct]
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
		# 每 tick 探测 worker.carrying 是否曾经非空 (HarvestActivity transfer 触发的 cycle 标志)
		for i in range(_workers.size()):
			if not _worker_ever_carried[i] and not _workers[i].carrying.is_empty():
				_worker_ever_carried[i] = true
		if _procedure.should_end():
			_fail("battle ended unexpectedly at tick %d (双方 ct 不死, harvest 不应触发胜负); result=%s" % [
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
		_fail("expected %d alive workers, got %d (worker should not die in harvest scenario)" % [NUM_WORKERS, alive_workers])
		return

	# AC6.2: team_resources[0]["gold"] / "wood" 双 >= 阈值
	var team_resources: Dictionary = _procedure.get_team_resources(0)
	var team_gold: int = int(team_resources.get("gold", 0))
	var team_wood: int = int(team_resources.get("wood", 0))
	if team_gold < GOLD_THRESHOLD:
		_fail("team 0 gold=%d below threshold %d (worker harvest 链路未完成预期 cycle)" % [team_gold, GOLD_THRESHOLD])
		return
	if team_wood < WOOD_THRESHOLD:
		_fail("team 0 wood=%d below threshold %d (worker harvest 链路未完成预期 cycle)" % [team_wood, WOOD_THRESHOLD])
		return

	# AC6.3: 至少 1 worker 经历过 carrying 非空 (HarvestActivity transfer 触发, 也即 ReturnAndDrop 被走过)
	var cycle_count: int = 0
	for ever_carried in _worker_ever_carried:
		if ever_carried:
			cycle_count += 1
	if cycle_count == 0:
		_fail("no worker ever had carrying non-empty (HarvestActivity 没触发 transfer)")
		return

	# AC6.4: 资源节点 amount 减少 (Phase C 实际消费 — gold + wood 总减 ≥ team_gold + team_wood)
	var total_consumed: int = (_gold_node.max_amount - _gold_node.amount) + (_wood_node.max_amount - _wood_node.amount)
	if total_consumed <= 0:
		_fail("resource node amounts unchanged (gold=%d/%d wood=%d/%d); harvest 没消费" % [
			_gold_node.amount, _gold_node.max_amount,
			_wood_node.amount, _wood_node.max_amount,
		])
		return

	# 报告
	print("rts harvest_loop smoke: ticks=%d alive_workers=%d team_gold=%d team_wood=%d gold_node=%d/%d wood_node=%d/%d cycle_workers=%d" % [
		_procedure.get_current_tick(), alive_workers, team_gold, team_wood,
		_gold_node.amount, _gold_node.max_amount,
		_wood_node.amount, _wood_node.max_amount,
		cycle_count,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - workers harvested gold/wood >= thresholds and dropped to ct")
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
