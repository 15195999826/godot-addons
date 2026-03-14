## AnimationConfig - 动画配置
##
## 定义所有动画相关的配置参数，支持运行时调整
class_name FrontendAnimationConfig
extends RefCounted


# ========== 移动动画配置 ==========

## 移动动画时长（毫秒）
var move_duration: float = 500.0

## 移动缓动函数
var move_easing: FrontendVisualAction.EasingType = FrontendVisualAction.EasingType.EASE_IN_OUT_QUAD


# ========== 伤害动画配置 ==========

## 飘字持续时间（毫秒）
var damage_floating_text_duration: float = 1000.0

## 血条动画时长（毫秒）
var damage_hp_bar_duration: float = 300.0

## 血条动画延迟（毫秒），等待受击特效
var damage_hp_bar_delay: float = 200.0

## 受击特效时长（毫秒）
var damage_hit_vfx_duration: float = 300.0


# ========== 治疗动画配置 ==========

## 飘字持续时间（毫秒）
var heal_floating_text_duration: float = 1000.0

## 血条动画时长（毫秒）
var heal_hp_bar_duration: float = 300.0


# ========== 死亡动画配置 ==========

## 死亡动画时长（毫秒）
var death_duration: float = 1000.0


# ========== 技能动画配置 ==========

## 基础攻击动画时长（毫秒）
var skill_basic_attack_duration: float = 1000.0

## 基础攻击命中帧时间点（毫秒）
var skill_basic_attack_hit_frame: float = 500.0


# ========== 攻击特效配置 ==========

## 攻击特效持续时间（毫秒）
var attack_vfx_duration: float = 300.0


# ========== 投射物配置 ==========

## 投射物默认大小
var projectile_size: float = 0.15

## 投射物命中特效时长（毫秒）
var projectile_hit_vfx_duration: float = 200.0

## 投射物默认速度（单位/秒）
var projectile_default_speed: float = 20.0


# ========== 工厂方法 ==========

## 创建默认配置
static func create_default() -> FrontendAnimationConfig:
	return FrontendAnimationConfig.new()


## 从字典创建配置
static func from_dict(data: Dictionary) -> FrontendAnimationConfig:
	var config := FrontendAnimationConfig.new()
	
	if data.has("move"):
		var move_data: Dictionary = data["move"]
		config.move_duration = move_data.get("duration", config.move_duration) as float
	
	if data.has("damage"):
		var damage_data: Dictionary = data["damage"]
		config.damage_floating_text_duration = damage_data.get("floatingTextDuration", config.damage_floating_text_duration) as float
		config.damage_hp_bar_duration = damage_data.get("hpBarDuration", config.damage_hp_bar_duration) as float
		config.damage_hp_bar_delay = damage_data.get("hpBarDelay", config.damage_hp_bar_delay) as float
		config.damage_hit_vfx_duration = damage_data.get("hitVfxDuration", config.damage_hit_vfx_duration) as float
	
	if data.has("heal"):
		var heal_data: Dictionary = data["heal"]
		config.heal_floating_text_duration = heal_data.get("floatingTextDuration", config.heal_floating_text_duration) as float
		config.heal_hp_bar_duration = heal_data.get("hpBarDuration", config.heal_hp_bar_duration) as float
	
	if data.has("death"):
		var death_data: Dictionary = data["death"]
		config.death_duration = death_data.get("duration", config.death_duration) as float
	
	return config
