## VisualStateQuery - 账本的只读视图（给翻译员用）
##
## 设计原则：
## - 只读查询，不允许修改账本
## - 翻译员是纯函数，只返回声明式的 VisualAction
## - 账本修改由 VisualUpdater 统一执行
## - 位置只讲逻辑平面坐标（Vector2）；像素 / 3D 投影是 view 层的事，
##   翻译员拿不到棋盘几何，欧氏派生量（方向 / 距离）也留给 view 投影后再算
class_name VisualStateQuery
extends RefCounted

# ========== 内部状态引用 ==========

## 角色状态 Map（actor_id -> ActorVisualState）
var _actors: Dictionary = {}

## 插值位置 Map（actor_id -> Vector2）用于平滑动画
var _interpolated_positions: Dictionary = {}

## 动画配置
var _animation_config: AnimationConfig


# ========== 构造函数 ==========

func _init(
	actors: Dictionary,
	interpolated_positions: Dictionary,
	animation_config: AnimationConfig
) -> void:
	_actors = actors
	_interpolated_positions = interpolated_positions
	_animation_config = animation_config


# ========== 角色查询 ==========

## 获取角色当前逻辑平面坐标（含移动中的在飞插值）；未知 actor 返回 ZERO
func get_actor_position(actor_id: String) -> Vector2:
	if _interpolated_positions.has(actor_id):
		return _interpolated_positions[actor_id]
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return Vector2.ZERO
	return actor.position


## actor 是否在账本上（用来区分「站在 (0,0)」和「不认识」）
func has_actor(actor_id: String) -> bool:
	return _actors.has(actor_id)


## 获取角色当前 HP
func get_actor_hp(actor_id: String) -> float:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return 0.0
	return actor.visual_hp


## 获取角色最大 HP
func get_actor_max_hp(actor_id: String) -> float:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return 100.0
	return actor.max_hp


## 检查角色是否存活
func is_actor_alive(actor_id: String) -> bool:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return false
	return actor.is_alive


## 获取角色所属队伍
func get_actor_team(actor_id: String) -> int:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return 0
	return actor.team


## 获取所有角色 ID
func get_all_actor_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _actors.keys():
		ids.append(key as String)
	return ids


## 获取角色显示名称
func get_actor_display_name(actor_id: String) -> String:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return ""
	return actor.display_name


# ========== 配置查询 ==========

## 获取动画配置
func get_animation_config() -> AnimationConfig:
	return _animation_config
