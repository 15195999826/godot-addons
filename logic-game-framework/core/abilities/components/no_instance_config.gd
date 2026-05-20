## NoInstance 组件配置
##
## 用于配置 NoInstanceComponent，定义被动触发的 Action 链。
## 不创建执行实例，事件触发时直接执行 Action。
## 推荐使用 Builder 模式构造，提供清晰的可读性和 IDE 自动补全。
##
## [b]注意[/b]
##
## 与 ActiveUseConfig 不同，NoInstanceConfig [b]没有默认触发器[/b]。
## 配置 actions(...) 时必须显式调用 .trigger() 至少一次；
## 仅配置 lifecycle (on_apply_actions / on_remove_actions) 时可省略 trigger。
##
## [b]推荐链式调用顺序[/b]
##
## 按照 "何时触发 → 做什么" 的语义顺序：
## [codeblock]
## NoInstanceConfig.builder() \
##     .trigger(TriggerConfig.new("damage", filter_fn))
##     .action(ReflectDamageAction.new(...))
##     .build()
## [/codeblock]
##
## §0.6 新增 lifecycle actions: grant 时执行 on_apply_actions / remove 时执行
## on_remove_actions。这是 Ability 生命周期级 hook，不需要 trigger 也能 build：
## [codeblock]
## NoInstanceConfig.builder() \
##     .on_apply_actions([LooseTagAction.Apply.new(...)])
##     .on_remove_actions([LooseTagAction.Remove.new(...)])
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

## §0.6 lifecycle actions: Ability grant 时执行
var on_apply_actions: Array[Action.BaseAction] = []

## §0.6 lifecycle actions: Ability remove (expire / revoke) 时执行
var on_remove_actions: Array[Action.BaseAction] = []


func _init(
	p_triggers: Array[TriggerConfig] = [],
	p_actions: Array[Action.BaseAction] = [],
	p_trigger_mode: String = "any",
	p_on_apply_actions: Array[Action.BaseAction] = [],
	p_on_remove_actions: Array[Action.BaseAction] = []
) -> void:
	self.triggers = p_triggers
	self.actions.assign(p_actions)
	self.trigger_mode = p_trigger_mode
	self.on_apply_actions.assign(p_on_apply_actions)
	self.on_remove_actions.assign(p_on_remove_actions)


## 创建对应的 NoInstanceComponent 实例
func create_component() -> AbilityComponent:
	return NoInstanceComponent.new(self)


## 创建 Builder
static func builder() -> NoInstanceConfigBuilder:
	return NoInstanceConfigBuilder.new()


## NoInstanceConfig Builder
##
## 使用链式调用构建 NoInstanceConfig，提供清晰的可读性。
##
## 合法形态:
## - 仅 trigger + action: 普通事件被动 (旧行为).
## - 仅 lifecycle actions: 没有 trigger 也能 build (§0.6).
## - trigger + action + lifecycle actions 可共存.
class NoInstanceConfigBuilder:
	extends RefCounted

	var _triggers: Array[TriggerConfig] = []
	var _trigger_mode: String = "any"
	var _actions: Array[Action.BaseAction] = []
	var _on_apply_actions: Array[Action.BaseAction] = []
	var _on_remove_actions: Array[Action.BaseAction] = []

	# ========== 1. 触发配置 ==========

	## 添加触发器（事件被动必须配置至少一个）
	func trigger(config: TriggerConfig) -> NoInstanceConfigBuilder:
		_triggers.append(config)
		return self

	## 设置触发模式（可选，默认 "any"）
	func trigger_mode(value: String) -> NoInstanceConfigBuilder:
		_trigger_mode = value
		return self

	# ========== 2. 动作配置 ==========

	## 添加动作（触发时执行）
	func action(act: Action.BaseAction) -> NoInstanceConfigBuilder:
		_actions.append(act)
		return self

	## 批量添加动作
	func actions(acts: Array[Action.BaseAction]) -> NoInstanceConfigBuilder:
		_actions.append_array(acts)
		return self

	# ========== 3. Lifecycle (§0.6) ==========

	## Ability grant 时执行的 actions (按声明顺序)
	func on_apply_actions(acts: Array[Action.BaseAction]) -> NoInstanceConfigBuilder:
		_on_apply_actions.append_array(acts)
		return self

	## Ability remove (expire / revoke) 时执行的 actions (按声明顺序)
	##
	## 触发场景:
	## - duration / expire → Ability remove_effects → on_remove
	## - AbilitySet.revoke_ability / 显式 remove → on_remove
	## - actor death → 当前不自动触发 (除非显式 revoke)
	func on_remove_actions(acts: Array[Action.BaseAction]) -> NoInstanceConfigBuilder:
		_on_remove_actions.append_array(acts)
		return self

	## 构建 NoInstanceConfig
	## 仅当配置了 actions(...) 但无 trigger 时报错;
	## lifecycle-only / trigger+action / trigger+action+lifecycle 都合法。
	func build() -> NoInstanceConfig:
		var has_trigger_actions := not _actions.is_empty()
		var has_lifecycle := not (_on_apply_actions.is_empty() and _on_remove_actions.is_empty())
		Log.assert_crash(has_trigger_actions or has_lifecycle,
			"NoInstanceConfig",
			"at least one of action(...) or on_apply_actions/on_remove_actions is required")
		if has_trigger_actions:
			Log.assert_crash(not _triggers.is_empty(),
				"NoInstanceConfig",
				"action(...) configured but no trigger; trigger required when actions are configured")
		return NoInstanceConfig.new(
			_triggers,
			_actions,
			_trigger_mode,
			_on_apply_actions,
			_on_remove_actions
		)
