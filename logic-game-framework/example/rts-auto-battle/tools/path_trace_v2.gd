## RTS pathfinding trace v2 — 标准化 24-字段 CSV writer (M3 0AD migration M0.1)
##
## 用途:
##   M3 epic 全程 (M0..M8) 每个 milestone 末跑 baseline smoke 时,通过此 writer 产出
##   定式 24 字段 trace,与 git-tracked baseline CSV 做 bit-identical diff,验证寻路 /
##   行为决定性不漂移。
##
## CSV schema (24 cols, 顺序固定 — diff 工具按列对照):
##   tick, unit_id, team, kind, px, py, vx, vy, vmag,
##   long_path_size, long_path_wp_json,
##   short_path_size, short_path_wp_json,
##   has_target, final_tx, final_ty, dist_final,
##   obstruction_radius, clearance,
##   region_id, global_region_id,
##   failed_movements, ticket_state,
##   activity
##
## M0 阶段字段 coverage (partial — M1..M7 逐步填):
##   - 已填: tick, unit_id, team, kind, px, py, vx, vy, vmag,
##           has_target, final_tx, final_ty, dist_final,
##           obstruction_radius, activity
##   - 占位 (-1 / ""): long/short_path_size, long/short_path_wp_json, clearance,
##           region_id, global_region_id, failed_movements, ticket_state
##
## 设计约束:
##   - 字段顺序固定 — 不许中途插字段, 只许把占位字段填实 (M1+ 改 fill 不改 schema)
##   - 占位用 -1 (int field) / "" (string field), 让 diff 工具能区分"M0 没填" vs "M0 填了 0"
##   - 每行末加 \n, 不加 BOM, 不加 trailing comma — 标准 CSV
##   - 浮点用 "%.4f" 4 位精度 (足以分辨亚像素 + 不被浮点抖动当作"漂移")
##
## 用法:
## ```
## var writer := PathTraceV2Writer.new()
## writer.open("user://baseline.csv")
## writer.write_header()
## for tick_i in range(MAX_TICKS):
##     procedure.tick_once()
##     writer.write_row(world, tick_i)
## writer.close()
## ```
##
## 决策来源: M3-0AD-pathfinding-migration / M0-footprint-split.md §M0.1
class_name PathTraceV2Writer
extends RefCounted


# ========== 常量 ==========

## 字段头 (固定 24 列, 顺序与 write_row 内输出严格一致)
const HEADER: String = "tick,unit_id,team,kind,px,py,vx,vy,vmag,long_path_size,long_path_wp_json,short_path_size,short_path_wp_json,has_target,final_tx,final_ty,dist_final,obstruction_radius,clearance,region_id,global_region_id,failed_movements,ticket_state,activity"


# ========== 字段 ==========

var _file: FileAccess = null
var _row_count: int = 0


# ========== Lifecycle ==========

## 打开 file 句柄 (覆写模式). 失败返回 false, 调方应检查并 fail-fast.
func open(path: String) -> bool:
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return false
	_row_count = 0
	return true


## 写 CSV header (24 列名). 必须在第一次 write_row 之前调一次.
func write_header() -> void:
	if _file == null:
		return
	_file.store_line(HEADER)


## 关闭 file 句柄. 安全幂等 (重复调 no-op).
func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## 已写出的数据行数 (不含 header). smoke 用此报告 trace 行数.
func get_row_count() -> int:
	return _row_count


# ========== 主写入 API ==========

## 遍历 world 内所有 alive RtsBattleActor, 每个 actor 写一行.
##
## actor → {unit, building} 各取所需字段; nav agent 字段在 actor 类型不是 unit 时填占位.
##
## 调方约定: tick 计数从 0 起 (与 procedure._current_tick 不同 — procedure 在
## tick_once() 起手做 _current_tick += 1, 故第一次 tick_once 后 procedure tick=1).
## 调方传入的 tick 应与 trace 比对维度一致 (我们在 baseline smoke 内传 i=tick_once 后
## procedure.get_current_tick(), 与 BattleRecorder.frame 编号对齐).
func write_row(world: RtsWorldGameplayInstance, tick: int) -> void:
	if _file == null or world == null:
		return
	var actors: Array = world.get_alive_actors()
	for actor in actors:
		if not (actor is RtsBattleActor):
			continue
		var battle_actor: RtsBattleActor = actor as RtsBattleActor
		_write_actor_row(world, tick, battle_actor)


