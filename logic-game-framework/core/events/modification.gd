## Modification - 事件修改操作
##
## 表示对事件字段的一次修改操作。
## 用于 Pre 阶段处理器返回的 Intent 中，描述如何修改事件的数值字段。
##
## ========== 操作类型 ==========
##
## - SET: 直接设置值（覆盖原值）
## - ADD: 加法修改（原值 + value）
## - MULTIPLY: 乘法修改（原值 * value）
##
## 计算顺序：SET → ADD → MULTIPLY
##
## ========== 使用示例 ==========
##
## @example 创建修改
## ```gdscript
## # 伤害减半
## var mod := Modification.multiply("damage", 0.5, "armor_buff", "护甲")
##
## # 伤害 -10
## var mod2 := Modification.add("damage", -10.0, "shield", "护盾")
##
## # 直接设置为 0（免疫）
## var mod3 := Modification.set_value("damage", 0.0, "immune", "免疫")
## ```
class_name Modification
extends RefCounted


## 操作类型枚举
enum Operation {
	SET,      ## 直接设置值
	ADD,      ## 加法修改
	MULTIPLY, ## 乘法修改
}


## 要修改的字段名
var field: String

## 操作类型
var operation: Operation

## 修改值
var value: float

## 修改来源 ID（用于追踪）
var source_id: String

## 修改来源名称（用于显示）
var source_name: String


func _init(
	p_field: String,
	p_operation: Operation,
	p_value: float,
	p_source_id: String = "",
	p_source_name: String = ""
) -> void:
	field = p_field
	operation = p_operation
	value = p_value
	source_id = p_source_id
	source_name = p_source_name


# ========== 静态工厂方法 ==========


## 创建 SET 操作（直接设置值）
static func set_value(p_field: String, p_value: float, p_source_id: String = "", p_source_name: String = "") -> Modification:
	return Modification.new(p_field, Operation.SET, p_value, p_source_id, p_source_name)


## 创建 ADD 操作（加法修改）
static func add(p_field: String, p_value: float, p_source_id: String = "", p_source_name: String = "") -> Modification:
	return Modification.new(p_field, Operation.ADD, p_value, p_source_id, p_source_name)


## 创建 MULTIPLY 操作（乘法修改）
static func multiply(p_field: String, p_value: float, p_source_id: String = "", p_source_name: String = "") -> Modification:
	return Modification.new(p_field, Operation.MULTIPLY, p_value, p_source_id, p_source_name)


# ========== 序列化 ==========


## 转换为 Dictionary（用于日志/调试）
func to_dict() -> Dictionary:
	return {
		"field": field,
		"operation": _operation_to_string(operation),
		"value": value,
		"sourceId": source_id,
		"sourceName": source_name,
	}


## 获取操作符号（用于日志显示）
func get_operation_sign() -> String:
	match operation:
		Operation.SET:
			return "="
		Operation.ADD:
			return "+" if value >= 0 else ""
		Operation.MULTIPLY:
			return "x"
		_:
			return "?"


# ========== 内部方法 ==========


static func _operation_to_string(op: Operation) -> String:
	match op:
		Operation.SET:
			return "set"
		Operation.ADD:
			return "add"
		Operation.MULTIPLY:
			return "multiply"
		_:
			return "unknown"
