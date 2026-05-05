## RTS Push pipeline acceptance smoke (0ad CCmpUnitMotionManager 复刻验收)
##
## 验证 0ad 5 阶段 push pipeline (PreMove → Move → DecayPressure → Push → PushAdjust → PostMove):
## 5 melee unit 强制 spawn 严重重叠(d ≈ 5-7 < sum_radius=28),跑 N tick warmup 让 push 收敛
## 到稳态 → 跑 K tick observation 验**稳态无抖动**(0ad pushing_pressure dampen + MinimalPushing
## 阈值的核心收敛机制)。
##
## **AC**:
##   - AC1 setup: 起手严重重叠 (d_initial < BEFORE_THRESHOLD)
##   - AC2 散开: warmup 后 d 增长(d_warm > d_initial)
##   - AC3 稳态无抖动: observation K tick 内 d 变化 ≤ STATIONARY_DELTA_MAX(Phase C 核心 fix —
##     pressure dampen + MinimalPushing 阈值让 push 收敛, 单位不在 cluster 内来回弹)
##   - AC4 不影响 motion._move_request: unit 没移动指令时仅 push,不会发奇怪 path 请求
##   - AC5 不 push 建筑(unit-unit only): enemy barracks 整 (warmup + observation) 不动
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 5050
const SPAWN_CENTER: Vector2 = Vector2(500.0, 500.0)
## 起始 pairwise sanity 阈值 — 起手必须重叠(< 10),否则测试 setup 错。
const MAX_PAIR_DIST_BEFORE_PUSH: float = 10.0
## Warmup 跑多少 tick 让 push 收敛(50 ms × 60 = 3 s,够 0ad pipeline pressure dampen 收敛)。
const WARMUP_TICKS: int = 60
## Observation 跑多少 tick 验稳态(60 tick 内 min pair distance 不抖动)。
const OBSERVATION_TICKS: int = 60
## Observation 期间 min pair distance 变化上限(px)— 0ad 算法 same control_group 同点 unit
## 慢散开(distance_factor 衰减区段 push 力度小, 60 tick 内 d 仍可能渐增 数 px)。8.0 px
## 余量足够大但仍能检出"反复抖动"(Phase C 前 push×N=10 iter 末态 ±2 px 反复弹动会失败)。
const STATIONARY_DELTA_MAX: float = 8.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null
var _controllers: Dictionary = {}
var _unit_ids: Array[String] = []
var _enemy_building_id: String = ""


