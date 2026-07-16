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
##     .timeline(MOVE_TIMELINE)                           # 2. 绑定时间线（设查找键+携带注册来源）
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

## 本组件携带的 timeline 资产（注册来源）。经 builder.timeline(data) 设置时非 null，
## 注册链路（如 register_all_timelines）从 config 树收集它统一注册；
## timeline_id 仍是执行期查找键（AbilityExecutionInstance 按 id 查 registry）。
var timeline_data: TimelineData = null

## Tag → Actions 映射列表（异步，按 timeline tag_time 触发）
var tag_actions: Array[TagActionsEntry]

## Timeline 开始时同步触发的 actions（activate 瞬间 / loop 每轮开始）
var on_timeline_start_actions: Array[Action.BaseAction]

## Timeline 结束时同步触发的 actions（timeline 完成 / loop 每轮结束）
var on_timeline_end_actions: Array[Action.BaseAction]

## Execution 被取消时同步触发的清理 actions（仅取消，不等同于成功结束）
var on_cancel_actions: Array[Action.BaseAction]

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
	on_timeline_end_actions: Array[Action.BaseAction] = [],
	on_cancel_actions: Array[Action.BaseAction] = [],
	timeline_data: TimelineData = null
) -> void:
	self.timeline_id = timeline_id
	self.tag_actions = tag_actions
	self.triggers = triggers
	self.trigger_mode = trigger_mode
	self.on_timeline_start_actions = on_timeline_start_actions
	self.on_timeline_end_actions = on_timeline_end_actions
	self.on_cancel_actions = on_cancel_actions
	self.timeline_data = timeline_data


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
	var _timeline_data: TimelineData = null
	var _tag_actions: Array[TagActionsEntry] = []
	var _triggers: Array[TriggerConfig] = []
	var _trigger_mode: String = "any"
	var _on_timeline_start_actions: Array[Action.BaseAction] = []
	var _on_timeline_end_actions: Array[Action.BaseAction] = []
	var _on_cancel_actions: Array[Action.BaseAction] = []
	
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
	
	## 绑定 timeline（必填）：一次调用同时设置执行期查找键（timeline_id = data.id）
	## 并让 config 携带该 TimelineData 作为注册来源（注册链路从 config 树收集统一注册）。
	## timeline 必须是 static 声明的常量实例——registry 对同 id 异引用会 crash。
	func timeline(data: TimelineData) -> ActivateInstanceConfigBuilder:
		Log.assert_crash(data != null and data.id != "", "ActivateInstanceConfig", "timeline(data) 要求非空且 id 非空")
		_timeline_data = data
		_timeline_id = data.id
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

	## 配置 execution 被取消时必跑的清理 actions。
	func on_cancel(actions: Array[Action.BaseAction]) -> ActivateInstanceConfigBuilder:
		_on_cancel_actions.append_array(actions)
		return self

	## 构建 ActivateInstanceConfig
	## 验证必填字段，缺失时触发断言错误
	func build() -> ActivateInstanceConfig:
		Log.assert_crash(_timeline_id != "", "ActivateInstanceConfig", "timeline is required")
		return ActivateInstanceConfig.new(
			_timeline_id,
			_tag_actions,
			_triggers,
			_trigger_mode,
			_on_timeline_start_actions,
			_on_timeline_end_actions,
			_on_cancel_actions,
			_timeline_data
		)
