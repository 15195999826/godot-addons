## RTS steering smoke (P2.2 acceptance) — 8 单位同向同终点不重叠
##
## 验证 RtsSpatialHash + RtsUnitSteering 配合 nav agent 的"compute_velocity → steering →
## integrate" 三段管线 (P2.2 procedure step 4 同构):
##   1. 8 个 melee 单位起始位置全部塞在 (250, 250) 附近 (0.5px 圆 — 几乎重合);
##   2. 全部 agent.set_target((450, 450)) 同终点;
##   3. 跑 200 个 tick (每 tick 内驱动同 procedure step 4 的三段);
##   4. 主断言: 任意两单位距离 ≥ collision_radius * 2 - tolerance — 不重叠;
##   5. 辅助断言: 多数单位实际向终点方向移动了 (path_length_traveled > 50 像素);
##
## 与 smoke_rts_auto_battle 的差异:
##   - 4v4 主 smoke: 端到端 procedure-driven, 全 stack (controller / strategy / activity / nav /
##     spatial / steering / integrate) 都跑, 但 8 单位场景只是局部边界
##   - steering smoke: 直接驱动 P2.2 新模块 (spatial_hash + steering + nav 拆分接口) 跑 8 单位
##     converging-on-same-target 场景 — 这正是 separation 力的"压力测试", 主 smoke 里没有这种密度
##
## 与 smoke_minimal_push_out 的差异:
##   - push-out smoke: 测纯静态算法 (RtsMinimalPushOut.resolve), 单位不主动 nav 推进
##   - steering smoke: 测**完整 movement pipeline**, 单位边走边互相避让
##
## 不接 procedure / strategy / controller — 那一层在 smoke_rts_auto_battle 里覆盖。这里隔离测
## P2.2 的三个新模块 (spatial_hash / steering / nav 两段拆分)。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const TICK_DT_SEC: float = TICK_INTERVAL_MS / 1000.0
const MAX_TICKS: int = 200

## 容差 (px), 与 smoke_minimal_push_out 一致 — 浮点抖动余量。
const TOLERANCE: float = 0.5

const UNIT_COUNT: int = 8


var _world: RtsWorldGameplayInstance = null
var _battle_map: RtsBattleMap = null
var _agents: Array[RtsNavAgent] = []
var _units: Array[RtsUnitActor] = []
var _spatial_hash: RtsSpatialHash = null


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_battle_map.grid)

	# 8 单位塞在 (100, 100) 附近 — 0.5 px 圆 (按 45° 间隔分布), 几乎完全重合
	# 起点选 (100, 100) 在 cell (3, 3), 完全在中央障碍 (cells 6..9, 6..9) 外;
	# 终点 (400, 100) 在 cell (12, 3), 同 row → 路径 clear 不需要绕障碍 (单测 steering 不测寻路)
	var center := Vector2(100.0, 100.0)
	var target_pos := Vector2(400.0, 100.0)
	for i in range(UNIT_COUNT):
		var angle: float = float(i) * (TAU / float(UNIT_COUNT))
		var offset: Vector2 = Vector2.from_angle(angle) * 0.5
		var pos: Vector2 = center + offset
		_spawn_unit(pos, target_pos)

	# 验证默认 collision_radius (melee = 12 → 2r=24)
	if _units[0].collision_radius != 12.0:
		_fail("expected MELEE collision_radius=12.0, got %f" % _units[0].collision_radius)
		return

	_spatial_hash = RtsSpatialHash.new()

	# 主循环: 每 tick = procedure step 4 三段 (spatial_hash + compute + steering + integrate)
	for tick in range(MAX_TICKS):
		var alive: Array = []
		for u in _units:
			alive.append(u)
		_spatial_hash.update_all(alive)

		# Step 4a: 写 desired velocity
		for i in range(_units.size()):
			_agents[i].compute_desired_velocity(TICK_DT_SEC)

		# Step 4b: steering 修改 velocity (separation + deflection)
		for i in range(_units.size()):
			RtsUnitSteering.apply(_units[i], _spatial_hash, _world, TICK_DT_SEC)

		# Step 4c: integrate position += velocity * dt
		for i in range(_units.size()):
			_agents[i].integrate(TICK_DT_SEC)

	# ===== 主断言: 任意两单位距离 ≥ collision_radius * 2 - tolerance =====
	var min_required: float = _units[0].collision_radius * 2.0 - TOLERANCE  # = 23.5 (melee)
	for i in range(_units.size()):
		for j in range(i + 1, _units.size()):
			var dist := _units[i].position_2d.distance_to(_units[j].position_2d)
			if dist < min_required:
				_fail("units[%d] and units[%d] too close: dist=%.4f < %.4f (2r=%.1f); positions=%s vs %s" % [
					i, j, dist, min_required, _units[0].collision_radius * 2.0,
					_units[i].position_2d, _units[j].position_2d,
				])
				return

	# ===== 辅助断言: 多数单位实际向终点方向移动了 =====
	var movers: int = 0
	var total_traveled: float = 0.0
	for agent in _agents:
		total_traveled += agent.path_length_traveled
		if agent.path_length_traveled > 50.0:
			movers += 1
	if movers < 6:
		_fail("only %d / %d units traveled > 50 px (steering 让所有单位卡住?)" % [movers, UNIT_COUNT])
		return

	# 计算最终位置散布范围
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for unit in _units:
		min_x = min(min_x, unit.position_2d.x)
		max_x = max(max_x, unit.position_2d.x)
		min_y = min(min_y, unit.position_2d.y)
		max_y = max(max_y, unit.position_2d.y)
	var spread_x: float = max_x - min_x
	var spread_y: float = max_y - min_y

	print("steering smoke: min_pair_dist OK; movers=%d/%d; total_traveled=%.1f px; final_spread=(%.1f, %.1f); buckets=%d" % [
		movers, UNIT_COUNT, total_traveled, spread_x, spread_y, _spatial_hash.get_bucket_count(),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 8 converging units stay separated (>= 2r - %.1f)" % TOLERANCE)
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(pos: Vector2, target_pos: Vector2) -> void:
	var unit := RtsUnitActor.new(Config.UnitClass.MELEE)
	unit.set_team_id(0)
	_world.add_actor(unit)
	unit.position_2d = pos
	_units.append(unit)

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(unit, _battle_map.grid)
	agent.set_target(target_pos)
	_agents.append(agent)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
