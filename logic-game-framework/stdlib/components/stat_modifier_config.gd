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
##
## §0.X stack-scaled StatModifier (Phase 04 Demon Form 前置):
## .scale_by_stacks() 启用后, 实际 modifier value = config.value * ability.stacks。
## Ability.add_stacks/remove_stacks/set_stacks 在 stacks 变化后自动通过
## AbilityComponent.on_stacks_changed 钩子原子更新所有 modifier value
## (走 RawAttributeSet.update_modifier，不 remove+add，避免 breakdown 闪烁与 dirty 两次)。


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

## §0.X: 启用 stacks-based scaling
var scales_by_stacks: bool = false


func _init(configs: Array[ModifierEntry] = [], p_scales_by_stacks: bool = false) -> void:
	modifier_configs = configs
	scales_by_stacks = p_scales_by_stacks


## 创建对应的 StatModifierComponent 实例
func create_component() -> AbilityComponent:
	return StatModifierComponent.new(modifier_configs, scales_by_stacks)


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
	var _scales_by_stacks: bool = false

	## 添加属性修改器
	## [br][param attribute_name] 属性名（如 "def", "atk", "hp"）
	## [br][param modifier_type] 修改器类型（使用 AttributeModifier.Type 枚举）
	## [br][param value] 修改值
	func modifier(attribute_name: String, modifier_type: AttributeModifier.Type, value: float) -> StatModifierConfigBuilder:
		_configs.append(ModifierEntry.new(attribute_name, modifier_type, value))
		return self

	## §0.X: 启用 stacks-based scaling
	## 启用后 modifier 实际 value = config.value * ability.stacks; Ability stacks
	## 变化时通过 on_stacks_changed 自动用 update_modifier 原子更新。
	func scale_by_stacks() -> StatModifierConfigBuilder:
		_scales_by_stacks = true
		return self

	## 构建 StatModifierConfig
	## 验证至少有一个 modifier
	func build() -> StatModifierConfig:
		Log.assert_crash(not _configs.is_empty(), "StatModifierConfig", "at least one modifier is required")
		return StatModifierConfig.new(_configs, _scales_by_stacks)
