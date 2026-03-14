class_name DynamicStatModifierComponentConfig
extends AbilityComponentConfig
## DynamicStatModifierComponentConfig - 动态属性修改器组件配置
##
## 作为 DynamicStatModifierConfig 的 Config wrapper，
## 用于 AbilityConfigBuilder.component_config() 链式调用。
## Ability._resolve_components() 会将此配置 resolve 为 DynamicStatModifierComponent。
##
## 【使用示例】
##
##   AbilityConfig.builder()
##       .component_config(DynamicStatModifierComponentConfig.new(
##           DynamicStatModifierConfig.new("max_hp", "atk", AttributeModifier.Type.ADD_BASE, 0.01)
##       ))
##       .build()


## 动态修改器配置
var modifier_config: DynamicStatModifierConfig


func _init(p_config: DynamicStatModifierConfig) -> void:
	modifier_config = p_config


## 创建对应的 DynamicStatModifierComponent 实例
func create_component() -> AbilityComponent:
	return DynamicStatModifierComponent.new(modifier_config)
