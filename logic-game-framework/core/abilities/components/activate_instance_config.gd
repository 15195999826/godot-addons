## ActivateInstance 组件配置
##
## 用于配置 ActivateInstanceComponent，定义触发器和 Timeline 执行。
## 推荐使用 Builder 模式构造，提供清晰的可读性和 IDE 自动补全。
##
## [b]注意[/b]
##
## 与 ActiveUseConfig 不同，ActivateInstanceConfig [b]没有默认触发器[/b]，
## 必须显式调用 .trigger() 方法配置触发条件。
##
## [b]推荐链式调用顺序[/b]
##
## 建议按照 "何时触发 → 执行什么 → 怎么执行" 的语义顺序：
## [codeblock]
## var config := ActivateInstanceConfig.builder() \
##     .trigger(TriggerConfig.new(...))                   # 1. 何时触发（必须配置）
##     .timeline_id(TIMELINE_ID.MOVE)                     # 2. 使用哪个时间线
##     .on_timeline_start([StartMoveAction...])           # 3a. 同步：每轮 timeline 开始
##     .on_tag(TimelineTags.EXECUTE, [ApplyMoveAction...])# 3b. 异步：timeline 时间点
##     .on_timeline_end([...])                            # 3c. 同步：每轮 timeline 结束
##     .build()
## [/codeblock]
##
## [b]on_timeline_start / on_timeline_end 与 on_tag 的区别[/b]
##
## - on_timeline_start/end：同步执行（在 activate 调用链 / tick 调用链里立即跑），
##   用于需要原子保证的操作（如 grid.reserve_tile、StageCueAction 发送动画提示）
## - on_tag：异步执行（按 timeline tag_time 在对应 tick 里触发），
##   用于可以延迟的时间点事件（如 DamageAction 在 HIT tag 时造成伤害）
##
## loop 模式下：每轮 timeline 开始/结束都会触发 on_timeline_start/end。
class_name ActivateInstanceConfig
extends AbilityComponentConfig


## Timeline ID
var timeline_id: String

## Tag → Actions 映射列表（异步，按 timeline tag_time 触发）
var tag_actions: Array[TagActionsEntry]

## Timeline 开始时同步触发的 actions（activate 瞬间 / loop 每轮开始）
var on_timeline_start_actions: Array[Action.BaseAction]

## Timeline 结束时同步触发的 actions（timeline 完成 / loop 每轮结束）
var on_timeline_end_actions: Array[Action.BaseAction]

## 触发器列表
var triggers: Array[TriggerConfig]

## 触发模式: "any" 或 "all"
var trigger_mode: String


func _init(
	timeline_id: String = "",
	tag_actions: Array[TagActionsEntry] = [],
	triggers: Array[TriggerConfig] = [],
	trigger_mode: String = "any",
	on_timeline_start_actions: Array[Action.BaseAction] = [],
	on_timeline_end_actions: Array[Action.BaseAction] = []
) -> void:
	self.timeline_id = timeline_id
	self.tag_actions = tag_actions
	self.triggers = triggers
	self.trigger_mode = trigger_mode
	self.on_timeline_start_actions = on_timeline_start_actions
	self.on_timeline_end_actions = on_timeline_end_actions


## 创建对应的 ActivateInstanceComponent 实例
func create_component() -> AbilityComponent:
	return ActivateInstanceComponent.new(self)


## 创建 Builder
static func builder() -> ActivateInstanceConfigBuilder:
	return ActivateInstanceConfigBuilder.new()


## ActivateInstanceConfig Builder
##
## 使用链式调用构建 ActivateInstanceConfig，提供清晰的可读性。
## 必填字段：timeline_id
##
## 推荐调用顺序：trigger → timeline_id → on_tag
class ActivateInstanceConfigBuilder:
	extends RefCounted

	var _timeline_id: String = ""
	var _tag_actions: Array[TagActionsEntry] = []
	var _triggers: Array[TriggerConfig] = []
	var _trigger_mode: String = "any"
	var _on_timeline_start_actions: Array[Action.BaseAction] = []
	var _on_timeline_end_actions: Array[Action.BaseAction] = []
	
	# ========== 1. 触发配置 ==========
	
	## 添加触发器（必须配置）
	## 与 ActiveUseConfig 不同，此组件没有默认触发器
	func trigger(config: TriggerConfig) -> ActivateInstanceConfigBuilder:
		_triggers.append(config)
		return self
	
	## 设置触发模式（可选，默认 "any"）
	## "any": 任一触发器匹配即触发
	## "all": 所有触发器都匹配才触发
	func trigger_mode(value: String) -> ActivateInstanceConfigBuilder:
		_trigger_mode = value
		return self
	
	# ========== 2. 时间线配置 ==========
	
	## 设置 Timeline ID（必填）
	## 指定执行时使用的时间线定义
	func timeline_id(value: String) -> ActivateInstanceConfigBuilder:
		_timeline_id = value
		return self
	
	## 添加 Tag -> Actions 映射（异步，按 timeline tag_time 触发）
	func on_tag(tag: String, actions: Array[Action.BaseAction]) -> ActivateInstanceConfigBuilder:
		_tag_actions.append(TagActionsEntry.new(tag, actions))
		return self

	## 配置 timeline 开始时同步触发的 actions（激活瞬间 / loop 每轮开始）
	func on_timeline_start(actions: Array[Action.BaseAction]) -> ActivateInstanceConfigBuilder:
		_on_timeline_start_actions.append_array(actions)
		return self

	## 配置 timeline 结束时同步触发的 actions（timeline 完成 / loop 每轮结束）
	func on_timeline_end(actions: Array[Action.BaseAction]) -> ActivateInstanceConfigBuilder:
		_on_timeline_end_actions.append_array(actions)
		return self

	## 构建 ActivateInstanceConfig
	## 验证必填字段，缺失时触发断言错误
	func build() -> ActivateInstanceConfig:
		Log.assert_crash(_timeline_id != "", "ActivateInstanceConfig", "timeline_id is required")
		return ActivateInstanceConfig.new(
			_timeline_id,
			_tag_actions,
			_triggers,
			_trigger_mode,
			_on_timeline_start_actions,
			_on_timeline_end_actions
		)
