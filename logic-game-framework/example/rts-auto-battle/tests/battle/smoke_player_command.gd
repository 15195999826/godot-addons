## RTS Player Command smoke (P2.6 — AC5 gate, 单元一)
##
## 验证要点:
##   1. RtsPlaceBuildingCommand 在 tick 30 应用成功 → barracks 出现在 left_team
##   2. footprint cells 被写入 grid pathing map (后续单位寻路绕开)
##   3. team_resources 扣减 = barracks cost (200 - 100 = 100 剩)
##   4. player_commands_log append 1 条 success entry
##   5. 同一位置再放第二个 barracks 应失败 (cells_occupied / cells_blocked) →
##      第二条 entry success=false; resources 不再扣减
##   6. 在 build_zone 之外放置 → 第三条 entry success=false reason=out_of_build_zone
##
## 不验证 (留给 smoke_player_command_production):
##   - 兵营后续生产单位
##   - 生产单位走 SpawnLane / 与敌人交战
##
## 不验证 (留给 smoke_crystal_tower_win):
##   - 胜负判定改写 (本 smoke 双方都没 crystal_tower 配置 → 走 fallback 全灭判定)
##
## 设计:
##   - 自建轻量 Node2D host + RtsBattleGrid (不带障碍, 让 placement 自由)
##   - 左方 team_config: build_zone = Rect2(50, 50, 400, 200), starting_resources=200
##   - 右方 team_config: 默认 (无 build_zone 限制); 给右方 1 sentinel unit 让 fallback team-wipeout 不立刻 right_lost
##   - 双方都有占位 actor + 无 controller → 都 idle 不动, 战斗在 PLACE_TICK 之前不会自然结束
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 42

const MAP_WIDTH: float = 500.0
const MAP_HEIGHT: float = 500.0

const PLACE_TICK: int = 30
const STARTING_RESOURCES: int = 200
const BARRACKS_COST: int = 100  # 与 RtsBuildingConfig._BARRACKS_STATS.cost 同步

