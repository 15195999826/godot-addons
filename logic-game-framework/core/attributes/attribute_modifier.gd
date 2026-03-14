class_name AttributeModifier
extends RefCounted
## 属性修改器
##
## 表示对某个属性的一次修改。使用 enum Type 替代字符串常量，提供类型安全。
## 通过工厂方法创建实例。

enum Type {
	ADD_BASE,
	MUL_BASE,
	ADD_FINAL,
	MUL_FINAL,
}

var id: String
var attribute_name: String
var modifier_type: Type
var value: float
var source: String


func _init(p_id: String, p_attribute_name: String, p_modifier_type: Type, p_value: float, p_source: String = "") -> void:
	id = p_id
	attribute_name = p_attribute_name
	modifier_type = p_modifier_type
	value = p_value
	source = p_source


## 创建 AddBase 修改器
static func create_add_base(p_id: String, p_attribute_name: String, p_value: float, p_source: String = "") -> AttributeModifier:
	return AttributeModifier.new(p_id, p_attribute_name, Type.ADD_BASE, p_value, p_source)


## 创建 MulBase 修改器
static func create_mul_base(p_id: String, p_attribute_name: String, p_value: float, p_source: String = "") -> AttributeModifier:
	return AttributeModifier.new(p_id, p_attribute_name, Type.MUL_BASE, p_value, p_source)


## 创建 AddFinal 修改器
static func create_add_final(p_id: String, p_attribute_name: String, p_value: float, p_source: String = "") -> AttributeModifier:
	return AttributeModifier.new(p_id, p_attribute_name, Type.ADD_FINAL, p_value, p_source)


## 创建 MulFinal 修改器
static func create_mul_final(p_id: String, p_attribute_name: String, p_value: float, p_source: String = "") -> AttributeModifier:
	return AttributeModifier.new(p_id, p_attribute_name, Type.MUL_FINAL, p_value, p_source)


## 序列化为 Dictionary（用于存档）
func serialize() -> Dictionary:
	var result := {
		"id": id,
		"attributeName": attribute_name,
		"modifierType": Type.keys()[modifier_type],
		"value": value,
	}
	if source != "":
		result["source"] = source
	return result


## 从 Dictionary 反序列化
static func deserialize(data: Dictionary) -> AttributeModifier:
	var type_str := str(data.get("modifierType", ""))
	var parsed_type := _parse_type(type_str)
	return AttributeModifier.new(
		str(data.get("id", "")),
		str(data.get("attributeName", "")),
		parsed_type,
		float(data.get("value", 0.0)),
		str(data.get("source", "")),
	)


## 解析类型字符串为 enum
static func _parse_type(type_str: String) -> Type:
	match type_str:
		"ADD_BASE":
			return Type.ADD_BASE
		"MUL_BASE":
			return Type.MUL_BASE
		"ADD_FINAL":
			return Type.ADD_FINAL
		"MUL_FINAL":
			return Type.MUL_FINAL
		_:
			push_warning("AttributeModifier: Unknown type '%s', defaulting to ADD_BASE" % type_str)
			return Type.ADD_BASE
