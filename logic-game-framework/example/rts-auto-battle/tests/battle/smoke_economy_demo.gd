## RTS Economy Demo smoke (M2.1 Phase D — AC3 主 gate)
##
## 验证 Phase D 经济闭环对外可观主链路 — full cycle:
##   1. 起手 starting {gold: 0, wood: 0}, 5 worker harvest 攒 cost
##   2. 资源到 barracks cost (80g + 50w) 后, smoke 自动 enqueue PlaceBuildingCommand barracks
##   3. PlaceBuildingCommand 应用扣资源 + barracks 出现在 left_team
##   4. barracks production_system 累 progress 满周期 spawn melee
##   5. melee 用 override_strategy=true 朝右方 ct 进军, 至少 1 次接战 → ATTACK_RESOLVED_EVENT
##
## 与 smoke_harvest_loop 的差异:
##   - smoke_harvest_loop: 仅 harvest cycle (worker → node → ct), 不 spawn building, 不 spawn melee
##   - 本 smoke: harvest → 自动 enqueue placement → barracks → melee → 攻 ct (full cycle 经济闭环)
##
## 与 smoke_player_command_production 的差异:
##   - smoke_player_command_production: 起手 starting {gold: 100, wood: 100} 直接 tick 30 enqueue 命令
##   - 本 smoke: 起手 0/0, 必须 worker harvest 攒到 cost 后 smoke 才 enqueue (验证 harvest 链路真在工作)
##
## 设计:
##   - 起手 (左 team 0):
##     - 5 worker @ (160, 200), (160, 230), (160, 260), (160, 290), (160, 320) y 间隔 30
##     - 1 left ct @ (200, 250) hp=2000 (drop-off + 防左方判负)
##   - 中立 (team_id=-1) — 1 gold + 1 wood node, 与 smoke_harvest_loop 同模式 (worker 按距离自然分流):
##     - 1 gold node @ (220, 220) — worker 0,1 距更近优先选
##     - 1 wood node @ (220, 290) — worker 3,4 距更近优先选; worker 2 (y=260) 距两 node 等距 by actor_id tiebreak
##   - 右 team 1:
##     - 1 right ct @ (440, 250) hp=2000 (防右方判负)
##   - left build_zone: Rect2(50, 50, 350, 400) (能放 barracks @ (300, 250))
##   - left starting {gold: 0, wood: 0}; right starting {} (不参与放置)
##   - 30Hz fixed tick + 900 tick MAX (D18: ≈ 30 真实秒, 覆盖 harvest cycle + barracks spawn + melee march + attack)
##   - 主循环每 tick check left resources; 满 80g + 50w 且未 enqueue 时 enqueue PlaceBuildingCommand barracks @ (300, 250)
##   - barracks spawner 用 RtsAttackMoveActivity(right_ct.pos, override=true) 让 melee 不被 IdleActivity 替换
##   - event_sink 收集 ATTACK_RESOLVED_EVENT 用于 melee → right_ct 攻击次数验证
##
## node 数量与 D17 草案 "2 gold + 2 wood" 简化为 "1 gold + 1 wood": 经实测 2+2 同侧布局会让 5 worker 全选 gold
## (距离 tiebreak 偏向先注册 node), wood 攒不到; 1+1 模式 (smoke_harvest_loop 同) 是已知能 mix 的最简配置。
##
## 决策来源: phase-d-cost-rebalance.md AC3 + D17 (cost {80,50}/(60,100)/{}, starting {100,100}) +
## D18 (900 tick @ 30Hz timeout 45000ms)
extends Node


const TICK_INTERVAL_MS: float = 1000.0 / 30.0  # ~33.33ms (30Hz fixed-tick, 与 smoke_harvest_loop 一致)
const RNG_SEED: int = 31415
const MAX_TICKS: int = 900  # D18: 30s @ 30Hz (覆盖 harvest cycle + barracks spawn + melee march + attack)

const MAP_WIDTH: float = 600.0
const MAP_HEIGHT: float = 500.0

const NUM_WORKERS: int = 5
const WORKER_SPAWN_BASE: Vector2 = Vector2(160.0, 200.0)
const WORKER_SPAWN_DELTA: Vector2 = Vector2(0.0, 30.0)

const GOLD_NODE_POS: Vector2 = Vector2(220.0, 220.0)
const WOOD_NODE_POS: Vector2 = Vector2(220.0, 290.0)
const LEFT_CT_POS: Vector2 = Vector2(200.0, 250.0)
const RIGHT_CT_POS: Vector2 = Vector2(440.0, 250.0)
const BARRACKS_PLACE_POS: Vector2 = Vector2(300.0, 250.0)
const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 350.0, 400.0)

