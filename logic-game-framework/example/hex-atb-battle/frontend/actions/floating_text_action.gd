## FloatingTextAction - 飘字动作
##
## 在指定位置显示飘字（伤害数字、治疗数字等）
class_name FrontendFloatingTextAction
extends FrontendVisualAction


# ========== 飘字样式枚举 ==========

enum FloatingTextStyle {
	NORMAL,
	CRITICAL,
	HEAL,
	MISS,
}


# ========== 属性 ==========

## 显示文本
var text: String

## 文字颜色
var color: Color

## 显示位置（世界坐标）
var position: Vector3

## 飘字样式
var style: FloatingTextStyle


# ========== 构造函数 ==========

func _init(
	p_actor_id: String,
	p_text: String,
	p_color: Color,
	p_position: Vector3,
	p_style: FloatingTextStyle,
	p_duration: float,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.FLOATING_TEXT, p_duration, p_delay)
	actor_id = p_actor_id
	text = p_text
	color = p_color
	position = p_position
	style = p_style


## 根据样式获取默认颜色
static func get_style_color(p_style: FloatingTextStyle) -> Color:
	match p_style:
		FloatingTextStyle.NORMAL:
			return Color.WHITE
		FloatingTextStyle.CRITICAL:
			return Color(1.0, 0.8, 0.0)  # 金色
		FloatingTextStyle.HEAL:
			return Color(0.2, 1.0, 0.2)  # 绿色
		FloatingTextStyle.MISS:
			return Color(0.5, 0.5, 0.5)  # 灰色
		_:
			return Color.WHITE
