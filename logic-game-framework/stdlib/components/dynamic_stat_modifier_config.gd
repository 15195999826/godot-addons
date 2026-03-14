class_name DynamicStatModifierConfig
extends RefCounted
## DynamicStatModifierConfig - 动态属性修改器配置
##
## 定义动态属性修改器的配置：源属性变化时，目标属性的 modifier 值会动态更新。
## 公式：target_attribute += source_attribute * coefficient
##
## 【使用示例】
##
##   # atk += max_hp * 0.01
##   var config := DynamicStatModifierConfig.new("max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.01)


## 源属性名（监听此属性的变化）
var source_attribute: String

## 目标属性名（修改此属性）
var target_attribute: String

## 修改器类型
var modifier_type: AttributeModifier.Type

## 系数：modifier_value = source_value * coefficient
var coefficient: float


func _init(
	p_source_attribute: String,
	p_target_attribute: String,
	p_modifier_type: AttributeModifier.Type,
	p_coefficient: float
) -> void:
	source_attribute = p_source_attribute
	target_attribute = p_target_attribute
	modifier_type = p_modifier_type
	coefficient = p_coefficient
