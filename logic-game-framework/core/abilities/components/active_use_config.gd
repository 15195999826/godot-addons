## ActiveUse 组件配置
##
## 用于配置 ActiveUseComponent，定义主动技能的触发、条件、消耗和执行。
## 继承 ActivateInstanceConfig 的所有配置，额外增加条件和消耗。
## 推荐使用 Builder 模式构造，提供清晰的可读性和 IDE 自动补全。
##
## [b]默认触发器[/b]
##
## ActiveUseConfig 专为主动技能设计，默认监听 [code]GameEvent.ABILITY_ACTIVATE_EVENT[/code]，
## 并自动过滤匹配当前 Ability 实例的事件（abilityInstanceId == ability.id）。
## 因此大多数主动技能无需显式配置 trigger，除非需要自定义触发逻辑。
##
## [b]推荐链式调用顺序[/b]
##
## 建议按照 "何时触发 → 执行什么 → 怎么执行 → 前置条件" 的语义顺序：
## [codeblock]
## var config := ActiveUseConfig.builder() \
##     .trigger(...)                                      # 1. 何时触发（可选，有默认值）
##     .timeline_id(TIMELINE_ID.SLASH)                    # 2. 使用哪个时间线
##     .on_timeline_start([StageCueAction...])            # 3a. 同步：每轮 timeline 开始
##     .on_tag(TimelineTags.HIT, [DamageAction...])       # 3b. 异步：timeline 时间点
##     .on_timeline_end([...])                            # 3c. 同步：每轮 timeline 结束（可选）
##     .condition(CooldownCondition.new())                # 4. 前置条件
##     .cost(TimedCooldownCost.new(2000.0))               # 5. 消耗
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
class_name ActiveUseConfig
extends AbilityComponentConfig


## Timeline ID
var timeline_id: String

## Tag → Actions 映射列表（异步，按 timeline tag_time 触发）
var tag_actions: Array[TagActionsEntry]

## Timeline 开始时同步触发的 actions（activate 瞬间 / loop 每轮开始）
var on_timeline_start_actions: Array[Action.BaseAction]

## Timeline 结束时同步触发的 actions（timeline 完成 / loop 每轮结束）
var on_timeline_end_actions: Array[Action.BaseAction]

## 触发器列表（可选，默认监听 AbilityActivateEvent）
var triggers: Array[TriggerConfig]

## 触发模式: "any" 或 "all"
var trigger_mode: String

## 条件列表（全部满足才能激活）
var conditions: Array[Condition] = []

## 消耗列表（激活时扣除）
var costs: Array[Cost] = []


func _init(
	timeline_id: String = "",
	tag_actions: Array[TagActionsEntry] = [],
	conditions: Array[Condition] = [],
	costs: Array[Cost] = [],
	triggers: Array[TriggerConfig] = [],
	trigger_mode: String = "any",
	on_timeline_start_actions: Array[Action.BaseAction] = [],
	on_timeline_end_actions: Array[Action.BaseAction] = []
) -> void:
	self.timeline_id = timeline_id
	self.tag_actions = tag_actions
	self.conditions.assign(conditions)
	self.costs.assign(costs)
	self.triggers = triggers
	self.trigger_mode = trigger_mode
	self.on_timeline_start_actions = on_timeline_start_actions
	self.on_timeline_end_actions = on_timeline_end_actions


## 创建对应的 ActiveUseComponent 实例
func create_component() -> AbilityComponent:
	return ActiveUseComponent.new(self)


## 创建 Builder
static func builder() -> ActiveUseConfigBuilder:
	return ActiveUseConfigBuilder.new()


## ActiveUseConfig Builder
##
## 使用链式调用构建 ActiveUseConfig，提供清晰的可读性。
## 必填字段：timeline_id
##
## 推荐调用顺序：trigger → timeline_id → on_tag → condition → cost
class ActiveUseConfigBuilder:
	extends RefCounted

	var _timeline_id: String = ""
	var _tag_actions: Array[TagActionsEntry] = []
	var _triggers: Array[TriggerConfig] = []
	var _trigger_mode: String = "any"
	var _conditions: Array[Condition] = []
	var _costs: Array[Cost] = []
	var _on_timeline_start_actions: Array[Action.BaseAction] = []
	var _on_timeline_end_actions: Array[Action.BaseAction] = []
	
	# ========== 1. 触发配置 ==========
	
	## 添加触发器（可选）
	## 默认监听 GameEvent.ABILITY_ACTIVATE_EVENT 并匹配当前 Ability 实例。
	## 仅在需要自定义触发逻辑时调用此方法。
	func trigger(config: TriggerConfig) -> ActiveUseConfigBuilder:
		_triggers.append(config)
		return self
	
	## 设置触发模式（可选，默认 "any"）
	## "any": 任一触发器匹配即触发
	## "all": 所有触发器都匹配才触发
	func trigger_mode(value: String) -> ActiveUseConfigBuilder:
		_trigger_mode = value
		return self
	
	# ========== 2. 时间线配置 ==========
	
	## 设置 Timeline ID（必填）
	## 指定技能执行时使用的时间线定义
	func timeline_id(value: String) -> ActiveUseConfigBuilder:
		_timeline_id = value
		return self
	
	## 添加 Tag -> Actions 映射（异步，按 timeline tag_time 触发）
	func on_tag(tag: String, actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		_tag_actions.append(TagActionsEntry.new(tag, actions))
		return self

	## 配置 timeline 开始时同步触发的 actions（激活瞬间 / loop 每轮开始）
	func on_timeline_start(actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		_on_timeline_start_actions.append_array(actions)
		return self

	## 配置 timeline 结束时同步触发的 actions（timeline 完成 / loop 每轮结束）
	func on_timeline_end(actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		_on_timeline_end_actions.append_array(actions)
		return self

	# ========== 3. 条件和消耗 ==========

	## 添加前置条件（可选）
	## 所有条件满足才能激活技能
	func condition(cond: Condition) -> ActiveUseConfigBuilder:
		_conditions.append(cond)
		return self

	## 添加消耗（可选）
	## 激活技能时扣除的资源
	func cost(c: Cost) -> ActiveUseConfigBuilder:
		_costs.append(c)
		return self

	## 构建 ActiveUseConfig
	## 验证必填字段，缺失时触发断言错误
	func build() -> ActiveUseConfig:
		Log.assert_crash(_timeline_id != "", "ActiveUseConfig", "timeline_id is required")
		return ActiveUseConfig.new(
			_timeline_id,
			_tag_actions,
			_conditions,
			_costs,
			_triggers,
			_trigger_mode,
			_on_timeline_start_actions,
			_on_timeline_end_actions
		)
