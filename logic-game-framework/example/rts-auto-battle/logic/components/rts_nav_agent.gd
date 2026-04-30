## RtsNavAgent - 单位寻路 / 移动包装
##
## NavigationAgent2D 是 Node, 不能直接挂在 RtsBattleActor(RefCounted) 上。
## 此 Node 作为 actor 在场景树里的 "avatar", 负责:
##   1. 持有 NavigationAgent2D, 处理 navmesh 上的下一帧路径点
##   2. 推进 position 向目标接近(按 actor.attribute_set.move_speed 走)
##   3. 把更新后的位置回写到 actor.position_2d
##
## 调方(smoke / frontend)通过 actor.id → RtsNavAgent 查表把两者绑起来。
## 一个 actor 一个 RtsNavAgent, 全部挂在 navigation 场景的子节点下。
class_name RtsNavAgent
extends Node2D


# ========== 字段 ==========

var actor: RtsBattleActor = null

## 子 NavigationAgent2D, _ready 时 add_child
var nav_agent: NavigationAgent2D = null

## 已抵达 target 的距离阈值(像素)
var arrival_threshold: float = 4.0

## 走过的总距离(像素), 服务 AC2 辅助断言: 总距离 / 起止直线距离 ≥ 1.03 视为绕路成功
var path_length_traveled: float = 0.0

## 起点与首次 set_target 时的目标点, 用于直线比例计算
var start_position: Vector2 = Vector2.ZERO
var first_target_position: Vector2 = Vector2.ZERO
var _has_first_target: bool = false

## 行走过程中 y 偏离起点 y 的最大值(像素), 服务 AC2 主断言:
## 横向起止两点 y 相同时, 单位若直线穿墙 max_y_deviation 应 ≈ 0;
## 真正绕过中央障碍 (200..300 在 y) 必然产生显著 y 偏移。
var max_y_deviation: float = 0.0
var max_x_deviation: float = 0.0


# ========== 初始化 ==========

func _ready() -> void:
	nav_agent = NavigationAgent2D.new()
	nav_agent.path_desired_distance = arrival_threshold
	nav_agent.target_desired_distance = arrival_threshold
	nav_agent.avoidance_enabled = false  # M0 不做 unit 间避让, 简化行为
	add_child(nav_agent)


# ========== 绑定 actor ==========

func bind_actor(p_actor: RtsBattleActor) -> void:
	actor = p_actor
	position = p_actor.position_2d
	start_position = p_actor.position_2d


# ========== 寻路 API ==========

## 设置目标点(世界坐标)。NavigationServer 会异步算路径, 后续 tick 取下一帧路径点。
func set_target(target_world_pos: Vector2) -> void:
	if nav_agent == null:
		return
	nav_agent.target_position = target_world_pos
	if not _has_first_target:
		first_target_position = target_world_pos
		_has_first_target = true


## 清空目标(actor 进入 attack range 时停止移动)。
func clear_target() -> void:
	if nav_agent == null:
		return
	nav_agent.target_position = position


## 是否抵达 NavigationAgent 当前 target。
func is_arrived() -> bool:
	if nav_agent == null:
		return true
	return nav_agent.is_navigation_finished()


# ========== Tick ==========

## procedure 每帧调用; dt 单位秒。把 actor 按 move_speed 推到下一帧路径点。
func tick(dt: float) -> void:
	if nav_agent == null or actor == null or actor.is_dead():
		return

	if nav_agent.is_navigation_finished():
		actor.velocity = Vector2.ZERO
		return

	var next_pt := nav_agent.get_next_path_position()
	var to_next := next_pt - position
	var dist := to_next.length()
	if dist <= 0.0001:
		return

	var move_speed: float = _resolve_move_speed()
	var step_len: float = move_speed * dt
	var step_vec: Vector2
	if step_len >= dist:
		step_vec = to_next
	else:
		step_vec = to_next.normalized() * step_len

	position += step_vec
	path_length_traveled += step_vec.length()
	actor.velocity = step_vec / dt if dt > 0.0 else Vector2.ZERO
	actor.position_2d = position
	max_y_deviation = max(max_y_deviation, abs(position.y - start_position.y))
	max_x_deviation = max(max_x_deviation, abs(position.x - start_position.x))


# ========== 内部 ==========

func _resolve_move_speed() -> float:
	if actor is RtsCharacterActor:
		return (actor as RtsCharacterActor).attribute_set.move_speed
	return 0.0
