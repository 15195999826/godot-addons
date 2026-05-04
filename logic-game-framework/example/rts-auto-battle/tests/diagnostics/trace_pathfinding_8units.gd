## Diagnostic trace: 8 melee 走到三 barracks 中央凹槽,dump 完整轨迹 + 异常检测
##
## 复刻 demo_rts_pathfinding 起手 layout: 8 unit @ y∈{380,420}, 3 barracks @ (250,200)/(350,280)/(450,180)
## 命令: 全选 → 右键 (350, 230) (3 barracks 形心,凹槽位置)
## 跑 12 秒 procedure tick (240 ticks @ 50ms),每 4 tick dump 一次状态
## 检测: pairwise overlap / 抖动 (velocity 反向) / 卡死 (≥ 2s 没移动)
##
## 不是 PASS/FAIL smoke — 是 dump 工具,跑完打印数据让人读。
## 用途: M6/M7/M8 推进时复测 group movement 视觉穿模 / 互相挤撞趋势,
##      跟 baseline (M5 末态) 对比 overlap event 数 / max_overlap 是否改善。
##
## M5 末态 baseline 输出(2026-05-04 测,参考):
##   Overlaps: 389 events
##   bucket [0-39]   起手离开: 83 events, max_overlap=8.73 px
##   bucket [40-119] 中途绕行: 266 events, max_overlap=9.45 px (~39% diameter 重叠)
##   bucket [120-199] 接近聚拢: 40 events, max_overlap=7.94 px
##   bucket [200+]   终点稳定: 0 events
##   Jitter: 1 event / Stuck: 0 event
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 12.0
const MAX_TICKS: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
const DUMP_EVERY_N_TICKS: int = 4   # 200ms

const TARGET_POS: Vector2 = Vector2(350.0, 230.0)

const TEAM0_START_POSITIONS: Array[Vector2] = [
	Vector2(50.0, 380.0), Vector2(80.0, 380.0), Vector2(110.0, 380.0), Vector2(140.0, 380.0),
	Vector2(50.0, 420.0), Vector2(80.0, 420.0), Vector2(110.0, 420.0), Vector2(140.0, 420.0),
]

const OBSTACLE_POSITIONS: Array[Vector2] = [
	Vector2(250.0, 200.0),
	Vector2(350.0, 280.0),
	Vector2(450.0, 180.0),
]

const DUMMY_BARRACKS_POS: Vector2 = Vector2(590.0, 470.0)


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null

var _unit_ids: Array[String] = []
var _controllers: Dictionary = {}

# 轨迹 [(tick, [(uid, x, y, vx, vy), ...]), ...]
var _trace: Array = []

# 异常计数
var _overlap_events: Array = []         # [(tick, uid_a, uid_b, dist, min_dist)]
var _jitter_events: Array = []          # [(tick, uid, prev_v, cur_v, dot)]
var _stuck_events: Array = []           # [(tick, uid, stuck_since_tick)]

# 上 tick velocity
var _prev_vel: Dictionary = {}          # uid → Vector2
# 卡死检测: 连续 tick position 几乎不变
var _stuck_since: Dictionary = {}       # uid → tick (开始几乎不动的 tick); 不存在 = 不卡


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

	# 3 obstacle barracks + 1 dummy
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	for ob_pos in OBSTACLE_POSITIONS:
		var ob := RtsBuildings.create_barracks()
		ob.set_team_id(1)
		_world.add_actor(ob)
		ob.position_2d = ob_pos
		ob.sync_obstruction_shape()
		right_actors.append(ob)

	var dummy := RtsBuildings.create_barracks()
	dummy.set_team_id(1)
	_world.add_actor(dummy)
	dummy.position_2d = DUMMY_BARRACKS_POS
	dummy.sync_obstruction_shape()
	right_actors.append(dummy)

	# 8 melee
	for sp in TEAM0_START_POSITIONS:
		var unit := _spawn_unit(sp)
		left_actors.append(unit)
		_unit_ids.append(unit.get_id())

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"rng_seed": 42,
	})

	# Enqueue MoveUnitsCommand 让 8 unit 走到 (350, 230)
	var cmd := RtsMoveUnitsCommand.new(0, 0, _unit_ids.duplicate(), TARGET_POS)
	_procedure.enqueue_player_command(cmd)

	# 主循环
	for tick in range(MAX_TICKS):
		_procedure.tick_once()
		_check_anomalies(tick)
		if tick % DUMP_EVERY_N_TICKS == 0:
			_dump_state(tick)

	_print_report()
	_world.end()
	GameWorld.destroy()
	get_tree().quit(0)


