## RtsUnitAttributeSet - RTS 单位属性集
##
## 直接 extends BaseGeneratedAttributeSet, 在 _init 中通过 _raw.apply_config 注册所有 RTS 属性,
## 不走 LGF AttributeSetGeneratorScript 的代码生成路径(避免修改共享 attributes_config.gd)。
##
## 暴露给调方的属性:
##   hp / max_hp        : 血量, 走 cross-clamp(hp <= max_hp), hp 最低 0
##   atk / def          : 战斗数值, 进入 max(1, atk - def) 伤害公式
##   move_speed         : 像素/秒, 由 frontend / NavAgent 消费
##   attack_speed       : 次/秒, basic attack cooldown 倒计时由 procedure tick 推进
##   attack_range       : 像素, 单位与目标距离 <= attack_range 才允许攻击
class_name RtsUnitAttributeSet
extends BaseGeneratedAttributeSet


const HP := "hp"
const MAX_HP := "max_hp"
const ATK := "atk"
const DEF := "def"
const MOVE_SPEED := "move_speed"
const ATTACK_SPEED := "attack_speed"
const ATTACK_RANGE := "attack_range"


func _init(p_actor_id: String = "") -> void:
	super(p_actor_id)
	_raw.apply_config({
		HP: { "baseValue": 100.0, "minValue": 0.0 },
		MAX_HP: { "baseValue": 100.0, "minValue": 1.0 },
		ATK: { "baseValue": 20.0 },
		DEF: { "baseValue": 0.0 },
		MOVE_SPEED: { "baseValue": 80.0, "minValue": 0.0 },
		ATTACK_SPEED: { "baseValue": 1.0, "minValue": 0.01 },
		ATTACK_RANGE: { "baseValue": 24.0, "minValue": 0.0 },
	})
	_raw.register_cross_attr_clamp(HP, "max", MAX_HP)


# ========== 属性视图 ==========

var hp: float:
	get:
		return _raw.get_current_value(HP)
var max_hp: float:
	get:
		return _raw.get_current_value(MAX_HP)
var atk: float:
	get:
		return _raw.get_current_value(ATK)
var def: float:
	get:
		return _raw.get_current_value(DEF)
var move_speed: float:
	get:
		return _raw.get_current_value(MOVE_SPEED)
var attack_speed: float:
	get:
		return _raw.get_current_value(ATTACK_SPEED)
var attack_range: float:
	get:
		return _raw.get_current_value(ATTACK_RANGE)


# ========== 基础值 setter ==========

func set_hp_base(value: float) -> void:
	_raw.set_base(HP, value)

func set_max_hp_base(value: float) -> void:
	_raw.set_base(MAX_HP, value)

func set_atk_base(value: float) -> void:
	_raw.set_base(ATK, value)

func set_def_base(value: float) -> void:
	_raw.set_base(DEF, value)

func set_move_speed_base(value: float) -> void:
	_raw.set_base(MOVE_SPEED, value)

func set_attack_speed_base(value: float) -> void:
	_raw.set_base(ATTACK_SPEED, value)

func set_attack_range_base(value: float) -> void:
	_raw.set_base(ATTACK_RANGE, value)


# ========== 序列化 ==========

func snapshot() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"atk": atk,
		"def": def,
		"move_speed": move_speed,
		"attack_speed": attack_speed,
		"attack_range": attack_range,
	}
