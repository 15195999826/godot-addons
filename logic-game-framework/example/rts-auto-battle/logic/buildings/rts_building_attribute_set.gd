## RtsBuildingAttributeSet - RTS 建筑属性集 (P2.5)
##
## 与 RtsUnitAttributeSet 同构: 直接 extends BaseGeneratedAttributeSet, 在 _init 中 apply_config
## 注册建筑专属属性, 不走 LGF AttributeSetGeneratorScript 的代码生成路径。
##
## 暴露给调方的属性:
##   hp / max_hp                    : 血量 (cross-clamp hp <= max_hp, hp 最低 0)
##   production_speed_multiplier    : 生产速度倍率 (默认 1.0, 留给 P2.6+ 升级 / buff 用)
##
## 决策来源: phase-2-core-systems.md §P2.5 (Production System + Building Factory)
class_name RtsBuildingAttributeSet
extends BaseGeneratedAttributeSet


const HP := "hp"
const MAX_HP := "max_hp"
const PRODUCTION_SPEED_MULTIPLIER := "production_speed_multiplier"


func _init(p_actor_id: String = "") -> void:
	super(p_actor_id)
	_raw.apply_config({
		HP: { "baseValue": 100.0, "minValue": 0.0 },
		MAX_HP: { "baseValue": 100.0, "minValue": 1.0 },
		PRODUCTION_SPEED_MULTIPLIER: { "baseValue": 1.0, "minValue": 0.01 },
	})
	_raw.register_cross_attr_clamp(HP, "max", MAX_HP)


# ========== 属性视图 ==========

var hp: float:
	get:
		return _raw.get_current_value(HP)
var max_hp: float:
	get:
		return _raw.get_current_value(MAX_HP)
var production_speed_multiplier: float:
	get:
		return _raw.get_current_value(PRODUCTION_SPEED_MULTIPLIER)


# ========== 基础值 setter ==========

func set_hp_base(value: float) -> void:
	_raw.set_base(HP, value)

func set_max_hp_base(value: float) -> void:
	_raw.set_base(MAX_HP, value)

func set_production_speed_multiplier_base(value: float) -> void:
	_raw.set_base(PRODUCTION_SPEED_MULTIPLIER, value)


# ========== 序列化 ==========

func snapshot() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"production_speed_multiplier": production_speed_multiplier,
	}
