## 诊断 smoke - headless 复刻 demo_rts_frontend setup, trace 所有单位寻找徘徊场景
##
## 完全镜像 demo_rts_frontend.gd 的起手:
##   - 双方各 5 worker + 1 crystal_tower + 4 中立 resource_node
##   - AI vs AI (双方 attach computer player)
##   - 30s 运行, 每 5 tick 录一次单位状态
##
## 徘徊检测启发式:
##   - oscillation: 单位 set_target 频率高 (≥10 in 100 ticks)
##   - non_monotonic: dist_to_target 长时间不下降但 has_target=true
##   - cluster_jam: 多个单位集中在 ≤30px 半径, 累计 > 50 tick (clustering at building/node)
extends Node


const TICK_INTERVAL_MS: float = 50.0
const MAX_TICKS: int = 600  # 30s
const RECORD_EVERY_N_TICKS: int = 5
const TRACE_PATH: String = "user://diag_demo_frontend_trace.csv"

# 完全镜像 demo_rts_frontend.gd 的位置
const LEFT_BASE_X: float = 80.0
const RIGHT_BASE_X: float = 420.0
const NUM_WORKERS_PER_TEAM: int = 5
const WORKER_SPAWN_DELTA_Y: float = 30.0
const LEFT_WORKER_SPAWN_X: float = LEFT_BASE_X + 50.0
const RIGHT_WORKER_SPAWN_X: float = RIGHT_BASE_X - 50.0
const WORKER_SPAWN_BASE_Y: float = 200.0
const LEFT_CT_POS: Vector2 = Vector2(LEFT_BASE_X, 350.0)
const RIGHT_CT_POS: Vector2 = Vector2(RIGHT_BASE_X, 350.0)
const STARTING_GOLD_LEFT: int = 100
const STARTING_WOOD_LEFT: int = 100
const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 200.0, 400.0)

const LEFT_GOLD_NODES: Array[Vector2] = [Vector2(180, 220), Vector2(180, 280)]
const LEFT_WOOD_NODES: Array[Vector2] = [Vector2(180, 350), Vector2(180, 410)]
const RIGHT_GOLD_NODES: Array[Vector2] = [Vector2(320, 220), Vector2(320, 280)]
const RIGHT_WOOD_NODES: Array[Vector2] = [Vector2(320, 350), Vector2(320, 410)]


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _agents: Dictionary = {}
var _controllers: Dictionary = {}
var _tracked_unit_ids: Array[String] = []
var _trace_lines: PackedStringArray = []
var _set_target_events: Dictionary = {}  # uid → count of false→true transitions
var _prev_has_target: Dictionary = {}
var _prev_path_size: Dictionary = {}
var _path_change_events: Dictionary = {}  # uid → count of path_size changing while has_target


func _ready() -> void:
	GameWorld.init()

	_grid = RtsBattleGrid.new(Vector2(500.0, 500.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	# CTs
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = LEFT_CT_POS
	left_actors.append(left_ct)

	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = RIGHT_CT_POS
	right_actors.append(right_ct)

	# 5 workers per team
	for i in range(NUM_WORKERS_PER_TEAM):
		var lp := Vector2(LEFT_WORKER_SPAWN_X, WORKER_SPAWN_BASE_Y + WORKER_SPAWN_DELTA_Y * float(i))
		var lw := _spawn_unit(RtsUnitClassConfig.UnitClass.WORKER, 0, lp)
		left_actors.append(lw)
		var rp := Vector2(RIGHT_WORKER_SPAWN_X, WORKER_SPAWN_BASE_Y + WORKER_SPAWN_DELTA_Y * float(i))
		var rw := _spawn_unit(RtsUnitClassConfig.UnitClass.WORKER, 1, rp)
		right_actors.append(rw)

	# Resource nodes
	_spawn_nodes(LEFT_GOLD_NODES, true)
	_spawn_nodes(LEFT_WOOD_NODES, false)
	_spawn_nodes(RIGHT_GOLD_NODES, true)
	_spawn_nodes(RIGHT_WOOD_NODES, false)

	var left_cfg := RtsTeamConfig.create(
		0, "ai", {"gold": STARTING_GOLD_LEFT, "wood": STARTING_WOOD_LEFT}, LEFT_BUILD_ZONE,
	)
	var right_cfg := RtsTeamConfig.create(
		1, "ai", {"gold": STARTING_GOLD_LEFT, "wood": STARTING_WOOD_LEFT},
		Rect2(300, 50, 200, 400),
	)

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": 12345,
	})
	_procedure.attach_computer_player(0)
	_procedure.attach_computer_player(1)

	# Track all initial workers
	for a in left_actors:
		if a is RtsUnitActor:
			_register_tracking(a.get_id())
	for a in right_actors:
		if a is RtsUnitActor:
			_register_tracking(a.get_id())

	# CSV header
	_trace_lines.append(
		"tick,uid,team,kind,px,py,vx,vy,vmag,has_target,path_size,path_empty,final_tx,final_ty,dist_final,activity,atk_target_id,atk_target_alive,atk_tgt_x,atk_tgt_y,atk_dist,atk_range,current_target_id"
	)

	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		_track_new_spawns()
		if tick_i % RECORD_EVERY_N_TICKS == 0:
			_record_tick(tick_i)
		_update_event_counts()
		if _procedure.should_end():
			break

	_procedure.finish()
	_print_summary()
	_save_trace()

	_world.end()
	GameWorld.destroy()
	get_tree().quit(0)


