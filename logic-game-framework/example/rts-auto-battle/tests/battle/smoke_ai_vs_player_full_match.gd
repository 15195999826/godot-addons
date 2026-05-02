## RTS AI vs Player Full Match smoke (M2.2 — AC4 主 gate)
##
## 验证 RtsComputerPlayer (M2.2 sub-feature) 自主 AI 链路 — left team attach AI vs right team
## 站桩, 跑 600 tick @ 30Hz, AI 自动:
##   1. 起手 5 worker harvest (沿用 M2.1 的 RtsHarvestStrategy, AI 不 override worker)
##   2. tick 30 决策 → 资源足 (起手 100/100 ≥ 80/50) → enqueue PlaceBuildingCommand barracks
##      在 ct 偏移点 (E4: ct + Vector2(96, 0))
##   3. barracks 周期 spawn melee (production_period_ms=4000ms = 120 tick @ 30Hz)
##   4. tick K 决策 (alive non-worker ≥ 3) → enqueue MoveUnitsCommand 攻右方 ct (only-once)
##   5. melee march to right_ct → controller._player_command_active 链跑完 → AutoTargetSystem
##      写 cached_target_id (right_ct mask=GROUND OK) → strategy.decide → attack ct
##
## E10 决策保旧 smoke 不破: 既有 12 项 smoke 不 attach AI, 数字 0 漂移 (验证落 AC6 bit-identical)
##
## 设计:
##   - 左 ct @ (200, 250) hp=2000, drop-off (worker harvest 终点)
##   - 右 ct @ (440, 250) hp=2000, 站桩 (AI 攻击目标)
##   - 双方 5 worker @ (160, y) / (480, y), y ∈ {200, 230, 260, 290, 320}
##   - 中立 (team_id=-1) 1 gold + 1 wood node 每方:
##     - left  gold @ (220, 220), wood @ (220, 290)
##     - right gold @ (420, 220), wood @ (420, 290)
##   - left starting {gold: 100, wood: 100} (D17, 起手能造 1 barracks)
##   - right starting {gold: 100, wood: 100} (站桩, 不 attach AI 不会用)
##   - left build_zone Rect2(50, 50, 350, 400) (能放 barracks @ (296, 250) = ct+(96,0))
##   - 30Hz fixed-tick, MAX_TICKS=600 (20s 真实时间, 足够 3+ melee spawn + attack ct)
##   - 主循环每 tick check world 的 left team alive barracks 数 (peak 跟踪)
##   - barracks spawner 与 smoke_economy_demo 同模式, melee 不 set_activity_chain 自然 attack
##   - event_sink 收 ATTACK_RESOLVED_EVENT 用于 melee → right_ct 攻击次数验证
##
## 决策来源: task-plan/m2-2-ai-opponent/README.md §AC4 + E1-E10 决策表
extends Node


const TICK_INTERVAL_MS: float = 1000.0 / 30.0  # 30Hz fixed-tick
const RNG_SEED: int = 31415
const MAX_TICKS: int = 600  # 20s 真实时间 @ 30Hz; barracks production_period_ms=4000ms → 5 melee 理论极值

const MAP_WIDTH: float = 600.0
const MAP_HEIGHT: float = 500.0

const NUM_WORKERS_PER_TEAM: int = 5
const WORKER_SPAWN_BASE_Y: float = 200.0
const WORKER_SPAWN_DELTA_Y: float = 30.0

const LEFT_WORKER_X: float = 160.0
const RIGHT_WORKER_X: float = 480.0
const LEFT_CT_POS: Vector2 = Vector2(200.0, 250.0)
const RIGHT_CT_POS: Vector2 = Vector2(440.0, 250.0)

const LEFT_GOLD_NODE_POS: Vector2 = Vector2(220.0, 220.0)
const LEFT_WOOD_NODE_POS: Vector2 = Vector2(220.0, 290.0)
const RIGHT_GOLD_NODE_POS: Vector2 = Vector2(420.0, 220.0)
const RIGHT_WOOD_NODE_POS: Vector2 = Vector2(420.0, 290.0)

const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 350.0, 400.0)

# 验收阈值 (E8: 中等强度)
const MIN_AI_BARRACKS: int = 1
const MIN_AI_UNITS_SPAWNED: int = 3
const MIN_AI_UNIT_TO_CT_ATTACKS: int = 1


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _agents: Dictionary = {}
var _controllers: Dictionary = {}