const BARRACKS_COST_GOLD: int = 80
const BARRACKS_COST_WOOD: int = 50


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _controllers: Dictionary = {}   # actor_id → RtsUnitController

var _workers: Array[RtsUnitActor] = []
var _resource_nodes: Array[RtsResourceNode] = []

var _right_ct: RtsBuildingActor = null
var _spawned_melee_ids: Array[String] = []
var _attack_events: Array[Dictionary] = []

# 跟踪每 worker 是否曾经 carrying 非空 (cycle_workers 验证)
var _worker_ever_carried: Array[bool] = []
# barracks 是否已 enqueue (避免重复 enqueue; true 已隐含 resources 曾 ≥ cost)
var _barracks_enqueued: bool = false
var _barracks_enqueued_tick: int = -1


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
	for i in range(NUM_WORKERS):
		var pos: Vector2 = WORKER_SPAWN_BASE + WORKER_SPAWN_DELTA * float(i)
		var worker := _spawn_worker(pos)
		_workers.append(worker)
		_worker_ever_carried.append(false)

	# 左 ct (drop-off; create_crystal_tower 工厂自动 is_drop_off=true)
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = LEFT_CT_POS

	# 中立 ResourceNode (team_id=-1) — 1 gold + 1 wood, 与 smoke_harvest_loop 同模式
	var gold_node := RtsResourceNodes.create_gold_node()
	gold_node.set_team_id(-1)
	_world.add_actor(gold_node)
	gold_node.position_2d = GOLD_NODE_POS
	_resource_nodes.append(gold_node)

	var wood_node := RtsResourceNodes.create_wood_node()
	wood_node.set_team_id(-1)
	_world.add_actor(wood_node)
	wood_node.position_2d = WOOD_NODE_POS
	_resource_nodes.append(wood_node)

	# 右 ct (hp=2000 永远不死) — 防右方判负, 让战斗持续到 MAX_TICKS
	_right_ct = RtsBuildings.create_crystal_tower()
	_right_ct.set_team_id(1)
	_world.add_actor(_right_ct)
	_right_ct.position_2d = RIGHT_CT_POS

	# Team configs: 左方 starting {gold: 0, wood: 0} 强制 worker harvest 才能放 barracks
	# (不与 D17 starting {100,100} 对齐 — 本 smoke 验"harvest 攒到 cost"链路)
	var left_cfg := RtsTeamConfig.create(0, "human", {"gold": 0, "wood": 0}, LEFT_BUILD_ZONE)
	var right_cfg := RtsTeamConfig.unconfigured(1)

	# left_team: 5 worker + left ct; right_team: right ct
	var left_actors: Array[RtsBattleActor] = [left_ct]
	for w in _workers:
		left_actors.append(w)
	var right_actors: Array[RtsBattleActor] = [_right_ct]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
		"event_sink": Callable(self, "_on_event_sink"),
	})

	# 主循环
	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()

		# 跟踪 worker carrying (cycle 验证)
		for i in range(_workers.size()):
			if not _worker_ever_carried[i] and not _workers[i].carrying.is_empty():
				_worker_ever_carried[i] = true

		# 资源到 cost → enqueue PlaceBuildingCommand barracks (一次性)
		if not _barracks_enqueued:
			var rs: Dictionary = _procedure.get_team_resources(0)
			var cur_gold: int = int(rs.get("gold", 0))
			var cur_wood: int = int(rs.get("wood", 0))
			if cur_gold >= BARRACKS_COST_GOLD and cur_wood >= BARRACKS_COST_WOOD:
				var current_tick: int = _procedure.get_current_tick()
				_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
					current_tick + 1, 0, RtsBuildingConfig.KIND_BARRACKS, BARRACKS_PLACE_POS,
				))
				_barracks_enqueued = true
				_barracks_enqueued_tick = current_tick + 1

		if _procedure.should_end():
			_fail("battle ended unexpectedly at tick %d (双方 ct 不死, melee 攻 ct 不致死); result=%s" % [
				_procedure.get_current_tick(), _procedure.get_result(),
			])
			return

	_procedure.finish()

	# ===== 验证 (AC3) =====
	# 1. 5 worker 全 alive (worker 不卡)
	var alive_workers: int = 0
	for w in _workers:
		if not w.is_dead():
			alive_workers += 1
	if alive_workers != NUM_WORKERS:
		_fail("expected %d alive workers, got %d" % [NUM_WORKERS, alive_workers])
		return

	# 2. cycle_workers ≥ 1 (HarvestActivity transfer 触发, ReturnAndDrop 也走过)
	var cycle_workers: int = 0
	for ever_carried in _worker_ever_carried:
		if ever_carried:
			cycle_workers += 1
	if cycle_workers < 1:
		_fail("no worker ever had carrying non-empty (HarvestActivity 没触发 transfer)")
		return

	# 3. barracks 已 enqueue + placement command success
	#    (_barracks_enqueued=true 已隐含 resources 曾达到 cost — enqueue 条件就是 ≥80g+50w)
	if not _barracks_enqueued:
		_fail("barracks 未在 %d tick 内攒齐 cost (cost=%d/%d); harvest 链路异常" % [
			MAX_TICKS, BARRACKS_COST_GOLD, BARRACKS_COST_WOOD,
		])
		return
	var log: Array[Dictionary] = _procedure.get_player_commands_log()
	if log.is_empty():
		_fail("placement command not applied (log empty)")
		return
	var entry: Dictionary = log[0]
	var result: Dictionary = entry.get("result", {})
	if not result.get("success", false):
		_fail("barracks placement failed: reason=%s" % str(result.get("reason", "")))
		return
	var barracks_id: String = str(result.get("actor_id", ""))
	if barracks_id.is_empty():
		_fail("placement success but actor_id missing")
		return

	# 4. ≥ 1 melee spawn (barracks 放置后 production cycle 至少完成 1 次)
	var melee_spawned: int = _spawned_melee_ids.size()
	if melee_spawned < 1:
		_fail("barracks 放置后未 spawn melee (placement_tick=%d, spawn_count=0; production_period 4s 内应 spawn ≥ 1)" % _barracks_enqueued_tick)
		return

	# 5. ≥ 1 次 melee → right_ct 攻击事件 (经济闭环对外可观主验证)
	var melee_to_ct_attacks: int = 0
	for ev in _attack_events:
		var src_id: String = ev.get("source_actor_id", "")
		var tgt_id: String = ev.get("target_actor_id", "")
		if tgt_id != _right_ct.get_id():
			continue
		# src 在 _spawned_melee_ids
		if _spawned_melee_ids.has(src_id):
			melee_to_ct_attacks += 1
	if melee_to_ct_attacks < 1:
		_fail("no melee → right_ct attack event (melee_spawned=%d, total_attack_events=%d); 经济闭环未走完" % [
			melee_spawned, _attack_events.size(),
		])
		return

	# 报告
	var final_resources: Dictionary = _procedure.get_team_resources(0)
	var final_gold: int = int(final_resources.get("gold", 0))
	var final_wood: int = int(final_resources.get("wood", 0))
	print("rts economy_demo smoke: ticks=%d alive_workers=%d cycle_workers=%d barracks_enqueued_tick=%d melee_spawned=%d melee_to_ct_attacks=%d final_gold=%d final_wood=%d" % [
		_procedure.get_current_tick(), alive_workers, cycle_workers, _barracks_enqueued_tick,
		melee_spawned, melee_to_ct_attacks, final_gold, final_wood,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - economy full cycle: harvest → cost → barracks → melee → attack ct")
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_worker(pos: Vector2) -> RtsUnitActor:
	var worker := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.WORKER)
	worker.set_team_id(0)
	_world.add_actor(worker)
	worker.position_2d = pos

	var motion_component := RtsMotionComponent.attach_default(worker, _world)

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(worker.unit_class)
	var controller := RtsUnitController.new(worker, motion_component, strategy)
	_controllers[worker.get_id()] = controller

	return worker


## production_system 调用; 把 barracks 生产的 melee spawn 出来。
##
## 与 smoke_castle_war_minimal 同模式 — 不 set_activity_chain, 让 RtsBasicAttackStrategy.decide /
## AutoTargetSystem 自然驱动 melee: AutoTarget 选距离最近的敌方 actor (即 right_ct, mask GROUND
## 能命中 building) → 写 cached_target_id → strategy.decide 返 attack activity → melee march + attack。
##
## 不用 RtsAttackMoveActivity override — AttackMove 到达终点后会切 IdleActivity 不主动 attack
## building, 导致 melee 站在 right_ct 旁边不打。
func _spawn_unit_for_building(building: RtsBuildingActor) -> RtsUnitActor:
	if building == null or building.is_dead():
		return null
	var unit_class: int = building.spawn_unit_kind
	if unit_class < 0:
		return null
	var team_id: int = building.get_team_id()

	var spawn_offset: float = 28.0
	var spawn_pos: Vector2
	if team_id == 0:
		spawn_pos = building.position_2d + Vector2(spawn_offset, 0.0)
	else:
		spawn_pos = building.position_2d - Vector2(spawn_offset, 0.0)

	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	unit.stance = building.spawn_unit_stance
	_world.add_actor(unit)
	unit.position_2d = spawn_pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	_controllers[unit.get_id()] = controller

	_procedure.add_unit_to_team(unit, team_id)
	_spawned_melee_ids.append(unit.get_id())
	return unit


func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		if event.get("kind", "") == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			_attack_events.append(event)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
