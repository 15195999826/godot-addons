## VisualizerContext - Visualizer 的只读上下文接口
##
## 设计原则：
## - 只读查询，不允许修改状态
## - Visualizer 是纯函数，只返回声明式的 VisualAction
## - 状态修改由 RenderWorld 统一执行
class_name FrontendVisualizerContext
extends RefCounted

# ========== 内部状态引用 ==========

## 角色状态 Map（actor_id -> FrontendActorRenderState）
var _actors: Dictionary = {}

## 插值位置 Map（actor_id -> Vector2）用于平滑动画
var _interpolated_positions: Dictionary = {}

## 动画配置
var _animation_config: FrontendAnimationConfig

## 六边形网格布局
var _layout: GridLayout


# ========== 构造函数 ==========

func _init(
	actors: Dictionary,
	interpolated_positions: Dictionary,
	animation_config: FrontendAnimationConfig,
	layout: GridLayout
) -> void:
	_actors = actors
	_interpolated_positions = interpolated_positions
	_animation_config = animation_config
	_layout = layout


# ========== 角色查询 ==========

## 获取角色当前位置（世界坐标）
func get_actor_position(actor_id: String) -> Vector3:
	var hex_pos := get_actor_hex_position(actor_id)
	var pixel := _layout.coord_to_pixel(hex_pos.to_axial())
	return Vector3(pixel.x, 0.0, pixel.y)


## 获取角色当前 HP
func get_actor_hp(actor_id: String) -> float:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor == null:
		return 0.0
	return actor.visual_hp


## 获取角色最大 HP
func get_actor_max_hp(actor_id: String) -> float:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor == null:
		return 100.0
	return actor.max_hp


## 检查角色是否存活
func is_actor_alive(actor_id: String) -> bool:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor == null:
		return false
	return actor.is_alive


## 获取角色六边形坐标
func get_actor_hex_position(actor_id: String) -> HexCoord:
	# 优先使用插值位置（取整）
	if _interpolated_positions.has(actor_id):
		var pos: Vector2 = _interpolated_positions[actor_id]
		return HexCoord.new(roundi(pos.x), roundi(pos.y))
	
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor == null:
		return HexCoord.zero()
	return actor.position


## 获取角色所属队伍
func get_actor_team(actor_id: String) -> int:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
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
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor == null:
		return ""
	return actor.display_name


# ========== 配置查询 ==========

## 获取动画配置
func get_animation_config() -> FrontendAnimationConfig:
	return _animation_config


## 获取六边形网格布局
func get_layout() -> GridLayout:
	return _layout


# ========== 坐标转换 ==========

## 将六边形坐标转换为世界坐标
func hex_to_world(hex: HexCoord) -> Vector3:
	var pixel := _layout.coord_to_pixel(hex.to_axial())
	return Vector3(pixel.x, 0.0, pixel.y)