func _register_tracking(uid: String) -> void:
	if _tracked_unit_ids.has(uid):
		return
	_tracked_unit_ids.append(uid)
	_set_target_events[uid] = 0
	_path_change_events[uid] = 0
	_prev_has_target[uid] = false
	_prev_path_size[uid] = 0


func _track_new_spawns() -> void:
	var actors: Array[RtsBattleActor] = _procedure.get_all_actors()
	for a: RtsBattleActor in actors:
		var uid: String = a.get_id()
		if _tracked_unit_ids.has(uid):
			continue
		if a is RtsUnitActor and _agents.has(uid):
			_register_tracking(uid)


func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	_world.add_actor(unit)
	unit.position_2d = pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)
	_agents[unit.get_id()] = motion_component

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	_controllers[unit.get_id()] = controller
	return unit


func _spawn_nodes(positions: Array[Vector2], is_gold: bool) -> void:
	for pos in positions:
		var node: RtsResourceNode = RtsResourceNodes.create_gold_node() if is_gold else RtsResourceNodes.create_wood_node()
		node.set_team_id(-1)
		_world.add_actor(node)
		node.position_2d = pos


func _spawn_unit_for_building(building: RtsBuildingActor) -> RtsUnitActor:
	if building == null or building.is_dead():
		return null
	var uc: int = building.spawn_unit_kind
	if uc < 0:
		return null
	var team_id: int = building.get_team_id()
	var spawn_offset: float = 28.0
	var spawn_pos: Vector2 = building.position_2d + (Vector2(spawn_offset, 0.0) if team_id == 0 else Vector2(-spawn_offset, 0.0))
	var unit := _spawn_unit(uc, team_id, spawn_pos)
	unit.stance = building.spawn_unit_stance
	_procedure.add_unit_to_team(unit, team_id)
	return unit


func _update_event_counts() -> void:
	for uid in _tracked_unit_ids:
		var actor := _world.get_actor(uid)
		if actor == null or not _agents.has(uid):
			continue
		var motion_component := _agents[uid] as RtsMotionComponent
		var has_t: bool = motion_component.motion.has_target()
		var psz: int = motion_component.motion._short_path.size()
		if has_t and not (_prev_has_target[uid] as bool):
			_set_target_events[uid] = (_set_target_events[uid] as int) + 1
		if has_t and psz != (_prev_path_size[uid] as int) and psz > 0:
			_path_change_events[uid] = (_path_change_events[uid] as int) + 1
		_prev_has_target[uid] = has_t
		_prev_path_size[uid] = psz


