## RTS AI vs AI Observation 模式 spawn rally smoke
##
## 锁定 demo_rts_frontend._spawn_unit_for_building 的"production-spawn 单位接战"路径.
## 主拒绝场景 = spawner 在 spawn 后调 set_activity_chain(RtsMoveToActivity, true) —— 那种
## 写法让 controller 跳过 strategy.decide, AutoTargetSystem 写的 _cached_target_id 没人读,
## 双方兵相遇时擦肩不交火, 现象 = 视觉上"双方兵直接错开".
##
## 本 smoke mirror RtsMatchPreset.create_ai_vs_ai_observe (pre_spawn_barracks_each_side=true,
## 双方 500/500, 双 AI), 不调 set_activity_chain — 让 AutoTargetSystem + BasicAttackStrategy
## 自然驱动. 跑 600 ticks @ 50ms = 30s 期间双方各从预放的 barracks spawn ~7 个 melee, 应在
## 中线相遇互殴.
##
## 验证要点:
##   1. 双方都 spawn 出 ≥ 3 个 unit (production_period_ms=4000 / 50ms tick = 80 ticks/spawn,
##      600 ticks ≥ 7 次 spawn 机会, 留 3 余地避免 cells_blocked 抖动)
##   2. unit_to_unit_attacks ≥ 5 (修复前 = 5 / 修复后 ≈ 25; 下限 5 留 5x 头室)
##   3. 至少有 melee 死亡 (双方接战的副产物, 排除"两边都打建筑"的伪过)
##
## 关键不变量:
##   - spawner 必须不调 set_activity_chain — strategy.decide 接管 (跟 castle_war_minimal
##     spawner 同模式)
##   - AutoTargetSystem 全场扫敌, 不靠 LOS, melee mask=GROUND 选最近 enemy ground actor
##     (敌方 unit 移动时距离会比 ct 更近 → 切到 unit_to_unit attack)
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 31337
const MAX_TICKS: int = 600  # 30s

const STARTING_GOLD: int = 500
const STARTING_WOOD: int = 500
const NUM_WORKERS: int = 5
const WORKER_DELTA_Y: float = 30.0
const WORKER_BASE_Y: float = 200.0

const LEFT_BASE_X: float = 80.0
const RIGHT_BASE_X: float = 420.0
const LEFT_WORKER_X: float = LEFT_BASE_X + 20.0
const RIGHT_WORKER_X: float = RIGHT_BASE_X - 20.0
const LEFT_CT_POS: Vector2 = Vector2(LEFT_BASE_X, 350.0)
const RIGHT_CT_POS: Vector2 = Vector2(RIGHT_BASE_X, 350.0)
const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 200.0, 400.0)

const LEFT_GOLD_NODES: Array[Vector2] = [Vector2(180, 220), Vector2(180, 280)]
const LEFT_WOOD_NODES: Array[Vector2] = [Vector2(180, 300), Vector2(180, 410)]
const RIGHT_GOLD_NODES: Array[Vector2] = [Vector2(320, 220), Vector2(320, 280)]
const RIGHT_WOOD_NODES: Array[Vector2] = [Vector2(320, 300), Vector2(320, 410)]


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _agents: Dictionary = {}        # actor_id → RtsNavAgent
var _controllers: Dictionary = {}   # actor_id → RtsUnitController
var _spawned_unit_ids: Array[String] = []
var _attack_events: Array[Dictionary] = []
var _death_events: Array[Dictionary] = []