# ========== 内部 ==========

func _write_actor_row(
	world: RtsWorldGameplayInstance,
	tick: int,
	actor: RtsBattleActor,
) -> void:
	# 字段拼装顺序严格对应 HEADER.
	var unit_id: String = actor.get_id()
	var team: int = actor.get_team_id()
	var kind: String = _resolve_kind(actor)
	var pos: Vector2 = actor.position_2d
	var vel: Vector2 = actor.velocity
	var vmag: float = vel.length()

	# nav 字段仅 RtsUnitActor 有 nav agent; building 占位 (has_target=false / final=Vector2.ZERO)
	var has_target: bool = false
	var final_target: Vector2 = Vector2.ZERO
	var dist_final: float = -1.0

	# Activity 标签也仅 unit 有 (建筑没 controller / activity)
	var activity_label: String = ""

	if actor is RtsUnitActor:
		var unit: RtsUnitActor = actor as RtsUnitActor
		var procedure: RtsAutoBattleProcedure = world.procedure as RtsAutoBattleProcedure
		if procedure != null:
			var ctrl: RtsUnitController = procedure.get_unit_runtime(unit.get_id())
			if ctrl != null:
				activity_label = ctrl.get_intent_action()
				if ctrl.motion_component != null:
					has_target = ctrl.motion_component.motion.has_target()
					if has_target:
						# motion final_target 仅 POINT MoveRequest 有意义;ENTITY/OFFSET 跳过
						var req: RtsMoveRequest = ctrl.motion_component.motion._move_request
						if req != null and req.type == RtsMoveRequest.Type.POINT:
							final_target = req.position
							dist_final = pos.distance_to(final_target)

	# obstruction_radius: M0 没 obstruction_shape — 用 collision_radius 当占位
	# (M2 起 unit 有 obstruction_shape 后改填 shape.size; 此字段在 M0 已经能填实, 不算占位)
	var obstruction_radius: float = actor.collision_radius

	# 写一行 (24 列, 严格按 HEADER 顺序)
	_file.store_line(
		"%d,%s,%d,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%s,%d,%s,%s,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%d,%s,%s" % [
			tick,                          # 1. tick
			unit_id,                       # 2. unit_id
			team,                          # 3. team
			kind,                          # 4. kind
			pos.x, pos.y,                  # 5-6. px, py
			vel.x, vel.y,                  # 7-8. vx, vy
			vmag,                          # 9. vmag
			-1,                            # 10. long_path_size (M5 填)
			"",                            # 11. long_path_wp_json (M5 填)
			-1,                            # 12. short_path_size (M5 填)
			"",                            # 13. short_path_wp_json (M5 填)
			"true" if has_target else "false",  # 14. has_target
			final_target.x, final_target.y,  # 15-16. final_tx, final_ty
			dist_final,                    # 17. dist_final
			obstruction_radius,            # 18. obstruction_radius
			-1,                            # 19. clearance (M2 填)
			-1,                            # 20. region_id (M4 填)
			-1,                            # 21. global_region_id (M4 填)
			-1,                            # 22. failed_movements (M7 填)
			"",                            # 23. ticket_state (M7 filing)
			activity_label,                # 24. activity
		]
	)
	_row_count += 1


## 解析 actor 的 kind 标签 (供 trace diff 时区分 unit class / building kind).
##
## RtsUnitActor → "unit:<UnitClass enum int>" (e.g. "unit:0" = MELEE)
## RtsBuildingActor → "building:<building_kind>" (e.g. "building:crystal_tower")
## 其它 (RtsResourceNode 等) → "other:<class_name>"
func _resolve_kind(actor: RtsBattleActor) -> String:
	if actor is RtsUnitActor:
		return "unit:%d" % (actor as RtsUnitActor).unit_class
	if actor is RtsBuildingActor:
		return "building:%s" % (actor as RtsBuildingActor).building_kind
	return "other:%s" % actor.get_class()