func _spawn_unit(pos: Vector2) -> RtsUnitActor:
	var actor := RtsUnitActor.new(Config.UnitClass.MELEE)
	actor.set_team_id(0)
	_world.add_actor(actor)
	actor.position_2d = pos
	actor.stance = RtsUnitActor.Stance.HOLD_FIRE

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(actor, _battle_map.grid)

	var strategy := RtsAIStrategyFactory.get_strategy(Config.UnitClass.MELEE)
	var controller := RtsUnitController.new(actor, agent, strategy)
	_controllers[actor.get_id()] = controller
	return actor


func _check_anomalies(tick: int) -> void:
	var alive_units: Array = []
	for uid in _unit_ids:
		var u := _world.get_actor(uid) as RtsUnitActor
		if u != null and not u.is_dead():
			alive_units.append(u)

	# 1) Pairwise overlap
	for i in range(alive_units.size()):
		for j in range(i + 1, alive_units.size()):
			var a := alive_units[i] as RtsUnitActor
			var b := alive_units[j] as RtsUnitActor
			var dist: float = a.position_2d.distance_to(b.position_2d)
			var min_dist: float = a.collision_radius + b.collision_radius
			if dist < min_dist - 0.01:
				_overlap_events.append([tick, a.get_id(), b.get_id(), dist, min_dist])

	# 2) 抖动 (velocity 跟上 tick 反向 dot < -0.5 且 magnitude > 0.1*move_speed)
	for u in alive_units:
		var uid: String = u.get_id()
		var cur_v: Vector2 = u.velocity if u.has_method("get") else Vector2.ZERO
		# RtsUnitActor.velocity 直接字段访问
		cur_v = u.velocity
		if _prev_vel.has(uid) and cur_v.length() > 30.0 and _prev_vel[uid].length() > 30.0:
			var prev: Vector2 = _prev_vel[uid]
			var d: float = cur_v.normalized().dot(prev.normalized())
			if d < -0.5:
				_jitter_events.append([tick, uid, prev, cur_v, d])
		_prev_vel[uid] = cur_v

	# 3) 卡死 (≥ 40 ticks = 2s position 累计变化 < 5px)
	# 简化: 跟前 40 tick 比较位置
	if tick >= 40:
		var trace_idx: int = (tick - 40) / DUMP_EVERY_N_TICKS
		if trace_idx >= 0 and trace_idx < _trace.size():
			var prev_snap: Array = _trace[trace_idx][1]
			var prev_map: Dictionary = {}
			for entry in prev_snap:
				prev_map[entry[0]] = Vector2(entry[1], entry[2])
			for u in alive_units:
				var uid: String = u.get_id()
				if prev_map.has(uid):
					var moved: float = u.position_2d.distance_to(prev_map[uid])
					var target_dist: float = u.position_2d.distance_to(TARGET_POS)
					if moved < 5.0 and target_dist > 50.0 and not _stuck_since.has(uid):
						_stuck_events.append([tick, uid, tick - 40])
						_stuck_since[uid] = tick


