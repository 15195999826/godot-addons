class_name StatModifierConfig
extends AbilityComponentConfig
## StatModifier 组件配置
##
## 定义属性修改器的配置数据，由 Ability._resolve_components() 解析为 StatModifierComponent 实例。
## 每个 Ability 实例独立创建 Component，避免共享状态污染。
##
## 推荐使用 Builder 模式构造：
## [codeblock]
## var config := StatModifierConfig.builder() \
##     .modifier("def", AttributeModifier.Type.ADD_BASE, 10.0) \
##     .modifier("atk", AttributeModifier.Type.MUL_BASE, 0.2) \
##     .build()
## [/codeblock]


## 单条修改器配置
class ModifierEntry:
	extends RefCounted

	var attribute_name: String
	var modifier_type: AttributeModifier.Type
	var value: float

	func _init(p_attribute_name: String, p_modifier_type: AttributeModifier.Type, p_value: float) -> void:
		attribute_name = p_attribute_name
		modifier_type = p_modifier_type
		value = p_value


## 修改器配置数组
var modifier_configs: Array[ModifierEntry]


func _init(configs: Array[ModifierEntry] = []) -> void:
	modifier_configs = configs


## 创建对应的 StatModifierComponent 实例
func create_component() -> AbilityComponent:
	return StatModifierComponent.new(modifier_configs)


## 创建 Builder
static func builder() -> StatModifierConfigBuilder:
	return StatModifierConfigBuilder.new()


## StatModifierConfig Builder
##
## 使用链式调用构建 StatModifierConfig，避免手写配置。
## 至少需要一个 modifier。
class StatModifierConfigBuilder:
	extends RefCounted

	var _configs: Array[ModifierEntry] = []

	## 添加属性修改器
	## [br][param attribute_name] 属性名（如 "def", "atk", "hp"）
	## [br][param modifier_type] 修改器类型（使用 AttributeModifier.Type 枚举）
	## [br][param value] 修改值
	func modifier(attribute_name: String, modifier_type: AttributeModifier.Type, value: float) -> StatModifierConfigBuilder:
		_configs.append(ModifierEntry.new(attribute_name, modifier_type, value))
		return self

	## 构建 StatModifierConfig
	## 验证至少有一个 modifier
	func build() -> StatModifierConfig:
		Log.assert_crash(not _configs.is_empty(), "StatModifierConfig", "at least one modifier is required")
		return StatModifierConfig.new(_configs)
