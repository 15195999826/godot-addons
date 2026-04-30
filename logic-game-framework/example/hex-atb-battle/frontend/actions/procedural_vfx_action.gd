## ProceduralVFXAction - 程序化特效动作
##
## 代码生成的效果（震屏、闪白、染色）
class_name FrontendProceduralVFXAction
extends FrontendVisualAction


# ========== 特效类型枚举 ==========

enum EffectType {
	HIT_FLASH,    # 受击闪白
	SHAKE,        # 震屏
	COLOR_TINT,   # 染色
}


# ========== 属性 ==========

## 效果类型
var effect: EffectType

## 效果强度（shake 使用）
var intensity: float

## 染色颜色（colorTint 使用）
var tint_color: Color


# ========== 构造函数 ==========

func _init(
	p_effect: EffectType,
	p_duration: float,
	p_actor_id: String = "",
	p_intensity: float = 5.0,
	p_tint_color: Color = Color.WHITE,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.PROCEDURAL_VFX, p_duration, p_delay)
	actor_id = p_actor_id
	effect = p_effect
	intensity = p_intensity
	tint_color = p_tint_color


## 计算闪白强度（前半段增强，后半段衰减）
func get_flash_intensity(progress: float) -> float:
	if progress < 0.5:
		return progress * 2.0
	return (1.0 - progress) * 2.0


## 计算震屏偏移
func get_shake_offset(progress: float) -> Vector2:
	var decay := 1.0 - progress
	return Vector2(
		sin(progress * PI * 8.0) * intensity * decay,
		cos(progress * PI * 6.0) * intensity * decay * 0.5
	)