func _dump_state(tick: int) -> void:
	var snap: Array = []
	for uid in _unit_ids:
		var u := _world.get_actor(uid) as RtsUnitActor
		if u == null or u.is_dead():
			continue
		var v: Vector2 = u.velocity
		snap.append([uid, u.position_2d.x, u.position_2d.y, v.x, v.y])
	_trace.append([tick, snap])


func _print_report() -> void:
	print("")
	print("=== 8-unit move trace (target=%s) ===" % TARGET_POS)
	print("Total ticks=%d, snapshots=%d" % [MAX_TICKS, _trace.size()])

	# 起手 + 末态
	if _trace.size() > 0:
		var first: Array = _trace[0][1]
		var last: Array = _trace[_trace.size() - 1][1]
		print("\n--- 起手位置 (tick=%d) ---" % _trace[0][0])
		for entry in first:
			print("  %s @ (%.1f, %.1f)" % [entry[0], entry[1], entry[2]])
		print("\n--- 末态位置 (tick=%d) ---" % _trace[_trace.size() - 1][0])
		for entry in last:
			var dist_to_target: float = Vector2(entry[1], entry[2]).distance_to(TARGET_POS)
			print("  %s @ (%.1f, %.1f) dist_to_target=%.1f" % [entry[0], entry[1], entry[2], dist_to_target])

	print("\n--- 异常 ---")
	print("Overlaps: %d events" % _overlap_events.size())
	# Bucket by tick range + max overlap per bucket
	var buckets: Dictionary = {0: [0, 0.0], 40: [0, 0.0], 120: [0, 0.0], 200: [0, 0.0]}
	var max_overlap: float = 0.0
	var max_overlap_line: String = ""
	for e in _overlap_events:
		var t: int = e[0]
		var ov: float = e[4] - e[3]
		var bucket: int = 0
		if t < 40: bucket = 0
		elif t < 120: bucket = 40
		elif t < 200: bucket = 120
		else: bucket = 200
		buckets[bucket][0] += 1
		if ov > buckets[bucket][1]:
			buckets[bucket][1] = ov
		if ov > max_overlap:
			max_overlap = ov
			max_overlap_line = "tick=%d %s↔%s dist=%.2f min=%.2f overlap=%.2f" % [t, e[1], e[2], e[3], e[4], ov]
	print("  bucket [0-39]   起手离开: %d events, max_overlap=%.2f px" % [buckets[0][0], buckets[0][1]])
	print("  bucket [40-119] 中途绕行: %d events, max_overlap=%.2f px" % [buckets[40][0], buckets[40][1]])
	print("  bucket [120-199] 接近聚拢: %d events, max_overlap=%.2f px" % [buckets[120][0], buckets[120][1]])
	print("  bucket [200+]   终点稳定: %d events, max_overlap=%.2f px" % [buckets[200][0], buckets[200][1]])
	print("  全局 max_overlap: %s" % max_overlap_line)
	print("Jitter (velocity 跨 tick 反向): %d events" % _jitter_events.size())
	if _jitter_events.size() > 0:
		print("  样本(前 10):")
		for k in range(mini(10, _jitter_events.size())):
			var e: Array = _jitter_events[k]
			print("    tick=%d %s prev=%s cur=%s dot=%.2f" % [
				e[0], e[1], e[2], e[3], e[4],
			])
	print("Stuck (≥2s 没移动): %d events" % _stuck_events.size())
	if _stuck_events.size() > 0:
		for e in _stuck_events:
			print("    tick=%d %s stuck_since_tick=%d" % [e[0], e[1], e[2]])

	# 完整轨迹 (CSV-style)
	print("\n--- 完整轨迹 (每 200ms 一行,CSV: tick,uid,x,y,vx,vy) ---")
	for snap_entry in _trace:
		var t: int = snap_entry[0]
		var snap: Array = snap_entry[1]
		for entry in snap:
			print("%d,%s,%.1f,%.1f,%.1f,%.1f" % [t, entry[0], entry[1], entry[2], entry[3], entry[4]])
