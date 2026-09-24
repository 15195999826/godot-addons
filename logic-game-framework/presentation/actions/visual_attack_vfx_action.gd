## VisualAttackVfxAction - 朝向性攻击特效卡片
##
## 在攻击者位置显示一个朝向目标的攻击特效（斩击波、能量冲击等）
## 攻击者本身不移动
class_name VisualAttackVfxAction
extends VisualAction


# ========== 特效类型枚举 ==========

enum AttackVFXType {
	SLASH,        # 斩击波
	THRUST,       # 突刺
	IMPACT,       # 冲击波
}


# ========== 属性 ==========

## 攻击者 ID
var source_actor_id: String

## 目标 ID
var target_actor_id: String

## 攻击者位置（逻辑平面坐标）
var source_position: Vector2

## 目标位置（逻辑平面坐标；方向 / 距离由 view 投影后算）
var target_position: Vector2

## 特效类型
var vfx_type: AttackVFXType

## 特效颜色
var vfx_color: Color

## 是否暴击（影响特效大小/颜色）
var is_critical: bool


# ========== 构造函数 ==========

func _init(
	p_source_actor_id: String,
	p_target_actor_id: String,
	p_source_position: Vector2,
	p_target_position: Vector2,
	p_duration: float,
	p_vfx_type: AttackVFXType = AttackVFXType.SLASH,
	p_vfx_color: Color = Color.WHITE,
	p_is_critical: bool = false,
	p_delay: float = 0.0
) -> void:
	super._init(KIND_ATTACK_VFX, p_duration, p_delay)
	source_actor_id = p_source_actor_id
	target_actor_id = p_target_actor_id
	source_position = p_source_position
	target_position = p_target_position
	vfx_type = p_vfx_type
	vfx_color = p_vfx_color
	is_critical = p_is_critical
	actor_id = p_source_actor_id  # 关联到攻击者


## 获取特效缩放（基于进度的淡入淡出）
func get_vfx_scale(progress: float) -> float:
	# 快速展开，缓慢消失
	if progress < 0.3:
		return progress / 0.3
	return 1.0 - (progress - 0.3) / 0.7


## 获取特效透明度
func get_vfx_alpha(progress: float) -> float:
	# 前半段保持不透明，后半段淡出
	if progress < 0.5:
		return 1.0
	return 1.0 - (progress - 0.5) / 0.5
