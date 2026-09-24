## ActiveUse 组件配置
##
## 用于配置 ActiveUseComponent：在 ActivateInstanceConfig（触发器 + Timeline 执行）之上加条件和消耗。
## 配置层级镜像组件层级（ActiveUseComponent extends ActivateInstanceComponent）。
## 推荐使用 Builder 模式构造，提供清晰的可读性和 IDE 自动补全。
##
## [b]默认触发器[/b]
##
## ActiveUseConfig 专为主动技能设计，triggers 为空时 ActiveUseComponent 默认用
## [code]TriggerConfig.ABILITY_ACTIVATE[/code]：只收寄给本 Ability 实例的 ABILITY_ACTIVATE_EVENT（定向投递，
## 收件人由地址保证）。因此大多数主动技能无需显式配置 trigger，除非需要自定义触发逻辑。
##
## [b]推荐链式调用顺序[/b]
##
## 建议按照 "何时触发 → 执行什么 → 怎么执行 → 前置条件" 的语义顺序：
## [codeblock]
## var config := ActiveUseConfig.builder() \
##     .trigger(...)                                      # 1. 何时触发（可选，有默认值）
##     .timeline(SLASH_TIMELINE)                          # 2. 绑定时间线（声明即冻结 tags）
##     .on_timeline_start([StageCueAction...])            # 3a. 同步：每轮 timeline 开始
##     .on_tag(TimelineTags.HIT, [DamageAction...])       # 3b. 异步：timeline 时间点
##     .on_timeline_end([...])                            # 3c. 同步：每轮 timeline 结束（可选）
##     .condition(CooldownCondition.new())                # 4. 前置条件
##     .cost(TimedCooldownCost.new(2000.0))               # 5. 消耗
##     .build()
## [/codeblock]
##
## on_timeline_start / on_timeline_end 与 on_tag 的区别见 ActivateInstanceConfig。
class_name ActiveUseConfig
extends ActivateInstanceConfig


## 条件列表（全部满足才能激活）
var conditions: Array[Condition] = []

## 消耗列表（激活时扣除）
var costs: Array[Cost] = []


func _init(
	p_timeline: TimelineData,
	p_tag_actions: Array[TagActionsEntry] = [],
	p_triggers: Array[TriggerConfig] = [],
	p_trigger_mode: String = "any",
	p_on_timeline_start_actions: Array[Action.BaseAction] = [],
	p_on_timeline_end_actions: Array[Action.BaseAction] = [],
	p_on_cancel_actions: Array[Action.BaseAction] = [],
	p_conditions: Array[Condition] = [],
	p_costs: Array[Cost] = []
) -> void:
	super(p_timeline, p_tag_actions, p_triggers, p_trigger_mode,
		p_on_timeline_start_actions, p_on_timeline_end_actions, p_on_cancel_actions)
	conditions.assign(p_conditions)
	costs.assign(p_costs)


## 创建对应的 ActiveUseComponent 实例
func create_component() -> AbilityComponent:
	return ActiveUseComponent.new(self)


## 创建 Builder
static func builder() -> ActiveUseConfigBuilder:
	return ActiveUseConfigBuilder.new()


## ActiveUseConfig Builder
##
## 继承 ActivateInstanceConfigBuilder 的全部链式方法（协变返回覆盖，链上任意位置之后都能接 condition / cost），
## 额外提供 condition / cost。必填字段：timeline。
class ActiveUseConfigBuilder:
	extends ActivateInstanceConfig.ActivateInstanceConfigBuilder

	var _conditions: Array[Condition] = []
	var _costs: Array[Cost] = []

	# ========== 1. 触发配置 ==========

	## 添加触发器（可选）。不配置时 ActiveUseComponent 默认用 TriggerConfig.ABILITY_ACTIVATE
	## （只收寄给本实例的激活请求）；仅在需要自定义触发逻辑时调用。
	func trigger(config: TriggerConfig) -> ActiveUseConfigBuilder:
		super.trigger(config)
		return self

	func trigger_mode(value: String) -> ActiveUseConfigBuilder:
		super.trigger_mode(value)
		return self

	# ========== 2. 时间线配置 ==========

	func timeline(data: TimelineData) -> ActiveUseConfigBuilder:
		super.timeline(data)
		return self

	func on_tag(tag: String, actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		super.on_tag(tag, actions)
		return self

	func on_timeline_start(actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		super.on_timeline_start(actions)
		return self

	func on_timeline_end(actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		super.on_timeline_end(actions)
		return self

	func on_cancel(actions: Array[Action.BaseAction]) -> ActiveUseConfigBuilder:
		super.on_cancel(actions)
		return self

	# ========== 3. 条件和消耗 ==========

	## 添加前置条件（可选）：所有条件满足才能激活技能
	func condition(cond: Condition) -> ActiveUseConfigBuilder:
		_conditions.append(cond)
		return self

	## 添加消耗（可选）：激活技能时扣除的资源
	func cost(c: Cost) -> ActiveUseConfigBuilder:
		_costs.append(c)
		return self

	## 构建 ActiveUseConfig；缺 timeline 触发断言错误
	func build() -> ActiveUseConfig:
		Log.assert_crash(_timeline_data != null, "ActiveUseConfig", "timeline is required")
		return ActiveUseConfig.new(
			_timeline_data,
			_tag_actions,
			_triggers,
			_trigger_mode,
			_on_timeline_start_actions,
			_on_timeline_end_actions,
			_on_cancel_actions,
			_conditions,
			_costs
		)
