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

## 初始层数（默认 1）
var initial_stacks: int = 1

## 最大层数（默认 1 = 不可叠加）
var max_stacks: int = 1

## 溢出策略，取值为 Ability.OVERFLOW_CAP / OVERFLOW_REFRESH / OVERFLOW_REJECT
var overflow_policy: int = 0


func _init(
	config_id: String = "",
	display_name: String = "",
	description: String = "",
	icon: String = "",
	ability_tags: Array[String] = [],
	active_use_components: Array[ActiveUseConfig] = [],
	components: Array[AbilityComponentConfig] = [],
	metadata: Dictionary = {},
	initial_stacks: int = 1,
	max_stacks: int = 1,
	overflow_policy: int = 0
) -> void:
	self.config_id = config_id
	self.display_name = display_name
	self.description = description
	self.icon = icon
	self.ability_tags = ability_tags
	self.active_use_components = active_use_components
	self.components = components
	self.metadata = metadata
	self.initial_stacks = initial_stacks
	self.max_stacks = max_stacks
	self.overflow_policy = overflow_policy


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
	var _initial_stacks: int = 1
	var _max_stacks: int = 1
	var _overflow_policy: int = 0
	
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

	## 声明为可叠层 Ability，配置初始层数 / 上限 / 溢出策略。
	##
	## 不调用本方法 → 默认 1/1/CAP（调 add_stacks 一直 CAP 在 1，对不可叠加 ability 语义安全）。
	## policy 传 Ability.OVERFLOW_CAP / OVERFLOW_REFRESH / OVERFLOW_REJECT。
	func stacks(initial: int, max_val: int, policy: int = Ability.OVERFLOW_CAP) -> AbilityConfigBuilder:
		_initial_stacks = initial
		_max_stacks = max_val
		_overflow_policy = policy
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
			_metadata,
			_initial_stacks,
			_max_stacks,
			_overflow_policy
		)
