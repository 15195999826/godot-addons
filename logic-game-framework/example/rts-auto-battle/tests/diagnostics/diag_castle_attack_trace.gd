## 诊断 dump - 单位攻击 building 场景, trace 看是否徘徊/死循环重新 set_target/能否到 attack_range
##
## 复现 castle_war 类场景: 4 melee 走向 enemy crystal_tower, 看:
##   1. 单位 dist_to_target 是否单调下降到 attack_range 内 (正常接战)
##   2. 是否反复 set_target → A* 找不到路 → fallback _direct_path → 撞 footprint → repeat
##   3. attack_range 是否 ≤ building cell rect 边距 (打不到时)
##   4. clear_target / has_target 切换频率
##
## Trace fields per unit per tick:
##   tick, uid, px, py, vx, vy, vmag, has_target, path_size, path_empty, dist_to_target,
##   dist_to_building_edge, in_block, wants_attack, attack_count
extends Node


const TICK_INTERVAL_MS: float = 50.0
const MAX_TICKS: int = 300  # 15s
const TRACE_PATH: String = "user://diag_castle_attack_trace.csv"

const NUM_UNITS: int = 4
# crystal_tower position. 1×1 footprint → cell = (px/32, py/32). 注意非 cell-aligned!
const CT_POS: Vector2 = Vector2(420.0, 250.0)


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _agents: Dictionary = {}
var _controllers: Dictionary = {}
var _unit_ids: Array[String] = []
var _ct_id: String = ""
# CT footprint world rect
var _ct_rect: Rect2 = Rect2()

var _trace_lines: PackedStringArray = []
var _attack_count_per_unit: Dictionary = {}
# 检测 set_target 频率: trace 上 has_target false→true / path_size 变化次数
var _set_target_events: Dictionary = {}  # uid → count


func _ready() -> void:
	GameWorld.init()

	_grid = RtsBattleGrid.new(Vector2(600.0, 500.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# Enemy crystal_tower (打它判胜负, 作为 attack target)
	var ct := RtsBuildings.create_crystal_tower()
	ct.set_team_id(1)
	_world.add_actor(ct)
	ct.position_2d = CT_POS
	# 高血让它不被打死, 我们要观察接战阶段
	ct.attribute_set.set_hp_base(99999.0)
	_ct_id = ct.get_id()

	# 算 CT footprint 实际 rect (1×1 footprint, cell-aligned 与否取决于 CT_POS)
	var ct_cells: Array = ct.get_footprint_cells(_grid)
	if ct_cells.size() > 0:
		var coord := ct_cells[0] as HexCoord
		var cs := RtsBattleGrid.DEFAULT_CELL_SIZE
		_ct_rect = Rect2(float(coord.q) * cs, float(coord.r) * cs, cs, cs)

	# 4 melee, 起点散开
	for i in range(NUM_UNITS):
		var unit := _spawn_unit(0, Vector2(50.0, 200.0 + float(i) * 30.0))
		_unit_ids.append(unit.get_id())
		_attack_count_per_unit[unit.get_id()] = 0
		_set_target_events[unit.get_id()] = 0

	var left_cfg := RtsTeamConfig.create(0, "human", {}, Rect2())
	var right_cfg := RtsTeamConfig.create(1, "ai", {}, Rect2())

	var left_actors: Array[RtsBattleActor] = []
	for uid in _unit_ids:
		left_actors.append(_world.get_actor(uid) as RtsBattleActor)
	var right_actors: Array[RtsBattleActor] = [ct]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": 42,
		"event_sink": Callable(self, "_on_event_sink"),
	})

	# 让单位主动攻击 CT (override strategy)
	for uid in _unit_ids:
		var ctrl := _controllers[uid] as RtsUnitController
		ctrl.set_activity_chain(RtsAttackActivity.new(_ct_id), true)

	_trace_lines.append(
		"tick,uid,px,py,vx,vy,vmag,has_target,path_size,path_empty,dist_target,dist_edge,in_block,wants_attack,attack_count"
	)
	# 上一帧 has_target, 用于检测 false→true 跳变 (新 set_target)
	var prev_has_target: Dictionary = {}
	for uid in _unit_ids:
		prev_has_target[uid] = false

	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		_record_tick(tick_i, prev_has_target)
		if _procedure.should_end():
			break

	_procedure.finish()
	_print_summary()
	_save_trace()

	_world.end()
	GameWorld.destroy()
	get_tree().quit(0)


