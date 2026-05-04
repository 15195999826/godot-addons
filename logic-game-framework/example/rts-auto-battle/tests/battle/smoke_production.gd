## RTS Production System smoke (P2.5 — AC4 gate)
##
## 验证要点 (AC4):
##   1. 兵营周期 spawn 单位: 30s 内左 / 右各 spawn ≥ 5 个 melee
##   2. spawn 后单位被加入对应 team_id 列表 (procedure.add_unit_to_team)
##   3. spawn 后单位至少有 1 个朝向对方阵营移动 (左队最大 x 偏移 ≥ 50px)
##   4. 建筑 footprint 被写入 grid pathing map (寻路绕开 building cells)
##
## 不验证 (留给 P2.6):
##   - 玩家命令 / building placement 合法性
##   - 水晶塔胜负判定
##
## 设计:
##   - 自建一个轻量场景 host (Node2D) 持 grid; 不复用 RtsBattleMap (它带中央障碍, 干扰本测)
##   - 左兵营 (2,2) @ (100, 230); 右兵营 (2,2) @ (400, 230) — 都对称分布, 让两阵营产兵互打
##   - 不放水晶塔 / 防御塔 — 本 smoke 只验证生产, 简化最大化
##   - rng_seed = 12345; 与 smoke_determinism 同 seed 让回归对比方便
extends Node


const UnitConfig := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 30.0
const RNG_SEED: int = 12345

const MAP_WIDTH: float = 500.0
const MAP_HEIGHT: float = 500.0

## 期望 30s @ 50ms / 4000ms 周期 → 7-8 spawn / team; 留 buffer 阈值 5
const EXPECTED_MIN_SPAWNS_PER_TEAM: int = 5

## "至少 1 个左队 spawn 单位移动 ≥ 50 px 朝东" — barracks 边缘 x=128 → spawn x=140 → 阈值 190
const MIN_EASTWARD_DISPLACEMENT: float = 50.0


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _controllers: Dictionary = {}   # actor_id → RtsUnitController

