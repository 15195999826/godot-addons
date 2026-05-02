## RTS Player Command + Production 集成 smoke (P2.6 — AC5 gate, 单元三; P2.5 + P2.6 联动)
##
## 验证要点 (玩家命令 → placement → production 完整链路):
##   1. tick 30 玩家命令应用成功 → left 阵营 barracks 出现
##   2. 资源扣减: left team_resources = 100 - 80 = 20 gold (Phase D barracks cost 80g+50w; 起手 100g+100w)
##   3. 后续 tick 内 production_system 累积 progress, 满周期触发 spawner 创建 melee
##   4. 30s 后 left 阵营 spawned 单位 ≥ 3 (placement @ tick 30 后 570 ticks ≈ 28.5s @ 4s 周期 = 7 spawn 理论, 阈值 ≥ 3 留 buffer)
##   5. 至少 1 个 spawn 单位朝东 ≥ 50 px (验证 override_strategy=true 让 SpawnLane 不被 strategy 替换)
##   6. 战斗未自然结束 — 双方 crystal_tower 都活, AutoTargetSystem 不打 buildings (current limitation)
##
## 设计与 smoke_production 的差异:
##   - smoke_production: 起手手动 add_actor 兵营 (不走 player command)
##   - 本 smoke: 起手 NO 兵营; 通过 PlaceBuildingCommand 在 tick 30 放置 → 验证完整 player command 链路
##   - 双方 crystal_tower 占位让 fallback / crystal-tower 判定不立刻结束战斗
##   - spawner 用 override_strategy=true: 让 SpawnLane RtsAttackMoveActivity 不被 strategy.decide 替换
##     (右方无敌人, AutoTargetSystem 写空 cached_target → strategy 提议 IdleActivity, 没 override 时 spawn 单位会原地不动)
##
## 设计:
##   - 自建 host + grid (无障碍)
##   - 左方 team_config: build_zone (50, 50) ~ (350, 350), starting_resources={"gold": 100, "wood": 100} (Phase D D17)
##   - 右方 team_config: 默认 (无 build_zone, resources={})
##   - 起手放双方 crystal_tower (各 hp=2000, 永远不死) — 不让任何一方 fallback 全灭
##   - 玩家命令 tick_stamp=30: PlaceBuildingCommand 兵营 @ (100, 230)
##   - 跑 600 ticks (30s @ 50ms)
extends Node


const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 30.0
const RNG_SEED: int = 12345

const STARTING_GOLD: int = 100   # Phase D D17 finalized
const STARTING_WOOD: int = 100   # Phase D D17 finalized
const BARRACKS_COST_GOLD: int = 80  # Phase D barracks cost

const PLACE_TICK: int = 30
const PLACE_POS: Vector2 = Vector2(100.0, 230.0)
const TARGET_POS: Vector2 = Vector2(400.0, 230.0)

const EXPECTED_MIN_SPAWNS: int = 3
const MIN_EASTWARD_DISPLACEMENT: float = 50.0


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _agents: Dictionary = {}        # actor_id → RtsNavAgent
var _controllers: Dictionary = {}   # actor_id → RtsUnitController