var _right_ct: RtsBuildingActor = null
var _ai_spawned_unit_ids: Array[String] = []  # AI team (=0) barracks 生产的 unit_id
var _attack_events: Array[Dictionary] = []
var _peak_ai_barracks: int = 0


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

	# Spawn left + right worker / ct / nodes
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	# 双方 ct (drop-off + 防判负)
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = LEFT_CT_POS
	left_actors.append(left_ct)

	_right_ct = RtsBuildings.create_crystal_tower()
	_right_ct.set_team_id(1)
	_world.add_actor(_right_ct)
	_right_ct.position_2d = RIGHT_CT_POS
	right_actors.append(_right_ct)

	# 双方各 5 worker
	for i in range(NUM_WORKERS_PER_TEAM):
		var lp := Vector2(LEFT_WORKER_X, WORKER_SPAWN_BASE_Y + WORKER_SPAWN_DELTA_Y * float(i))
		left_actors.append(_spawn_worker(0, lp))
		var rp := Vector2(RIGHT_WORKER_X, WORKER_SPAWN_BASE_Y + WORKER_SPAWN_DELTA_Y * float(i))
		right_actors.append(_spawn_worker(1, rp))

	# 中立 ResourceNode 双方各 1 gold + 1 wood (worker 选最近自然分流)
	_spawn_resource_node(LEFT_GOLD_NODE_POS, true)
	_spawn_resource_node(LEFT_WOOD_NODE_POS, false)
	_spawn_resource_node(RIGHT_GOLD_NODE_POS, true)
	_spawn_resource_node(RIGHT_WOOD_NODE_POS, false)

	# Team configs (D17 — 双方 starting {100, 100})
	var left_cfg := RtsTeamConfig.create(0, "human", {"gold": 100, "wood": 100}, LEFT_BUILD_ZONE)
	var right_cfg := RtsTeamConfig.create(1, "ai", {"gold": 100, "wood": 100}, Rect2())

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
		"event_sink": Callable(self, "_on_event_sink"),
	})

	# AC4 — 左 team(team_id=0) attach AI; 右 team(team_id=1) NO attach (站桩)
	_procedure.attach_computer_player(0)

	# 主循环
	for _tick_i in range(MAX_TICKS):
		_procedure.tick_once()

		# 跟踪 AI team alive barracks 数 (peak 取最大值)
		var cur_barracks: int = _count_team_alive_barracks(0)
		if cur_barracks > _peak_ai_barracks:
			_peak_ai_barracks = cur_barracks

		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 验证 (AC4) =====
	var ai_units_spawned: int = _ai_spawned_unit_ids.size()
	var ai_unit_to_ct_attacks: int = 0
	for ev in _attack_events:
		var src_id: String = ev.get("source_actor_id", "")
		var tgt_id: String = ev.get("target_actor_id", "")
		if tgt_id != _right_ct.get_id():
			continue
		if _ai_spawned_unit_ids.has(src_id):
			ai_unit_to_ct_attacks += 1

	if _peak_ai_barracks < MIN_AI_BARRACKS:
		_fail("ai_barracks=%d < %d (AI 没放下 barracks; 检查 _try_build_barracks 决策路径)" % [
			_peak_ai_barracks, MIN_AI_BARRACKS,
		])
		return
	if ai_units_spawned < MIN_AI_UNITS_SPAWNED:
		_fail("ai_units_spawned=%d < %d (barracks production 没 spawn 够; barracks_alive=%d)" % [
			ai_units_spawned, MIN_AI_UNITS_SPAWNED, _peak_ai_barracks,
		])
		return
	if ai_unit_to_ct_attacks < MIN_AI_UNIT_TO_CT_ATTACKS:
		_fail("ai_unit_to_ct_attacks=%d < %d (AI unit 没 attack 到右方 ct; ai_units_spawned=%d, total_attack_events=%d)" % [
			ai_unit_to_ct_attacks, MIN_AI_UNIT_TO_CT_ATTACKS,
			ai_units_spawned, _attack_events.size(),
		])
		return

	print("rts ai_vs_player smoke: ticks=%d ai_barracks=%d ai_units_spawned=%d ai_unit_to_ct_attacks=%d total_attack_events=%d" % [
		_procedure.get_current_tick(), _peak_ai_barracks, ai_units_spawned,
		ai_unit_to_ct_attacks, _attack_events.size(),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - ai_barracks=%d ai_units_spawned=%d ai_unit_to_ct_attacks=%d" % [
		_peak_ai_barracks, ai_units_spawned, ai_unit_to_ct_attacks,
	])
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_worker(p_team_id: int, pos: Vector2) -> RtsUnitActor:
	var worker := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.WORKER)
	worker.set_team_id(p_team_id)
	_world.add_actor(worker)
	worker.position_2d = pos

	var agent := RtsNavAgent.new()
	_host.add_child(agent)
	agent.bind_actor(worker, _grid)
	_agents[worker.get_id()] = agent

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(worker.unit_class)
	var controller := RtsUnitController.new(worker, agent, strategy)
	_controllers[worker.get_id()] = controller

	return worker


func _spawn_resource_node(pos: Vector2, is_gold: bool) -> void:
	var node: RtsResourceNode = RtsResourceNodes.create_gold_node() if is_gold else RtsResourceNodes.create_wood_node()
	node.set_team_id(-1)
	_world.add_actor(node)
	node.position_2d = pos


func _count_team_alive_barracks(p_team_id: int) -> int:
	var count: int = 0
	for actor in _world.get_alive_actors():
		if not (actor is RtsBuildingActor):
			continue
		var b := actor as RtsBuildingActor
		if b.get_team_id() != p_team_id:
			continue
		if b.building_kind == RtsBuildingConfig.KIND_BARRACKS:
			count += 1
	return count


## production_system 调用; AI team(=0) 的 barracks spawn melee 跟踪进 _ai_spawned_unit_ids。
##
## 与 smoke_economy_demo 同模式 — 不 set_activity_chain, 让 RtsBasicAttackStrategy.decide /
## AutoTargetSystem 自然驱动: AI MoveUnitsCommand 派出后 unit._player_command_active = true,
## 走 RtsMoveToActivity 到 right_ct.position; 抵达后 controller._player_command_active 自动清,
## strategy 接管 → AutoTargetSystem 已在 right_ct 范围 → cached_target_id = right_ct.id →
## strategy.decide 返 attack activity → unit attack right_ct (mask=GROUND 命中 building OK)。
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

	var agent := RtsNavAgent.new()
	_host.add_child(agent)
	agent.bind_actor(unit, _grid)
	_agents[unit.get_id()] = agent

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, agent, strategy)
	_controllers[unit.get_id()] = controller

	_procedure.add_unit_to_team(unit, team_id)

	# 仅跟踪 AI team(=0) 的 spawn — 用于 ai_units_spawned + ai_unit_to_ct_attacks 验证
	if team_id == 0:
		_ai_spawned_unit_ids.append(unit.get_id())
	return unit


func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		if event.get("kind", "") == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			_attack_events.append(event)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