func _record_tick(tick: int) -> void:
	for uid in _tracked_unit_ids:
		var actor := _world.get_actor(uid)
		if actor == null:
			continue
		if not (actor is RtsUnitActor):
			continue
		var unit := actor as RtsUnitActor
		if unit.is_dead():
			continue
		var motion_component := _agents[uid] as RtsMotionComponent
		var ctrl := _controllers[uid] as RtsUnitController
		var pos := unit.position_2d
		var vel := unit.velocity
		var has_t: bool = motion_component.motion.has_target()
		var final_t: Vector2 = Vector2.ZERO
		if has_t:
			# motion final_target 仅 POINT MoveRequest 有意义;ENTITY/OFFSET 跳过
			var req: RtsMoveRequest = motion_component.motion._move_request
			if req != null and req.type == RtsMoveRequest.Type.POINT:
				final_t = req.position
		var dist_f: float = pos.distance_to(final_t) if has_t else -1.0
		var activity_label: String = "?"
		if ctrl != null and ctrl.current_activity != null:
			activity_label = ctrl.current_activity.get_intent_label()
		# 探 AttackActivity 内部
		var atk_target_id: String = ""
		var atk_target_alive: String = "?"
		var atk_target_pos: Vector2 = Vector2.ZERO
		var atk_dist: float = -1.0
		var atk_range: float = unit.attribute_set.attack_range
		var current_target_id: String = unit.current_target_id
		if ctrl != null and ctrl.current_activity is RtsAttackActivity:
			var aa := ctrl.current_activity as RtsAttackActivity
			atk_target_id = aa.target_id
			var t := _world.get_actor(aa.target_id)
			if t != null:
				atk_target_alive = "true" if not t.is_dead() else "DEAD"
				atk_target_pos = t.position_2d
				atk_dist = pos.distance_to(t.position_2d)
			else:
				atk_target_alive = "MISSING"

		_trace_lines.append("%d,%s,%d,%s,%.2f,%.2f,%.3f,%.3f,%.3f,%s,%d,%s,%.2f,%.2f,%.2f,%s,%s,%s,%.2f,%.2f,%.2f,%.2f,%s" % [
			tick, uid, unit.get_team_id(),
			RtsUnitClassConfig.UnitClass.keys()[unit.unit_class],
			pos.x, pos.y, vel.x, vel.y, vel.length(),
			str(has_t), motion_component.motion._short_path.size(),
			str(motion_component.motion._short_path.is_empty()),
			final_t.x, final_t.y, dist_f, activity_label,
			atk_target_id, atk_target_alive,
			atk_target_pos.x, atk_target_pos.y, atk_dist, atk_range,
			current_target_id,
		])


func _print_summary() -> void:
	print("=== diag_demo_frontend_trace summary ===")
	print("Result: %s, ticks=%d" % [_procedure.get_result(), _procedure.get_current_tick()])
	print("Tracked units: %d (data rows: %d)" % [_tracked_unit_ids.size(), _trace_lines.size() - 1])
	print("")
	print("uid | team | kind | final_pos | alive | set_target_evts | path_changes")
	for uid in _tracked_unit_ids:
		var actor := _world.get_actor(uid)
		if actor == null:
			print("%s | (gone)" % uid)
			continue
		var unit := actor as RtsUnitActor
		var fp: Vector2 = unit.position_2d
		var alive: bool = not unit.is_dead()
		var kind_str: String = RtsUnitClassConfig.UnitClass.keys()[unit.unit_class]
		print("%s | %d | %s | (%.0f,%.0f) | %s | %d | %d" % [
			uid, unit.get_team_id(), kind_str, fp.x, fp.y, str(alive),
			_set_target_events[uid] as int,
			_path_change_events[uid] as int,
		])

	# 徘徊检测: 找 dist_final 长时间不下降的 uid (suspect_oscillation)
	print("")
	print("--- Wandering suspects (has_target=true & dist_final > 15 for ≥ 30 sampled ticks) ---")
	var per_uid_lines: Dictionary = {}
	for line in _trace_lines:
		var parts := line.split(",")
		if parts.size() < 16 or parts[0] == "tick":
			continue
		var uid := parts[1]
		if not per_uid_lines.has(uid):
			per_uid_lines[uid] = []
		(per_uid_lines[uid] as Array).append(parts)

	for uid in per_uid_lines.keys():
		var rows: Array = per_uid_lines[uid] as Array
		var stuck_run: int = 0
		var max_stuck_run: int = 0
		var stuck_start: int = -1
		var stuck_end: int = -1
		var max_start: int = -1
		var max_end: int = -1
		for r in rows:
			var parts: PackedStringArray = r as PackedStringArray
			var has_t: bool = parts[9] == "true"
			var dist_f: float = float(parts[14])
			if has_t and dist_f > 15.0 and float(parts[8]) < 5.0:  # has_target + far + slow
				if stuck_run == 0:
					stuck_start = int(parts[0])
				stuck_run += 1
				stuck_end = int(parts[0])
				if stuck_run > max_stuck_run:
					max_stuck_run = stuck_run
					max_start = stuck_start
					max_end = stuck_end
			else:
				stuck_run = 0
		if max_stuck_run >= 6:  # 6 sampled ticks * 5 = 30 logic ticks = 1.5s
			print("WANDERING: %s — max_run=%d sampled ticks (%d~%d), %d set_targets" % [
				uid, max_stuck_run, max_start, max_end, _set_target_events[uid] as int,
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
