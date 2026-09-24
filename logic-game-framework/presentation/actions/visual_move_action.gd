## VisualMoveAction - 移动卡片
##
## 把 actor 从一个逻辑平面位置移到另一个（hex 项目：格到格）
class_name VisualMoveAction
extends VisualAction



# ========== 属性 ==========

## 起始逻辑平面坐标
var from_position: Vector2

## 目标逻辑平面坐标
var to_position: Vector2

## 缓动函数
var easing: EasingType


# ========== 构造函数 ==========

func _init(
	p_actor_id: String,
	p_from_position: Vector2,
	p_to_position: Vector2,
	p_duration: float,
	p_easing: EasingType = EasingType.EASE_IN_OUT_QUAD,
	p_delay: float = 0.0
) -> void:
	super._init(KIND_MOVE, p_duration, p_delay)
	actor_id = p_actor_id
	from_position = p_from_position
	to_position = p_to_position
	easing = p_easing


## 根据进度计算插值位置（逻辑平面浮点坐标）
func get_interpolated_position(progress: float) -> Vector2:
	var eased_progress := VisualAction.apply_easing(progress, easing)
	return VisualAction.lerp_vector2(from_position, to_position, eased_progress)