func _spawn_unit(team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	unit.set_team_id(team_id)
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


func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		if event.get("kind", "") == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			var src: String = event.get("source_actor_id", "")
			if _attack_count_per_unit.has(src):
				_attack_count_per_unit[src] = (_attack_count_per_unit[src] as int) + 1


func _record_tick(tick: int, prev_has_target: Dictionary) -> void:
	for uid in _unit_ids:
		var unit := _world.get_actor(uid) as RtsUnitActor
		if unit == null:
			continue
		var motion_component := _agents[uid] as RtsMotionComponent
		var ctrl := _controllers[uid] as RtsUnitController
		var pos := unit.position_2d
		var vel := unit.velocity
		var ct := _world.get_actor(_ct_id)
		var dist_target: float = pos.distance_to(ct.position_2d) if ct != null else -1.0
		var coord: HexCoord = _grid.world_to_coord(pos)
		var in_block: bool = false
		if _grid.has_tile(coord):
			in_block = _grid.model.is_tile_blocking(coord)

		var has_t: bool = motion_component.motion.has_target()
		var dist_edge: float = _signed_dist_to_rect(pos, _ct_rect)

		# 检测 set_target 跳变 (false→true)
		if has_t and not (prev_has_target[uid] as bool):
			_set_target_events[uid] = (_set_target_events[uid] as int) + 1
		prev_has_target[uid] = has_t

		# wants_attack: 从 controller.current_activity 取 (attack activity 才有)
		var wants_atk: bool = false
		if ctrl != null and ctrl.current_activity is RtsAttackActivity:
			wants_atk = (ctrl.current_activity as RtsAttackActivity).wants_to_attack()

		_trace_lines.append("%d,%s,%.2f,%.2f,%.3f,%.3f,%.3f,%s,%d,%s,%.2f,%.2f,%s,%s,%d" % [
			tick, uid, pos.x, pos.y, vel.x, vel.y, vel.length(),
			str(has_t), motion_component.motion._short_path.size(),
			str(motion_component.motion._short_path.is_empty()),
			dist_target, dist_edge, str(in_block), str(wants_atk),
			_attack_count_per_unit[uid] as int,
		])


func _signed_dist_to_rect(p: Vector2, r: Rect2) -> float:
	var dx: float = max(r.position.x - p.x, p.x - (r.position.x + r.size.x))
	var dy: float = max(r.position.y - p.y, p.y - (r.position.y + r.size.y))
	if dx <= 0.0 and dy <= 0.0:
		return max(dx, dy)
	dx = max(dx, 0.0)
	dy = max(dy, 0.0)
	return sqrt(dx * dx + dy * dy)


func _print_summary() -> void:
	print("=== diag_castle_attack_trace summary ===")
	print("CT_POS=%s ct_footprint_rect=%s ct_rect_center=(%.1f, %.1f)" % [
		CT_POS, _ct_rect, _ct_rect.position.x + _ct_rect.size.x * 0.5,
		_ct_rect.position.y + _ct_rect.size.y * 0.5,
	])
	# Bug 1 验证: position vs rect center 的偏差
	var ct_center: Vector2 = _ct_rect.position + _ct_rect.size * 0.5
	print("⚠ position_2d=%s vs footprint geometric center=%s OFFSET=%s" % [
		CT_POS, ct_center, CT_POS - ct_center,
	])
	print("trace lines: %d" % _trace_lines.size())
	print("")
	print("Per-unit summary (uid | final_pos | min_dist_to_target | attacks | set_target_events | path_empty_pct):")
	for uid in _unit_ids:
		var unit := _world.get_actor(uid) as RtsUnitActor
		var fpos := unit.position_2d if unit != null else Vector2.ZERO

		var min_dist: float = 1e9
		var path_empty_count: int = 0
		var data_rows: int = 0
		for line in _trace_lines:
			var parts := line.split(",")
			if parts.size() < 15 or parts[1] != uid:
				continue
			data_rows += 1
			min_dist = min(min_dist, float(parts[10]))
			if parts[9] == "true":
				path_empty_count += 1
		var pct: float = 0.0 if data_rows == 0 else (float(path_empty_count) / float(data_rows)) * 100.0
		print("%s | (%.1f,%.1f) | %.2f | %d | %d | %.1f%%" % [
			uid, fpos.x, fpos.y, min_dist,
			_attack_count_per_unit[uid] as int,
			_set_target_events[uid] as int,
			pct,
		])


func _save_trace() -> void:
	var f := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if f == null:
		print("WARN: failed to open %s" % TRACE_PATH)
		return
	for line in _trace_lines:
		f.store_line(line)
	f.close()
	print("trace CSV: %s" % ProjectSettings.globalize_path(TRACE_PATH))