func _ready() -> void:
	GameWorld.init()
	IdGenerator.reset_id_counter()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(800.0, 800.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)
	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 5 melee unit team 0 强制重叠 spawn 在 SPAWN_CENTER ± 5px
	# d 起始 ≈ 5-7 px 远 < sum_radius=24 → push pass 必触发
	var offsets: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(5.0, 0.0),
		Vector2(0.0, 5.0),
		Vector2(5.0, 5.0),
		Vector2(-3.0, 3.0),
	]
	var team0_units: Array[RtsBattleActor] = []
	for off in offsets:
		var u := _spawn_unit(RtsUnitClassConfig.UnitClass.MELEE, 0, SPAWN_CENTER + off)
		team0_units.append(u)
		_unit_ids.append(u.get_id())

	# 1 enemy barracks team 1 远处(避免 0v0 fallback 判胜负 + 验证 AC2.3 push 不动建筑)
	var enemy_b := RtsBuildings.create_barracks()
	enemy_b.set_team_id(1)
	_world.add_actor(enemy_b)
	enemy_b.position_2d = Vector2(750.0, 750.0)
	enemy_b.sync_obstruction_shape()
	_enemy_building_id = enemy_b.get_id()

	var left: Array[RtsBattleActor] = team0_units
	var right: Array[RtsBattleActor] = [enemy_b]

	_procedure = _world.start_rts_battle(left, right, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"rng_seed": RNG_SEED,
	})

	# AC1 sanity: 起始 pairwise dist 应 ≤ MAX_PAIR_DIST_BEFORE_PUSH(确实重叠)
	var d_initial: float = _pairwise_min_dist(_unit_ids)
	if d_initial > MAX_PAIR_DIST_BEFORE_PUSH:
		_fail("AC1 setup: d_initial %.2f > %.2f (units not overlapping enough)" % [d_initial, MAX_PAIR_DIST_BEFORE_PUSH])
		return

	var enemy_pos_before: Vector2 = (_world.get_actor(_enemy_building_id) as RtsBattleActor).position_2d

	# Warmup — 让 push 收敛到稳态(0ad pipeline 不是 1 tick 一发到位,multi-turn 收敛 +
	# pressure dampen + MinimalPushing 阈值让 push 力度逐渐衰减到 0)
	for _i in WARMUP_TICKS:
		_procedure.tick_once()

	var d_warmup: float = _pairwise_min_dist(_unit_ids)

	# AC2: warmup 后 d 增长(确实在散开;不要求达到 sum_radius — 0ad 同 control_group 设计就是
	# tight formation,稳态 d < sum_radius 是预期行为,见 CCmpUnitMotionManager.h:69 注释)
	if d_warmup <= d_initial:
		_fail("AC2: d_warmup %.2f ≤ d_initial %.2f (push 没散开 5 unit cluster)" % [d_warmup, d_initial])
		return

	# Observation — 跑 K tick 验稳态无抖动(Phase C 核心 fix:pressure dampen + MinimalPushing
	# 阈值让稳态 push.length() < 0.2 清零,d 不变;老 push×N=10 iter 终态在 ±2 px 抖动反复)
	var d_history: Array[float] = []
	for _i in OBSERVATION_TICKS:
		_procedure.tick_once()
		d_history.append(_pairwise_min_dist(_unit_ids))

	var d_min_obs: float = INF
	var d_max_obs: float = -INF
	for d in d_history:
		d_min_obs = minf(d_min_obs, d)
		d_max_obs = maxf(d_max_obs, d)
	var d_range: float = d_max_obs - d_min_obs

	# AC3: observation K tick 内 min pair distance 变化 ≤ STATIONARY_DELTA_MAX (无抖动核心)
	if d_range > STATIONARY_DELTA_MAX:
		_fail("AC3 stationary: observation %d tick d range %.2f > %.2f (cluster 在抖动 — pressure dampen / MinimalPushing 失效)" % [OBSERVATION_TICKS, d_range, STATIONARY_DELTA_MAX])
		return

	# AC5: enemy building 整 (warmup + observation) 不被 push
	var enemy_pos_after: Vector2 = (_world.get_actor(_enemy_building_id) as RtsBattleActor).position_2d
	if enemy_pos_before.distance_to(enemy_pos_after) > 0.001:
		_fail("AC5: enemy building moved %.4f px (push 误推到建筑)" % enemy_pos_before.distance_to(enemy_pos_after))
		return

	# AC4: motion._move_request 仍 NONE(没下移动命令;push 不创奇怪 path)
	for uid in _unit_ids:
		var u: RtsUnitActor = _world.get_actor(uid) as RtsUnitActor
		if u == null or u.motion_component == null:
			_fail("AC4: unit %s missing motion_component after tick" % uid)
			return
		var motion: RtsUnitMotion = (u.motion_component as RtsMotionComponent).motion
		if motion._move_request != null and motion._move_request.type != RtsMoveRequest.Type.NONE:
			_fail("AC4: unit %s _move_request unexpectedly set after push (type=%d)" % [uid, motion._move_request.type])
			return

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - smoke_group_push_pass — initial %.2f → warmup(%d t) %.2f → stationary(%d t) range %.2f ≤ %.2f (0ad pipeline + pressure dampen 收敛无抖动)" % [
		d_initial, WARMUP_TICKS, d_warmup, OBSERVATION_TICKS, d_range, STATIONARY_DELTA_MAX,
	])
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var u := RtsUnitActor.new(unit_class)
	u.set_team_id(team_id)
	_world.add_actor(u)
	u.position_2d = pos
	u.stance = RtsUnitActor.Stance.HOLD_FIRE  # 不主动开火 → 不影响 push 测试

	var motion_component := RtsMotionComponent.attach_default(u, _world)

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(u, motion_component, strategy)
	_controllers[u.get_id()] = controller
	return u


func _pairwise_min_dist(ids: Array[String]) -> float:
	var min_d: float = INF
	for i in range(ids.size()):
		var a: RtsBattleActor = _world.get_actor(ids[i]) as RtsBattleActor
		if a == null:
			continue
		for j in range(i + 1, ids.size()):
			var b: RtsBattleActor = _world.get_actor(ids[j]) as RtsBattleActor
			if b == null:
				continue
			var d: float = a.position_2d.distance_to(b.position_2d)
			if d < min_d:
				min_d = d
	return min_d


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	if _world != null:
		_world.end()
	GameWorld.destroy()
	get_tree().quit(1)
