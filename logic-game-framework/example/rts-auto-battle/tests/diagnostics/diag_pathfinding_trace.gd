## 诊断 dump - 编队走向紧贴建筑后侧的目标, 逐 tick 录单位轨迹 / 路径状态 / 是否进 footprint。
##
## 不是 PASS/FAIL 测试 - 输出 trace CSV 给人分析, 用来定位:
##   1. 单位是否走进 building footprint (穿建筑)
##   2. 单位是否在建筑前 has_target=true 但 velocity≈0 (徘徊)
##   3. formation 中谁的目标点落在 footprint cell 内 / 边缘
##   4. A* path 是否为空 (find_path 找不到)
##
## Trace fields per unit per tick:
##   tick, uid, px, py, vx, vy, |v|, wp_idx, wp_size, has_target, in_blocking_cell,
##   final_tx, final_ty, dist_to_final, dist_to_building_edge, path_empty
##
## Map setup:
##   - 600x500 map
##   - 1 barracks @ (300, 250), 2x2 footprint cells (9,7),(10,7),(9,8),(10,8) → world rect [288, 224]..[352, 288]
##   - 6 melee 起始 (50, 200..300)
##   - 目标 (370, 250) - 紧贴 barracks footprint 右边缘 18px (formation spacing 30 → 部分单位的 final 落在 footprint 内)
extends Node


const TICK_INTERVAL_MS: float = 50.0
const MAX_TICKS: int = 240  # 12s
const TRACE_PATH: String = "user://diag_pathfinding_trace.csv"

const NUM_UNITS: int = 6
const TARGET_POS: Vector2 = Vector2(370.0, 250.0)
const BARRACKS_POS: Vector2 = Vector2(300.0, 250.0)
const BARRACKS_RECT: Rect2 = Rect2(288.0, 224.0, 64.0, 64.0)


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _agents: Dictionary = {}
var _controllers: Dictionary = {}
var _unit_ids: Array[String] = []
var _trace_lines: PackedStringArray = []
# 每 unit 累计速度近 0 的连续 tick 数 (徘徊判定)
var _stationary_ticks: Dictionary = {}


func _ready() -> void:
	GameWorld.init()

	_grid = RtsBattleGrid.new(Vector2(600.0, 500.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 1 个 enemy barracks 当障碍
	var barracks := RtsBuildings.create_barracks()
	barracks.set_team_id(1)
	_world.add_actor(barracks)
	barracks.position_2d = BARRACKS_POS

	# 6 melee, y 列状散布
	for i in range(NUM_UNITS):
		var unit := _spawn_unit(0, Vector2(50.0, 180.0 + float(i) * 28.0))
		_unit_ids.append(unit.get_id())
		_stationary_ticks[unit.get_id()] = 0

	var left_cfg := RtsTeamConfig.create(0, "human", {}, Rect2())
	var right_cfg := RtsTeamConfig.create(1, "ai", {}, Rect2())

	var left_actors: Array[RtsBattleActor] = []
	for uid in _unit_ids:
		left_actors.append(_world.get_actor(uid) as RtsBattleActor)
	var right_actors: Array[RtsBattleActor] = [barracks]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": 42,
	})

	# 玩家命令: tick 1 编队 → TARGET_POS
	_procedure.enqueue_player_command(RtsMoveUnitsCommand.new(
		1, 0, _unit_ids, TARGET_POS,
	))

	# CSV 头
	_trace_lines.append(
		"tick,uid,px,py,vx,vy,vmag,wp_idx,wp_size,has_target,in_block,final_tx,final_ty,dist_final,dist_building_edge,path_empty"
	)

	# 跑
	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		_record_tick(tick_i)
		if _procedure.should_end():
			break

	_procedure.finish()

	# 汇总
	_print_summary()
	_save_trace()

	_world.end()
	GameWorld.destroy()
	get_tree().quit(0)


func _spawn_unit(team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	unit.set_team_id(team_id)
	unit.stance = RtsUnitActor.Stance.HOLD_FIRE  # 不打人, 专注移动测试
	_world.add_actor(unit)
	unit.position_2d = pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)
	_agents[unit.get_id()] = motion_component

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(
		RtsUnitClassConfig.UnitClass.MELEE
	)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	_controllers[unit.get_id()] = controller
	return unit