## spawn 跟踪 (与 smoke_production 同结构)
var _spawned: Dictionary = {}


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

	# 双方 crystal_tower 占位 — 让 fallback / crystal-tower 判定不立刻结束战斗
	# (左 crystal_tower 在 (50, 50) 角落; 右 crystal_tower 在 (450, 450) 角落; 都不在 build_zone 内)
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = Vector2(50.0, 50.0)

	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = Vector2(450.0, 450.0)

	# Team config: 左 build_zone (50, 50) ~ (350, 350); resources = {"gold": 200, "wood": 0}
	var left_team_cfg := RtsTeamConfig.create(
		0, "human", {"gold": STARTING_GOLD, "wood": STARTING_WOOD},
		Rect2(50.0, 50.0, 300.0, 300.0),
	)
	var right_team_cfg := RtsTeamConfig.create(1, "human", {}, Rect2())

	var left_actors: Array[RtsBattleActor] = [left_ct]
	var right_actors: Array[RtsBattleActor] = [right_ct]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_team_cfg, 1: right_team_cfg },
		"rng_seed": RNG_SEED,
	})

	# Player command: tick 30 放置兵营
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		PLACE_TICK, 0, RtsBuildingConfig.KIND_BARRACKS, PLACE_POS,
	))

	# 主循环
	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for tick_i in range(max_ticks):
		_procedure.tick_once()
		_update_spawn_max_x()
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 验证 =====
	# 1. 玩家命令 log 有 1 条 success
	var log: Array[Dictionary] = _procedure.get_player_commands_log()
	if log.size() != 1:
		_fail("expected 1 player_command log entry, got %d" % log.size())
		return
	var entry := log[0]
	var result: Dictionary = entry.get("result", {})
	if not result.get("success", false):
		_fail("placement command failed: reason=%s" % str(result.get("reason", "")))
		return
	var placed_id: String = str(result.get("actor_id", ""))
	if placed_id.is_empty():
		_fail("placement success but actor_id missing")
		return

	# 2. Resources 扣减 = cost (M2.1 Phase A 多资源 dict)
	var remaining: Dictionary = _procedure.get_team_resources(0)
	var expected_gold: int = STARTING_GOLD - BARRACKS_COST_GOLD
	var actual_gold: int = int(remaining.get("gold", 0))
	if actual_gold != expected_gold:
		_fail("expected gold %d after placement, got %d" % [expected_gold, actual_gold])
		return

	# 3. Spawn 数量 ≥ EXPECTED_MIN_SPAWNS
	var left_spawned: int = _count_spawned_team(0)
	if left_spawned < EXPECTED_MIN_SPAWNS:
		_fail("left barracks spawned only %d units (expected >= %d)" % [
			left_spawned, EXPECTED_MIN_SPAWNS,
		])
		return

	# 4. 至少 1 个 spawn 单位朝东 ≥ 50 px
	var max_left_eastward: float = -INF
	for actor_id in _spawned.keys():
		var record: Dictionary = _spawned[actor_id]
		if record.get("team_id", -1) != 0:
			continue
		var displacement: float = float(record.get("max_x", 0.0)) - float(record.get("spawn_x", 0.0))
		if displacement > max_left_eastward:
			max_left_eastward = displacement
	if max_left_eastward < MIN_EASTWARD_DISPLACEMENT:
		_fail("no left-spawned unit moved >= %.1f px east (max=%.1f); SpawnLane override may be broken" % [
			MIN_EASTWARD_DISPLACEMENT, max_left_eastward,
		])
		return

	# 5. 战斗未自然结束 (双方 crystal_tower 都活, AutoTarget 不打 buildings)
	if _procedure.get_result() != "":
		_fail("battle ended unexpectedly with result='%s' (both crystal_towers should be alive)" % _procedure.get_result())
		return

	# 报告
	print("rts player_command_production smoke: ticks=%d placed_id=%s left_spawned=%d max_eastward=%.2f gold_remaining=%d" % [
		_procedure.get_current_tick(), placed_id, left_spawned, max_left_eastward, actual_gold,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - player command placed barracks, production cycle started, units march east via override")
	get_tree().quit(0)


# ========== Spawner ==========

## 与 smoke_production 同结构, 唯一差异: set_activity_chain 第二参数 override_strategy=true,
## 让 SpawnLane 在 strategy.decide 提议 IdleActivity (右方无敌可见) 时不被替换。
func _spawn_unit_for_building(building: RtsBuildingActor) -> RtsUnitActor:
	if building == null or building.is_dead():
		return null

	var unit_class: int = building.spawn_unit_kind
	if unit_class < 0:
		return null
	var team_id: int = building.get_team_id()

	# 朝对方阵营前方 spawn (左 → +x; 右 → -x)
	var spawn_pos: Vector2 = _compute_spawn_pos(building, team_id)

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
	# P2.6 关键: override_strategy=true 让 SpawnLane 不被 IdleActivity 替换
	controller.set_activity_chain(RtsAttackMoveActivity.new(TARGET_POS), true)
	_controllers[unit.get_id()] = controller

	_procedure.add_unit_to_team(unit, team_id)

	_spawned[unit.get_id()] = {
		"team_id": team_id,
		"spawn_x": spawn_pos.x,
		"max_x": spawn_pos.x,
	}
	return unit


# ========== 内部 ==========

func _compute_spawn_pos(building: RtsBuildingActor, team_id: int) -> Vector2:
	var building_pos: Vector2 = building.position_2d
	var footprint_half_x: float = float(building.footprint_size.x) * 16.0
	var unit_radius: float = 12.0
	var buffer: float = 8.0
	var dx: float = footprint_half_x + unit_radius + buffer
	if team_id == 0:
		return Vector2(building_pos.x + dx, building_pos.y)
	else:
		return Vector2(building_pos.x - dx, building_pos.y)


func _update_spawn_max_x() -> void:
	for actor_id in _spawned.keys():
		var actor := _world.get_actor(actor_id) as RtsUnitActor
		if actor == null or actor.is_dead():
			continue
		var record: Dictionary = _spawned[actor_id]
		var current_max: float = float(record.get("max_x", 0.0))
		if actor.position_2d.x > current_max:
			record["max_x"] = actor.position_2d.x


func _count_spawned_team(team_id: int) -> int:
	var count: int = 0
	for actor_id in _spawned.keys():
		var record: Dictionary = _spawned[actor_id]
		if record.get("team_id", -1) == team_id:
			count += 1
	return count


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
