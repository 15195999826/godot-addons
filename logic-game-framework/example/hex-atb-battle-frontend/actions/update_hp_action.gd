## UpdateHPAction - 血条更新动作
##
## 平滑过渡血条显示值
class_name FrontendUpdateHPAction
extends FrontendVisualAction


# ========== 属性 ==========

## 起始 HP
var from_hp: float

## 目标 HP
var to_hp: float


# ========== 构造函数 ==========

func _init(
	p_actor_id: String,
	p_from_hp: float,
	p_to_hp: float,
	p_duration: float,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.UPDATE_HP, p_duration, p_delay)
	actor_id = p_actor_id
	from_hp = p_from_hp
	to_hp = p_to_hp


## 根据进度计算插值 HP
func get_interpolated_hp(progress: float) -> float:
	return FrontendVisualAction.lerp_value(from_hp, to_hp, progress)
