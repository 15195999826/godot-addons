## Ability 配置
##
## 定义 Ability 的完整配置，包括基本信息和组件列表。
## 推荐使用 Builder 模式构造，提供清晰的可读性和 IDE 自动补全。
##
## 示例:
## [codeblock]
## var config := AbilityConfig.builder() \
##     .config_id("skill_slash") \
##     .display_name("横扫斩") \
##     .description("近战攻击") \
##     .ability_tags(["skill", "active", "melee"]) \
##     .active_use(ActiveUseConfig.builder()...) \
##     .component_config(StatModifierConfig.builder()...) \
##     .build()
## [/codeblock]
class_name AbilityConfig
extends RefCounted


## 配置 ID（必填，用于标识配置）
var config_id: String

## 显示名称
var display_name: String

## 描述
var description: String

## 图标路径
var icon: String

## 标签列表
var ability_tags: Array[String]

## 主动使用组件配置列表
var active_use_components: Array[ActiveUseConfig]

## 效果组件配置列表（被动触发、Buff 等）
var components: Array[AbilityComponentConfig]

## 自定义元数据（游戏层可自由附加，如施法距离、伤害类型等）
var metadata: Dictionary = {}


func _init(
	config_id: String = "",
	display_name: String = "",
	description: String = "",
	icon: String = "",
	ability_tags: Array[String] = [],
	active_use_components: Array[ActiveUseConfig] = [],
	components: Array[AbilityComponentConfig] = [],
	metadata: Dictionary = {}
) -> void:
	self.config_id = config_id
	self.display_name = display_name
	self.description = description
	self.icon = icon
	self.ability_tags = ability_tags
	self.active_use_components = active_use_components
	self.components = components
	self.metadata = metadata


## 创建 Builder
static func builder() -> AbilityConfigBuilder:
	return AbilityConfigBuilder.new()


## AbilityConfig Builder
##
## 使用链式调用构建 AbilityConfig，提供清晰的可读性。
## 必填字段：config_id
class AbilityConfigBuilder:
	extends RefCounted
	
	var _config_id: String = ""
	var _display_name: String = ""
	var _description: String = ""
	var _icon: String = ""
	var _ability_tags: Array[String] = []
	var _active_use_components: Array[ActiveUseConfig] = []
	var _components: Array[AbilityComponentConfig] = []
	var _metadata: Dictionary = {}
	
	## 设置配置 ID（必填）
	## @required
	func config_id(value: String) -> AbilityConfigBuilder:
		_config_id = value
		return self
	
	## 设置显示名称
	func display_name(value: String) -> AbilityConfigBuilder:
		_display_name = value
		return self
	
	## 设置描述
	func description(value: String) -> AbilityConfigBuilder:
		_description = value
		return self
	
	## 设置图标路径
	func icon(value: String) -> AbilityConfigBuilder:
		_icon = value
		return self
	
	## 设置标签列表
	func ability_tags(value: Array[String]) -> AbilityConfigBuilder:
		_ability_tags = value
		return self
	
	## 添加主动使用组件
	func active_use(config: ActiveUseConfig) -> AbilityConfigBuilder:
		_active_use_components.append(config)
		return self
	
	## 添加效果组件配置
	func component_config(config: AbilityComponentConfig) -> AbilityConfigBuilder:
		_components.append(config)
		return self
	
	## 添加元数据键值对
	func meta(key: String, value: Variant) -> AbilityConfigBuilder:
		_metadata[key] = value
		return self
	
	## 构建 AbilityConfig
	## 验证必填字段，缺失时触发断言错误
	func build() -> AbilityConfig:
		Log.assert_crash(_config_id != "", "AbilityConfig", "config_id is required")
		return AbilityConfig.new(
			_config_id,
			_display_name,
			_description,
			_icon,
			_ability_tags,
			_active_use_components,
			_components,
			_metadata
		)