## spawn 跟踪: actor_id → { team_id, spawn_pos, max_x_after_spawn }
## (用 Dictionary 而不是单独 Array 让我们能在 ticks 里更新 max_x)
var _spawned: Dictionary = {}


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

	# 左 / 右 barracks (2x2 footprint, 中央水平对称)
	var left_barracks := RtsBuildings.create_barracks()
	left_barracks.set_team_id(0)
	_world.add_actor(left_barracks)
	left_barracks.position_2d = Vector2(100.0, 230.0)

	var right_barracks := RtsBuildings.create_barracks()
	right_barracks.set_team_id(1)
	_world.add_actor(right_barracks)
	right_barracks.position_2d = Vector2(400.0, 230.0)

	var left_team: Array[RtsBattleActor] = [left_barracks]
	var right_team: Array[RtsBattleActor] = [right_barracks]

	_procedure = _world.start_rts_battle(left_team, right_team, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"rng_seed": RNG_SEED,
	})

	# 验证 footprint 注册了: barracks cells 应该 blocking
	if not _verify_footprint_blocking(left_barracks):
		_fail("left barracks footprint NOT blocking after procedure.start()")
		return
	if not _verify_footprint_blocking(right_barracks):
		_fail("right barracks footprint NOT blocking after procedure.start()")
		return

	# 主循环
	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for tick_i in range(max_ticks):
		_procedure.tick_once()
		_update_spawn_max_x()  # 跟踪所有 spawn 单位的最大 x
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== AC4 主断言 =====
	var left_count: int = _count_spawned_team(0)
	var right_count: int = _count_spawned_team(1)

	if left_count < EXPECTED_MIN_SPAWNS_PER_TEAM:
		_fail("left barracks spawned only %d units (expected >= %d)" % [left_count, EXPECTED_MIN_SPAWNS_PER_TEAM])
		return
	if right_count < EXPECTED_MIN_SPAWNS_PER_TEAM:
		_fail("right barracks spawned only %d units (expected >= %d)" % [right_count, EXPECTED_MIN_SPAWNS_PER_TEAM])
		return

	# 至少 1 个左队 spawn 朝东偏移 ≥ MIN_EASTWARD_DISPLACEMENT
	var max_left_eastward: float = -INF
	for actor_id in _spawned.keys():
		var record: Dictionary = _spawned[actor_id]
		if record.get("team_id", -1) != 0:
			continue
		var displacement: float = float(record.get("max_x", 0.0)) - float(record.get("spawn_x", 0.0))
		if displacement > max_left_eastward:
			max_left_eastward = displacement
	if max_left_eastward < MIN_EASTWARD_DISPLACEMENT:
		_fail("no left-spawned unit reached eastward displacement >= %.1f (max=%.1f)" % [
			MIN_EASTWARD_DISPLACEMENT, max_left_eastward,
		])
		return

	# 报告
	print("rts production smoke: ticks=%d left_spawned=%d right_spawned=%d max_left_eastward=%.2f px" % [
		_procedure.get_current_tick(), left_count, right_count, max_left_eastward,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - production cycle ok, footprint registered, units march east")
	get_tree().quit(0)


# ========== Spawner ==========

## procedure 调本回调; 创建 unit + nav + controller, 加入 procedure team。
func _spawn_unit_for_building(building: RtsBuildingActor) -> RtsUnitActor:
	if building == null or building.is_dead():
		return null

	var unit_class: int = building.spawn_unit_kind
	if unit_class < 0:
		return null
	var team_id: int = building.get_team_id()

	# 决定 spawn 位置: 朝对方阵营前一格 + 单位半径 + buffer
	# 左队 (team 0) 在 barracks 东侧 (+x); 右队 (team 1) 在 barracks 西侧 (-x)
	var spawn_pos: Vector2 = _compute_spawn_pos(building, team_id)
	var target_pos: Vector2 = _compute_target_pos(team_id)

	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	unit.stance = building.spawn_unit_stance
	_world.add_actor(unit)
	unit.position_2d = spawn_pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	# SpawnLane intent: 初始 attack-move 朝对方主基地; strategy.decide 在下个 tick 找到敌人时
	# 会替换为 AttackActivity (reconcile cancel + flush)。即使被替换, 此 chain 头标记了"march to
	# target_pos" 意图, 在 enemy 暂时不可达 (DEFENSIVE / HOLD_FIRE 全场无敌时) 仍能驱动单位前进。
	controller.set_activity_chain(RtsAttackMoveActivity.new(target_pos))
	_controllers[unit.get_id()] = controller

	_procedure.add_unit_to_team(unit, team_id)

	_spawned[unit.get_id()] = {
		"team_id": team_id,
		"spawn_x": spawn_pos.x,
		"max_x": spawn_pos.x,  # 起手等于 spawn_x; 后续 _update_spawn_max_x 累积
	}
	return unit


# ========== 内部 ==========

## 兵营 footprint 是 (2,2), AABB 偏左上 → world coverage:
##   左兵营 @ (100, 230) → cells (2..3, 6..7) → world x in [64, 128], y in [192, 256]
##   右兵营 @ (400, 230) → cells (11..12, 6..7) → world x in [352, 416], y in [192, 256]
##
## 单位 collision_radius=12 (melee); 留 8 px buffer 避免 spawn 与 footprint 边缘重叠。
func _compute_spawn_pos(building: RtsBuildingActor, team_id: int) -> Vector2:
	var building_pos: Vector2 = building.position_2d
	var footprint_half_x: float = float(building.footprint_size.x) * 16.0  # cell_size/2 × cells/side
	var unit_radius: float = 12.0
	var buffer: float = 8.0
	var dx: float = footprint_half_x + unit_radius + buffer
	if team_id == 0:
		return Vector2(building_pos.x + dx, building_pos.y)
	else:
		return Vector2(building_pos.x - dx, building_pos.y)


## SpawnLane 目标点: 对方阵营中心 (P2.5 没有水晶塔; P2.6 改为 enemy_crystal_tower.position_2d)。
func _compute_target_pos(team_id: int) -> Vector2:
	if team_id == 0:
		return Vector2(400.0, 230.0)  # 朝右兵营
	else:
		return Vector2(100.0, 230.0)  # 朝左兵营


## 验证建筑 footprint 已被 grid 标 blocking。
func _verify_footprint_blocking(building: RtsBuildingActor) -> bool:
	var footprint: Array = building.get_footprint_cells(_grid)
	if footprint.is_empty():
		return false
	for c in footprint:
		var coord := c as HexCoord
		if not _grid.model.is_tile_blocking(coord):
			return false
	return true


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
