## VisualAction - 卡片基类
##
## 一张卡片 = 翻译员从一条逻辑事件翻出来的一段声明式表演（做什么，不是怎么做）。
## 卡片是纯数据：不持 Node、不改账本；怎么记账由 VisualUpdater 按 kind 查 handler 决定。
##
## 设计原则：
## - kind 是开放的 StringName：内置种类用本类的 KIND_* 常量，项目私有卡片自定义 kind 并向
##   VisualUpdater.register_handler 登记自己的记账函数，不改框架
## - 支持 delay 延迟执行；时间单位一律毫秒
## - 位置字段一律是逻辑平面坐标（Vector2，含义由项目定：hex 项目是 axial 浮点，连续世界是 (x, y)）；
##   像素 / 3D 与方向、距离这类欧氏量归 view 层投影后算
class_name VisualAction
extends RefCounted


# ========== 内置卡片种类 ==========

const KIND_MOVE: StringName = &"move"
## 瞬时指令：把 hp delta 累到 actor.target_hp，visual_hp 由 VisualUpdater.tick_time 持续追赶
const KIND_HP_DELTA: StringName = &"hp_delta"
const KIND_FLOATING_TEXT: StringName = &"floating_text"
const KIND_PROCEDURAL_VFX: StringName = &"procedural_vfx"
const KIND_DEATH: StringName = &"death"
## 朝向性攻击特效
const KIND_ATTACK_VFX: StringName = &"attack_vfx"
## 投射物飞行
const KIND_PROJECTILE: StringName = &"projectile"
## 瞬时：对 actor.buffs 数组做 ADD/UPDATE/REMOVE
const KIND_BUFF_STATE: StringName = &"buff_state"
## 瞬时：对 actor.shields 数组做 ADD/UPDATE/REMOVE
const KIND_SHIELD_STATE: StringName = &"shield_state"
## 撞墙 / 撞单位的临时位移弹回（view 层叠加 offset + squish，不动逻辑位置）
const KIND_BUMP: StringName = &"bump"
## 瞬时更新 actor.facing_direction，无 turn-speed / lerp
const KIND_FACING_STATE: StringName = &"facing_state"


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

## 卡片种类（VisualUpdater 按它查记账 handler）
var kind: StringName

## 关联的 Actor ID（可选，某些全局效果无需）
var actor_id: String = ""

## 动画持续时间（毫秒）
var duration: float = 0.0

## 延迟执行时间（毫秒），默认 0
var delay: float = 0.0


# ========== 构造函数 ==========

func _init(p_kind: StringName, p_duration: float, p_delay: float = 0.0) -> void:
	kind = p_kind
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


## Vector2 线性插值（逻辑平面坐标）
static func lerp_vector2(a: Vector2, b: Vector2, t: float) -> Vector2:
	return a + (b - a) * t
