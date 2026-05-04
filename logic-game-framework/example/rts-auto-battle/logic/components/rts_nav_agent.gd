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
const ARRIVAL_THRESHOLD_SQ: float = ARRIVAL_THRESHOLD * ARRIVAL_THRESHOLD


# ========== 字段 ==========

var actor: RtsBattleActor = null
var grid: RtsBattleGrid = null

## M5: PathfinderFacade 引用(procedure._init 末注入 world.pathfinder_facade);facade 优先,
## facade==null 时 fallback 老 RtsPathfinding.find_path 路径(旧 smoke 不走 procedure)。
var facade: RtsPathfinderFacade = null

## M5: per-actor pass_mask cache(GROUND→default mask / AIR→air mask),bind_actor 时算。
##
## 0 = invalid(facade 路径不可用,fallback 走 grid + layer)。
var _pass_mask: int = 0

## 当前路径(world 坐标 waypoint 列表), set_target 时填充。
##
## **Forward iteration**:`_path[_waypoint_index]` 是下一个目标 → ++_waypoint_index 推进。
## 来源 = M5 facade RtsWaypointPath.waypoints reverse(facade 反向存储,我们这层 forward 用)
## 或 M5 之前 RtsPathfinding.find_path Array[Vector2]。
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


## M5: 注入 PathfinderFacade + 算 pass_mask cache(procedure._init 末调,grid 之后)。
##
## facade null 时 nav_agent 退回老 RtsPathfinding.find_path 路径(旧 smoke 不走 procedure)。
func attach_pathfinder(p_facade: RtsPathfinderFacade, p_registry: RtsPassabilityClassRegistry) -> void:
	facade = p_facade
	if actor != null and p_registry != null:
		var class_id: String = "air" if actor.movement_layer == MovementLayer.Layer.AIR else "default"
		_pass_mask = p_registry.get_mask(class_id)
	else:
		_pass_mask = 0


# ========== 寻路 API ==========

## 设置目标点(世界坐标)。立即跑 A* 拿 waypoint 列表, 后续 tick 沿 waypoint 推进。
##
## 寻路失败(grid 未绑 / 找不到路径)时清空 path → tick 时 actor 速度归零, 调方下次再试。
##
## **M5 canonicalize 参数**:
##   - true(默认):走 facade.compute_path_immediate — 玩家 click 走 canonicalize,goal 落
##     impassable 区时 mutate 到外缘 navcell(✋2 体验点 = unit 走最近可达,不死循环)
##   - false:走 facade.compute_path_direct — AI attack-move / harvest 等 "target 是 actor 中心,
##     可能在 footprint 内" 的 callsite,不 canonicalize 直接 A*(避免 M4b.3 wire fail lesson:
##     enemy 中心被偏到 ct 旁外缘 → unit 在 attack range 外永远打不到)
##
## **facade null fallback**(旧 smoke 不走 procedure):退回 RtsPathfinding.find_path 老路径,
## canonicalize 参数被忽略。
func set_target(target_world_pos: Vector2, canonicalize: bool = true) -> void:
	_final_target = target_world_pos
	_has_target = true
	if not _has_first_target:
		first_target_position = target_world_pos
		_has_first_target = true

	if actor == null:
		_path = []
		_waypoint_index = 0
		return

	# M5 facade 路径(优先):走 RtsLongPathfinder + canonicalize 选择
	if facade != null and _pass_mask != 0:
		var goal := RtsPathGoal.new(RtsPathGoal.Type.POINT, target_world_pos)
		var wp_path: RtsWaypointPath
		if canonicalize:
			wp_path = facade.compute_path_immediate(actor.position_2d, goal, _pass_mask)
		else:
			wp_path = facade.compute_path_direct(actor.position_2d, goal, _pass_mask)
		# Reverse 到 forward array(facade RtsWaypointPath 反向存储:waypoints[0]=goal,
		# [size-1]=next-step;nav_agent 老 forward iter:_path[0]=next-step,_path[size-1]=goal)
		_path = []
		for k in range(wp_path.size() - 1, -1, -1):
			_path.append(wp_path.waypoints[k])
		_waypoint_index = 0
		return

	# Fallback:老 RtsPathfinding.find_path(旧 smoke 不走 procedure 时;M5.5 删 RtsBattleGrid 后此路径同步删)
	if grid == null:
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
	if actor.position_2d.distance_squared_to(_final_target) <= ARRIVAL_THRESHOLD_SQ:
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
	return actor.position_2d.distance_squared_to(_final_target) <= ARRIVAL_THRESHOLD_SQ


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
		var next_dist_sq: float = actor.position_2d.distance_squared_to(next_pt)
		if next_dist_sq <= ARRIVAL_THRESHOLD_SQ:
			_waypoint_index += 1
			continue
		# 跳过被 steering 推过头的 waypoint: 若下一 waypoint 比当前 waypoint 更近, 视为已通过
		if _waypoint_index + 1 < _path.size():
			var future_pt: Vector2 = _path[_waypoint_index + 1]
			if actor.position_2d.distance_squared_to(future_pt) < next_dist_sq:
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
