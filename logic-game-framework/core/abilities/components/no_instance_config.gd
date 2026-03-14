## NoInstance 组件配置
##
## 用于配置 NoInstanceComponent，定义被动触发的 Action 链。
## 不创建执行实例，事件触发时直接执行 Action。
## 推荐使用 Builder 模式构造，提供清晰的可读性和 IDE 自动补全。
##
## [b]注意[/b]
##
## 与 ActiveUseConfig 不同，NoInstanceConfig [b]没有默认触发器[/b]，
## 必须显式调用 .trigger() 方法配置触发条件。
##
## [b]推荐链式调用顺序[/b]
##
## 建议按照 "何时触发 → 做什么" 的语义顺序：
## [codeblock]
## var config := NoInstanceConfig.builder() \
##     .trigger(TriggerConfig.new("damage", filter_fn)) # 1. 何时触发（必须配置）
##     .action(ReflectDamageAction.new(...))            # 2. 执行什么动作
##     .build()
## [/codeblock]
class_name NoInstanceConfig
extends AbilityComponentConfig


## 触发器列表
var triggers: Array[TriggerConfig]

## 触发模式: "any" 或 "all"
var trigger_mode: String

## Action 列表（触发时执行）
var actions: Array[Action.BaseAction] = []


func _init(
	triggers: Array[TriggerConfig] = [],
	actions: Array[Action.BaseAction] = [],
	trigger_mode: String = "any"
) -> void:
	self.triggers = triggers
	self.actions.assign(actions)
	self.trigger_mode = trigger_mode


## 创建对应的 NoInstanceComponent 实例
func create_component() -> AbilityComponent:
	return NoInstanceComponent.new(self)


## 创建 Builder
static func builder() -> NoInstanceConfigBuilder:
	return NoInstanceConfigBuilder.new()


## NoInstanceConfig Builder
##
## 使用链式调用构建 NoInstanceConfig，提供清晰的可读性。
## 必填字段：至少一个 trigger
##
## 推荐调用顺序：trigger → action
class NoInstanceConfigBuilder:
	extends RefCounted
	
	var _triggers: Array[TriggerConfig] = []
	var _trigger_mode: String = "any"
	var _actions: Array[Action.BaseAction] = []
	
	# ========== 1. 触发配置 ==========
	
	## 添加触发器（必须配置至少一个）
	## 被动技能必须显式指定监听的事件类型
	func trigger(config: TriggerConfig) -> NoInstanceConfigBuilder:
		_triggers.append(config)
		return self
	
	## 设置触发模式（可选，默认 "any"）
	## "any": 任一触发器匹配即触发
	## "all": 所有触发器都匹配才触发
	func trigger_mode(value: String) -> NoInstanceConfigBuilder:
		_trigger_mode = value
		return self
	
	# ========== 2. 动作配置 ==========
	
	## 添加动作（触发时执行）
	## 可多次调用添加多个动作，按顺序执行
	func action(act: Action.BaseAction) -> NoInstanceConfigBuilder:
		_actions.append(act)
		return self
	
	## 批量添加动作
	func actions(acts: Array[Action.BaseAction]) -> NoInstanceConfigBuilder:
		_actions.append_array(acts)
		return self
	
	## 构建 NoInstanceConfig
	## 验证必填字段，缺失时触发断言错误
	func build() -> NoInstanceConfig:
		Log.assert_crash(not _triggers.is_empty(), "NoInstanceConfig", "at least one trigger is required")
		return NoInstanceConfig.new(
			_triggers,
			_actions,
			_trigger_mode
		)
