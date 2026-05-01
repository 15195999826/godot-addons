## RtsNavAgent - 单位寻路 / 移动包装(纯 GDScript, 无 NavigationAgent2D)
##
## P1.2 重写: 去掉 NavigationAgent2D 依赖, 改成"持当前路径 + waypoint 索引 + 前进 to next"
## 的纯 GDScript 实现。决策 D3 锁定不用 NavigationServer, 走自研 grid + A*。
##
## P2.2 拆分: 把"计算速度"与"写位置"两步分开, 让 procedure 主循环可以在两步中间插
## spatial_hash + steering 改写 actor.velocity:
##   compute_desired_velocity(dt) — 仅写 actor.velocity (waypoint 方向 × move_speed); 不动 position
##   integrate(dt)                — 仅写 actor.position_2d += actor.velocity * dt; 推进 waypoint 索引
##   tick(dt)                     — 老接口 backwards-compat: 内部调 compute + integrate
##                                    (smoke_navigation / smoke_grid_pathfinding 在 procedure 外
##                                    手动驱动 nav 时仍用这个)
##
## 仍保持 Node2D 是因为现有 5 处 demo/smoke 都用 _battle_map.add_child(agent) 把 agent 挂在场景树
## (frontend visualizer 也走类似 pattern)。Phase 2 P2.7 接 BattleDirector 流式时可重新评估。
##
## 流程 (procedure-driven):
##   bind_actor(actor, grid) → activity.set_target(world_pos) → procedure 每帧调
##   compute_desired_velocity → steering 改写 velocity → integrate 推位置。
##
## AC2 / smoke_navigation 用的辅助统计字段(path_length_traveled / max_y_deviation 等)保留,
## 仍在 integrate 内累加 (按"实际走出"的 step_vec 计, 已包含 steering 偏移)。
class_name RtsNavAgent
extends Node2D


# ========== 常量 ==========

## 抵达 waypoint 的距离阈值(像素)
const ARRIVAL_THRESHOLD: float = 4.0


# ========== 字段 ==========

var actor: RtsBattleActor = null
var grid: RtsBattleGrid = null

## 当前路径(world 坐标 waypoint 列表), set_target 时由 RtsPathfinding.find_path 填充
var _path: Array[Vector2] = []

## 当前正在前进的 waypoint 索引(_path[_waypoint_index] 即"下一个目标点")
var _waypoint_index: int = 0

## 最近一次 set_target 传入的最终目标(用于 is_arrived 判定)
var _final_target: Vector2 = Vector2.ZERO
var _has_target: bool = false

# ========== 统计字段(AC2 detour 断言 / smoke 用) ==========

## 走过的总距离(像素), 服务 nav smoke 辅助断言: 总距离 / 起止直线距离 ≥ 1.03
var path_length_traveled: float = 0.0

## 起点与首次 set_target 时的目标点, 用于直线比例计算
var start_position: Vector2 = Vector2.ZERO
var first_target_position: Vector2 = Vector2.ZERO
var _has_first_target: bool = false

## 行走过程中 y / x 偏离起点的最大值(像素), 服务 AC2 主断言。
var max_y_deviation: float = 0.0
var max_x_deviation: float = 0.0


# ========== 绑定 ==========

func bind_actor(p_actor: RtsBattleActor, p_grid: RtsBattleGrid = null) -> void:
	actor = p_actor
	grid = p_grid
	position = p_actor.position_2d
	start_position = p_actor.position_2d


## 后绑 grid (smoke 在 spawn 之后才注入 grid 时用)
func set_grid(p_grid: RtsBattleGrid) -> void:
	grid = p_grid


# ========== 寻路 API ==========

## 设置目标点(世界坐标)。立即跑 A* 拿 waypoint 列表, 后续 tick 沿 waypoint 推进。
##
## 寻路失败(grid 未绑 / 找不到路径)时清空 path → tick 时 actor 速度归零, 调方下次再试。
func set_target(target_world_pos: Vector2) -> void:
	_final_target = target_world_pos
	_has_target = true
	if not _has_first_target:
		first_target_position = target_world_pos
		_has_first_target = true

	if grid == null or actor == null:
		_path = []
		_waypoint_index = 0
		return

	var layer: int = actor.movement_layer
	_path = RtsPathfinding.find_path(grid, actor.position_2d, target_world_pos, layer)
	_waypoint_index = 0


## 清空目标(actor 进入 attack range 时停止移动)。
func clear_target() -> void:
	_path = []
	_waypoint_index = 0
	_has_target = false
	if actor != null:
		actor.velocity = Vector2.ZERO


## 是否抵达 _final_target(允许 ARRIVAL_THRESHOLD 像素的容差)。
func is_arrived() -> bool:
	if not _has_target or actor == null:
		return true
	if _waypoint_index >= _path.size():
		return true
	if actor.position_2d.distance_to(_final_target) <= ARRIVAL_THRESHOLD:
		return true
	return false