const PLACE_POS_OK: Vector2 = Vector2(150.0, 200.0)
const PLACE_POS_OUT_OF_ZONE: Vector2 = Vector2(50.0, 400.0)  # y=400 在 build_zone (50, 50, 400, 200) 之外


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null


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

	# Team config: 左方 build_zone (50, 50) ~ (450, 250); resources = 200
	var left_team_cfg := RtsTeamConfig.create(0, "human", STARTING_RESOURCES, Rect2(50.0, 50.0, 400.0, 200.0))
	# 右方默认: 无 build_zone, resources = 0; 不放任何 actor → fallback 全灭判定会让 right 立刻 lost
	var right_team_cfg := RtsTeamConfig.unconfigured(1)

	# 双方各 1 sentinel — 确保 fallback team-wipeout 模式下战斗不立刻结束
	# (sentinel 都没 controller → 永远 idle 不动, 不互殴)
	var left_sentinel := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	left_sentinel.set_team_id(0)
	_world.add_actor(left_sentinel)
	left_sentinel.position_2d = Vector2(50.0, 100.0)
	left_sentinel.stance = RtsUnitActor.Stance.HOLD_FIRE

	var right_sentinel := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	right_sentinel.set_team_id(1)
	_world.add_actor(right_sentinel)
	right_sentinel.position_2d = Vector2(450.0, 450.0)
	right_sentinel.stance = RtsUnitActor.Stance.HOLD_FIRE

	var left_actors: Array[RtsBattleActor] = [left_sentinel]
	var right_actors: Array[RtsBattleActor] = [right_sentinel]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": {},  # 没 controller, sentinel 不动 (Idle)
		"team_configs": { 0: left_team_cfg, 1: right_team_cfg },
		"rng_seed": RNG_SEED,
	})

	# Phase 1: 放置 OK 命令 — tick_stamp=30
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		PLACE_TICK, 0, RtsBuildingConfig.KIND_BARRACKS, PLACE_POS_OK,
	))

	# Phase 2: 立即再放一个同位置兵营 — 应该 fail (cells 已占)
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		PLACE_TICK, 0, RtsBuildingConfig.KIND_BARRACKS, PLACE_POS_OK,
	))

	# Phase 3: 放置在 build_zone 之外 — 应该 fail (out_of_build_zone)
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		PLACE_TICK, 0, RtsBuildingConfig.KIND_BARRACKS, PLACE_POS_OUT_OF_ZONE,
	))

	# 跑到刚好 PLACE_TICK 那一帧 (含): 第 PLACE_TICK 次 tick_once 时 _current_tick=PLACE_TICK,
	# step 1.5 apply_due 拿到 3 条全部 due 命令并应用; sentinel 都 HOLD_FIRE 不互攻 → 战斗不结束
	for tick_i in range(PLACE_TICK):
		_procedure.tick_once()
		if _procedure.should_end():
			_fail("battle ended unexpectedly at tick %d (sentinels should keep both teams alive)" % _procedure.get_current_tick())
			return

	_procedure.finish()

	# ===== 验证 =====
	var log: Array[Dictionary] = _procedure.get_player_commands_log()
	if log.size() != 3:
		_fail("expected 3 player_commands_log entries (1 ok + 2 fail), got %d" % log.size())
		return

	# Entry 0: 应该 success
	var entry0 := log[0]
	var result0: Dictionary = entry0.get("result", {})
	if not result0.get("success", false):
		_fail("entry0 expected success=true, got reason=%s" % str(result0.get("reason", "")))
		return
	if not result0.has("actor_id"):
		_fail("entry0 success but missing actor_id")
		return
	var placed_id: String = str(result0["actor_id"])

	# Entry 1: 应该 fail (cells_occupied_by_actors 或 cells_blocked)
	var entry1 := log[1]
	var result1: Dictionary = entry1.get("result", {})
	if result1.get("success", false):
		_fail("entry1 should fail (same position) but got success")
		return
	var reason1: String = str(result1.get("reason", ""))
	if reason1 != "cells_blocked" and reason1 != "cells_occupied_by_actors":
		_fail("entry1 expected cells_blocked or cells_occupied_by_actors, got %s" % reason1)
		return

	# Entry 2: 应该 fail (out_of_build_zone)
	var entry2 := log[2]
	var result2: Dictionary = entry2.get("result", {})
	if result2.get("success", false):
		_fail("entry2 should fail (out of zone) but got success")
		return
	if str(result2.get("reason", "")) != "out_of_build_zone":
		_fail("entry2 expected out_of_build_zone, got %s" % result2.get("reason", ""))
		return

	# Resources: 仅扣一次 cost (entry0 成功)
	var remaining: int = _procedure.get_team_resources(0)
	if remaining != STARTING_RESOURCES - BARRACKS_COST:
		_fail("expected resources %d after 1 placement, got %d" % [
			STARTING_RESOURCES - BARRACKS_COST, remaining,
		])
		return

	# 建筑实例存在 + footprint cells blocking
	var placed_actor: Actor = _world.get_actor(placed_id)
	if placed_actor == null or not (placed_actor is RtsBuildingActor):
		_fail("placed actor missing or wrong type")
		return
	var placed_building := placed_actor as RtsBuildingActor
	if placed_building.is_dead():
		_fail("placed building immediately dead — unexpected")
		return
	if placed_building.position_2d.distance_to(PLACE_POS_OK) > 1.0:
		_fail("placed building position drift: %s vs %s" % [str(placed_building.position_2d), str(PLACE_POS_OK)])
		return

	var footprint: Array = placed_building.get_footprint_cells(_grid)
	for c in footprint:
		var coord := c as HexCoord
		if not _grid.model.is_tile_blocking(coord):
			_fail("placed building footprint cell %s NOT blocking" % coord.to_key())
			return

	# 应该已加入 left_team
	var found_in_team: bool = false
	for a in _procedure.left_team:
		if a.get_id() == placed_id:
			found_in_team = true
			break
	if not found_in_team:
		_fail("placed building NOT added to left_team")
		return

	# 报告
	print("rts player_command smoke: ticks=%d log_entries=%d resources_remaining=%d placed_id=%s" % [
		_procedure.get_current_tick(), log.size(), remaining, placed_id,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - placement command applied, dup/out-of-zone rejected, resources deducted")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
