## VisualAction - 视觉动作基类
##
## 描述原子级的视觉效果，由 Visualizer 从 GameEvent 翻译而来。
## 这些动作是声明式的，描述"做什么"而非"怎么做"。
##
## 设计原则：
## - 纯数据对象，不持有 Node 引用
## - 声明式描述，由 RenderWorld 应用
## - 支持 delay 延迟执行
class_name FrontendVisualAction
extends RefCounted


# ========== 动作类型枚举 ==========

enum ActionType {
	MOVE,
	UPDATE_HP,
	FLOATING_TEXT,
	MELEE_STRIKE,
	PROCEDURAL_VFX,
	DEATH,
	ATTACK_VFX,      # 朝向性攻击特效
	PROJECTILE,      # 投射物飞行
}


# ========== 缓动函数枚举 ==========

enum EasingType {
	LINEAR,
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	EASE_IN_QUAD,
	EASE_OUT_QUAD,
	EASE_IN_OUT_QUAD,
	EASE_IN_CUBIC,
	EASE_OUT_CUBIC,
	EASE_IN_OUT_CUBIC,
}


# ========== 基础属性 ==========

## 动作类型
var type: ActionType

## 关联的 Actor ID（可选，某些全局效果无需）
var actor_id: String = ""

## 动画持续时间（毫秒）
var duration: float = 0.0

## 延迟执行时间（毫秒），默认 0
var delay: float = 0.0


# ========== 构造函数 ==========

func _init(p_type: ActionType, p_duration: float, p_delay: float = 0.0) -> void:
	type = p_type
	duration = p_duration
	delay = p_delay


# ========== 缓动函数实现 ==========

## 应用缓动函数
static func apply_easing(progress: float, easing: EasingType) -> float:
	match easing:
		EasingType.LINEAR:
			return progress
		EasingType.EASE_IN:
			return progress * progress
		EasingType.EASE_OUT:
			return progress * (2.0 - progress)
		EasingType.EASE_IN_OUT:
			if progress < 0.5:
				return 2.0 * progress * progress
			return -1.0 + (4.0 - 2.0 * progress) * progress
		EasingType.EASE_IN_QUAD:
			return progress * progress
		EasingType.EASE_OUT_QUAD:
			return progress * (2.0 - progress)
		EasingType.EASE_IN_OUT_QUAD:
			if progress < 0.5:
				return 2.0 * progress * progress
			return -1.0 + (4.0 - 2.0 * progress) * progress
		EasingType.EASE_IN_CUBIC:
			return progress * progress * progress
		EasingType.EASE_OUT_CUBIC:
			var t := progress - 1.0
			return t * t * t + 1.0
		EasingType.EASE_IN_OUT_CUBIC:
			if progress < 0.5:
				return 4.0 * progress * progress * progress
			var t := progress - 1.0
			return (t * 2.0) * (t * 2.0) * (t * 2.0) + 1.0
		_:
			return progress


## 线性插值
static func lerp_value(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## Vector3 线性插值
static func lerp_vector3(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a + (b - a) * t