# ========== P2.3 stuck detection 用的查询 ==========

## 当前是否持有 active 目标 (set_target 设过 + 还没 clear_target)。
##
## 注: 与 is_arrived 不同 — 路径找不到 (空 path) 时 is_arrived 也返回 true (兼容老调方),
## 但 has_target 仍为 true. stuck detector 用 has_target + position-not-near-final 判断"想动但动不了"。
func has_target() -> bool:
	return _has_target


## 当前 actor 是否在 _final_target 的 ARRIVAL_THRESHOLD 内 (与 is_arrived 不同 — 不读 path 状态,
## 仅看 position 与目标距离)。给 stuck detector 用: agent has_target=true 但 actor 已在目标处
## 不算 stuck (典型场景: AttackActivity 已 in-range 但未 clear_target 的 race)。
func is_at_final_target() -> bool:
	if not _has_target or actor == null:
		return true
	return actor.position_2d.distance_to(_final_target) <= ARRIVAL_THRESHOLD


## 当前最终目标坐标 (像素); _has_target=false 时返回 Vector2.ZERO 占位 (调方应先查 has_target)。
func get_final_target() -> Vector2:
	if not _has_target:
		return Vector2.ZERO
	return _final_target


## 当前 path 是否为空 (无可行路径; 通常因 A* 找不到路径或起点 / 终点不可通行)。
func has_empty_path() -> bool:
	return _path.is_empty()


# ========== Tick (P2.2 拆分) ==========

## 写 actor.velocity = waypoint 方向 × move_speed; 不写位置, 不推进 waypoint 索引。
##
## procedure 在 steering 之前调; 也允许调方传 dt = 0 (本接口不读 dt, 留着仅为对称)。
## 无 path / 已抵达 / 无 actor → velocity = 0, 静止单位是合法状态(idle / 攻击 in-range)。
func compute_desired_velocity(_dt: float) -> void:
	if actor == null or actor.is_dead():
		return
	if _waypoint_index >= _path.size():
		actor.velocity = Vector2.ZERO
		return
	var next_pt: Vector2 = _path[_waypoint_index]
	var to_next: Vector2 = next_pt - actor.position_2d
	var dist: float = to_next.length()
	if dist <= 0.0001:
		actor.velocity = Vector2.ZERO
		return
	var move_speed: float = _resolve_move_speed()
	actor.velocity = to_next.normalized() * move_speed


## 写 actor.position_2d += actor.velocity * dt; 推进 waypoint 索引 + 累加统计。
##
## procedure 在 steering 之后调 — actor.velocity 已被 steering 修改 (含 separation / deflection)。
## 如果 steering 把单位推得偏离当前 waypoint, "下一 waypoint 比当前 waypoint 更近" 检测会自动跳过
## 旧的 waypoint, 避免单位卡在错过的 waypoint 上转圈。
func integrate(dt: float) -> void:
	if actor == null or actor.is_dead():
		return
	var step_vec: Vector2 = actor.velocity * dt
	if step_vec.length_squared() > 0.0:
		actor.position_2d += step_vec
		position = actor.position_2d
		path_length_traveled += step_vec.length()
		max_y_deviation = max(max_y_deviation, abs(actor.position_2d.y - start_position.y))
		max_x_deviation = max(max_x_deviation, abs(actor.position_2d.x - start_position.x))

	# Waypoint 抵达检查 + steering 推过头时的跳号
	while _waypoint_index < _path.size():
		var next_pt: Vector2 = _path[_waypoint_index]
		if actor.position_2d.distance_to(next_pt) <= ARRIVAL_THRESHOLD:
			_waypoint_index += 1
			continue
		# 跳过被 steering 推过头的 waypoint: 若下一 waypoint 比当前 waypoint 更近, 视为已通过
		if _waypoint_index + 1 < _path.size():
			var future_pt: Vector2 = _path[_waypoint_index + 1]
			if actor.position_2d.distance_to(future_pt) < actor.position_2d.distance_to(next_pt):
				_waypoint_index += 1
				continue
		break


## 老接口 backwards-compat: 内部 = compute_desired_velocity + integrate。
##
## procedure 主循环已经显式拆开调用; 仅 smoke_navigation / smoke_grid_pathfinding 在 procedure
## 外手动驱动 agent 时使用 (它们没有 steering 中间层, 一个 tick 完成 nav 推进即可)。
func tick(dt: float) -> void:
	compute_desired_velocity(dt)
	integrate(dt)


# ========== 内部 ==========

func _resolve_move_speed() -> float:
	if actor is RtsUnitActor:
		return (actor as RtsUnitActor).attribute_set.move_speed
	return 0.0