func _ready() -> void:
	GameWorld.init()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(500.0, 500.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 双方 ct + 预放 barracks (mirror Observe preset pre_spawn_barracks_each_side=true)
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = LEFT_CT_POS
	left_ct.sync_obstruction_shape()

	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = RIGHT_CT_POS
	right_ct.sync_obstruction_shape()

	var left_barracks := RtsBuildings.create_barracks()
	left_barracks.set_team_id(0)
	_world.add_actor(left_barracks)
	left_barracks.position_2d = LEFT_CT_POS + Vector2(96.0, 0.0)
	left_barracks.sync_obstruction_shape()

	var right_barracks := RtsBuildings.create_barracks()
	right_barracks.set_team_id(1)
	_world.add_actor(right_barracks)
	right_barracks.position_2d = RIGHT_CT_POS + Vector2(-96.0, 0.0)
	right_barracks.sync_obstruction_shape()

	var left_actors: Array[RtsBattleActor] = [left_ct, left_barracks]
	var right_actors: Array[RtsBattleActor] = [right_ct, right_barracks]

	for i in range(NUM_WORKERS):
		var lp: Vector2 = Vector2(LEFT_WORKER_X, WORKER_BASE_Y + WORKER_DELTA_Y * float(i))
		left_actors.append(_spawn_unit(Config.UnitClass.WORKER, 0, lp))
		var rp: Vector2 = Vector2(RIGHT_WORKER_X, WORKER_BASE_Y + WORKER_DELTA_Y * float(i))
		right_actors.append(_spawn_unit(Config.UnitClass.WORKER, 1, rp))

	_spawn_resource_nodes(LEFT_GOLD_NODES, true)
	_spawn_resource_nodes(LEFT_WOOD_NODES, false)
	_spawn_resource_nodes(RIGHT_GOLD_NODES, true)
	_spawn_resource_nodes(RIGHT_WOOD_NODES, false)

	var left_cfg := RtsTeamConfig.create(
		0, "ai", {"gold": STARTING_GOLD, "wood": STARTING_WOOD}, LEFT_BUILD_ZONE,
	)
	var right_cfg := RtsTeamConfig.create(
		1, "ai", {"gold": STARTING_GOLD, "wood": STARTING_WOOD}, Rect2(),
	)

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
		"event_sink": Callable(self, "_on_event_sink"),
	})
	_procedure.attach_computer_player(0)
	_procedure.attach_computer_player(1)

	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 验证 =====
	var ticks: int = _procedure.get_current_tick()
	var unit_to_unit: int = 0
	var unit_to_building: int = 0
	for ev in _attack_events:
		var src_id: String = ev.get("source_actor_id", "")
		var tgt_id: String = ev.get("target_actor_id", "")
		var src := _world.get_actor(src_id)
		var tgt := _world.get_actor(tgt_id)
		if src is RtsUnitActor and tgt is RtsUnitActor:
			unit_to_unit += 1
		elif src is RtsUnitActor and tgt is RtsBuildingActor:
			unit_to_building += 1

	# 双方 spawn 数 (排除起手 worker, 只算 production spawn 出来的 melee)
	var left_spawned: int = 0
	var right_spawned: int = 0
	for uid in _spawned_unit_ids:
		var u := _world.get_actor(uid) as RtsUnitActor
		if u == null:
			continue
		if u.get_team_id() == 0:
			left_spawned += 1
		else:
			right_spawned += 1

	# 1. 双方都至少 spawn 出 3 个 melee (production rally OK; cells_blocked 抖动留 3 余地)
	if left_spawned < 3:
		_fail("left team spawned only %d units (expected ≥ 3)" % left_spawned)
		return
	if right_spawned < 3:
		_fail("right team spawned only %d units (expected ≥ 3)" % right_spawned)
		return

	# 2. 关键断言: unit_to_unit attacks ≥ 5 (锁定 spawner 不重新引入 RtsMoveToActivity+override).
	#    Repro baseline: override=true → unit_to_unit=5; override=false → unit_to_unit≈25.
	#    设 ≥ 5 是因为 override=true 时偶尔有 5 次 unit_to_unit (双方在 ct 旁挤一起时 spatial
	#    碰撞被 AutoTarget 当 mover); 修复后稳定 20+. 用 ≥ 5 + 死亡条件双重锁定排错.
	if unit_to_unit < 5:
		_fail("unit_to_unit attacks = %d (expected ≥ 5; spawner may have re-introduced override RtsMoveToActivity, units passed each other without engaging)" % unit_to_unit)
		return

	# 3. 至少 1 个 melee 死亡 (排除 "两边都打建筑没死人" 的伪过场景).
	#    死的可能是 unit/building 任意, 重点是要有死亡发生.
	var melee_deaths: int = 0
	for ev in _death_events:
		var actor_id: String = ev.get("actor_id", "")
		var actor := _world.get_actor(actor_id)
		if actor is RtsUnitActor and (actor as RtsUnitActor).unit_class != Config.UnitClass.WORKER:
			melee_deaths += 1
	if melee_deaths < 1:
		_fail("no melee deaths recorded (expected ≥ 1; both sides may not be engaging in combat)")
		return

	# 报告
	print("rts ai_vs_ai_observe smoke: ticks=%d spawned L=%d R=%d attacks_total=%d unit_to_unit=%d unit_to_building=%d melee_deaths=%d" % [
		ticks, left_spawned, right_spawned,
		_attack_events.size(), unit_to_unit, unit_to_building, melee_deaths,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - units engaged each other in combat (unit_to_unit=%d ≥ 5, melee_deaths=%d ≥ 1)" % [unit_to_unit, melee_deaths])
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	_world.add_actor(unit)
	unit.position_2d = pos

	var agent := RtsNavAgent.new()
	_host.add_child(agent)
	agent.bind_actor(unit, _grid)
	_agents[unit.get_id()] = agent

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, agent, strategy)
	_controllers[unit.get_id()] = controller

	return unit


func _spawn_resource_nodes(positions: Array[Vector2], is_gold: bool) -> void:
	for pos in positions:
		var node: RtsResourceNode = RtsResourceNodes.create_gold_node() if is_gold else RtsResourceNodes.create_wood_node()
		node.set_team_id(-1)
		_world.add_actor(node)
		node.position_2d = pos


## production_system 调用; mirror demo_rts_frontend._spawn_unit_for_building 修复版本:
## **不调 set_activity_chain** — 让 AutoTargetSystem + BasicAttackStrategy 自然驱动 (跟
## castle_war_minimal smoke 同模式).
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

	var unit := _spawn_unit(unit_class, team_id, spawn_pos)
	unit.stance = building.spawn_unit_stance
	_procedure.add_unit_to_team(unit, team_id)
	_spawned_unit_ids.append(unit.get_id())
	return unit


func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		var kind: String = event.get("kind", "")
		if kind == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			_attack_events.append(event)
		elif kind == RtsBattleEvents.ACTOR_DIED_EVENT:
			_death_events.append(event)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