func _record_tick(tick: int) -> void:
	for uid in _unit_ids:
		var unit := _world.get_actor(uid) as RtsUnitActor
		if unit == null or unit.is_dead():
			continue
		var motion_component := _agents[uid] as RtsMotionComponent
		var pos := unit.position_2d
		var vel := unit.velocity
		var vmag := vel.length()

		# 在 blocking cell 内?
		var coord: HexCoord = _grid.world_to_coord(pos)
		var in_block: bool = false
		if _grid.has_tile(coord):
			in_block = _grid.model.is_tile_blocking(coord)

		# final target 与抵达距离 (motion: 仅 POINT MoveRequest 有 final target)
		var has_t: bool = motion_component.motion.has_target()
		var final_t: Vector2 = Vector2.ZERO
		if has_t:
			var req: RtsMoveRequest = motion_component.motion._move_request
			if req != null and req.type == RtsMoveRequest.Type.POINT:
				final_t = req.position
		var dist_final: float = pos.distance_to(final_t) if has_t else -1.0
		var path_empty: bool = motion_component.motion._short_path.is_empty()

		# 距 building 矩形最近边的距离 (负 = 内部)
		var dist_edge: float = _signed_dist_to_rect(pos, BARRACKS_RECT)

		# 静止累计
		if vmag < 1.0 and has_t and dist_final > 4.0:
			_stationary_ticks[uid] = (_stationary_ticks[uid] as int) + 1
		else:
			_stationary_ticks[uid] = 0

		# M7d: motion 没 _waypoint_index 概念 (短 path 在 procedure 全局推进), 用 0 占位
		_trace_lines.append("%d,%s,%.2f,%.2f,%.3f,%.3f,%.3f,%d,%d,%s,%s,%.2f,%.2f,%.2f,%.2f,%s" % [
			tick, uid, pos.x, pos.y, vel.x, vel.y, vmag,
			0, motion_component.motion._short_path.size(),
			str(has_t), str(in_block),
			final_t.x, final_t.y, dist_final, dist_edge,
			str(path_empty),
		])


func _signed_dist_to_rect(p: Vector2, r: Rect2) -> float:
	var dx: float = max(r.position.x - p.x, p.x - (r.position.x + r.size.x))
	var dy: float = max(r.position.y - p.y, p.y - (r.position.y + r.size.y))
	if dx <= 0.0 and dy <= 0.0:
		# 内部 - 取距最近边的负距离
		return max(dx, dy)
	# 外部
	dx = max(dx, 0.0)
	dy = max(dy, 0.0)
	return sqrt(dx * dx + dy * dy)


func _print_summary() -> void:
	print("=== diag_pathfinding_trace summary ===")
	print("trace lines: %d (header + %d data rows)" % [_trace_lines.size(), _trace_lines.size() - 1])
	print("target=%s barracks=%s rect=%s" % [TARGET_POS, BARRACKS_POS, BARRACKS_RECT])
	print("")
	print("Per-unit summary:")
	print("uid | final_pos | dist_to_target | min_edge_dist | max_stationary_ticks | ever_in_block | path_empty_count")

	for uid in _unit_ids:
		var unit := _world.get_actor(uid) as RtsUnitActor
		var _motion_component := _agents[uid] as RtsMotionComponent
		var final_pos := unit.position_2d if unit != null else Vector2.ZERO
		var dist_to_t := final_pos.distance_to(TARGET_POS) if unit != null else -1.0

		# scan trace for this uid
		var min_edge: float = 1e9
		var max_stationary: int = 0
		var cur_stationary: int = 0
		var ever_in_block: bool = false
		var path_empty_count: int = 0
		for line in _trace_lines:
			if not line.begins_with(""):
				continue
			var parts := line.split(",")
			if parts.size() < 16:
				continue
			if parts[1] != uid:
				continue
			var edge_dist := float(parts[14])
			min_edge = min(min_edge, edge_dist)
			var vmag := float(parts[6])
			var has_t := parts[9] == "true"
			var dist_f := float(parts[13])
			if vmag < 1.0 and has_t and dist_f > 4.0:
				cur_stationary += 1
				max_stationary = max(max_stationary, cur_stationary)
			else:
				cur_stationary = 0
			if parts[10] == "true":
				ever_in_block = true
			if parts[15] == "true":
				path_empty_count += 1

		print("%s | (%.1f,%.1f) | %.2f | %.2f | %d | %s | %d" % [
			uid, final_pos.x, final_pos.y, dist_to_t, min_edge,
			max_stationary, str(ever_in_block), path_empty_count,
		])


func _save_trace() -> void:
	var f := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if f == null:
		print("WARN: failed to open %s for write" % TRACE_PATH)
		return
	for line in _trace_lines:
		f.store_line(line)
	f.close()
	# user:// 真实路径
	var real_path := ProjectSettings.globalize_path(TRACE_PATH)
	print("trace CSV saved: %s" % real_path)
