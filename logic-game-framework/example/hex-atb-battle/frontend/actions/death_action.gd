## DeathAction - 死亡动作
##
## 角色死亡时的视觉效果
class_name FrontendDeathAction
extends FrontendVisualAction


# ========== 属性 ==========

## 击杀者 ID（可选）
var killer_id: String


# ========== 构造函数 ==========

func _init(
	p_actor_id: String,
	p_duration: float,
	p_killer_id: String = "",
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.DEATH, p_duration, p_delay)
	actor_id = p_actor_id
	killer_id = p_killer_id


## 计算淡出透明度
func get_fade_alpha(progress: float) -> float:
	return 1.0 - progress


## 计算下沉偏移
func get_sink_offset(progress: float) -> float:
	return -progress * 0.5  # 下沉 0.5 单位
