class_name AbilityComponent
extends RefCounted
## Ability 组件基类
##
## 所有 Ability 组件都应继承此类。
## 提供可选的生命周期钩子，子类按需覆盖。

var type: String = "AbilityComponent"
var _state: String = "active"
## 所属 Ability 的弱引用。
##
## 持强引用会与 Ability._components 形成循环引用（GDScript RefCounted 无循环 GC），
## 导致 Ability 及其全部 component 在 GameWorld.shutdown 后仍被锁住无法释放。
## 弱引用让 Ability 的销毁仅由 AbilitySet / GameWorld 层级决定，component 只是附属。
var _ability_ref: WeakRef = null

func get_state() -> String:
	return _state

func initialize(ability: Ability) -> void:
	_ability_ref = weakref(ability) if ability != null else null
	_state = "active"

func is_active() -> bool:
	return _state == "active"

func mark_expired() -> void:
	_state = "expired"

func is_expired() -> bool:
	return _state == "expired"

## 返回所属 Ability；若 Ability 已被销毁则返回 null，调用方需短路。
func get_ability() -> Ability:
	if _ability_ref == null:
		return null
	return _ability_ref.get_ref() as Ability

## 本 component 要随时间推进的函数，签名 (dt: float) -> void；不随时间推进就返回空 Callable（默认）。
##
## 交出去的就是函数本身，没有与之分开的开关：Ability 构造时收齐全部 component 的返回值，AbilitySet.tick 每帧只对
## 「交了函数的 ability」走遍历，其余早退。基类没有按名字调用的推进钩子——只写一个叫 on_tick 的方法不会被推进。
## 函数自己判 is_active，Ability 不替它挡（TimeDurationComponent 过期后自己返回）。
func get_tick_callable() -> Callable:
	return Callable()

## 响应事件（可选覆盖）
## @return true 表示组件被触发
func on_event(_event_dict: Dictionary, _context: AbilityLifecycleContext) -> bool:
	return false

## 本 component 要从 post 派发（EventProcessor.process_post_event）接收的事件 kind（可选覆盖）。
##
## Ability.apply_effects 汇总全部 component 声明的 kind（定向投递 kind 除外），每种 kind 注册一条 post handler；
## 事件到达后仍经 Ability.receive_event → on_event 按 trigger 过滤。覆盖了 on_event 却不声明 kind 的 component
## 只收得到 AbilitySet.receive_event 的定向投递（激活请求 / grant 自投递）。
func get_post_event_kinds() -> Array[String]:
	return []

## 本 component 各 post kind 的 precheck 列表 { kind: Array[Callable] }（可选覆盖）：只列「该 kind 的每个 trigger 都带
## precheck」的 kind。Ability.apply_effects 汇总全部 component：某 kind 在任一 component 里缺席即不预过滤（退回全派）。
## 带 trigger 的 component 直接返回 AbilityComponent.trigger_prechecks_by_kind(_triggers)。
func get_post_event_prechecks() -> Dictionary:
	return {}

## 能力生效时调用（可选覆盖）
func on_apply(_context: AbilityLifecycleContext) -> void:
	pass

## 能力移除时调用（可选覆盖）
func on_remove(_context: AbilityLifecycleContext) -> void:
	pass

## §0.X: Ability stacks 变化时调用 (可选覆盖)
##
## 触发时机: Ability.add_stacks / remove_stacks / set_stacks 内 stacks 实际变化后。
## 同一次调用如果 stacks 没真正变 (clamp 边界 / count<=0), hook 不触发。
##
## 不允许在 on_stacks_changed 内再调用 add_stacks/remove_stacks/set_stacks (递归更改)。
## Ability 实现了 reentrance guard, 嵌套调用会 Log.assert_crash。
func on_stacks_changed(_context: AbilityLifecycleContext, _old_stacks: int, _new_stacks: int) -> void:
	pass


## Ability 以 REFRESH 溢出策略叠层达到 CAP 时广播 (可选覆盖)。
##
## 时长类 component 借此实现"叠层刷新持续时间"的原子语义 (如 TimeDurationComponent
## 重置 remaining)。非时长类 component 无需实现 —— core 不点名具体 component 类型,
## 由实现方自行决定是否响应。
func on_ability_stack_refreshed() -> void:
	pass


## Phase B2 (Break): Ability 首次进入 disabled 状态时调用 (empty → non-empty)。
##
## 仅外部注册型 component 应实现 (StatModifierComponent / DynamicStatModifierComponent):
## 撤销外部注册状态 (RawAttributeSet modifier / dynamic dep), 这样 derived stat 立即
## 反映"passive 被禁用"。
##
## ❌ NoInstanceComponent / ActivateInstanceComponent **不应**实现此 hook:
## Ability.receive_event() 和 Ability.tick_executions() 已经顶层短路, 这些 component
## 的事件 / timeline 自然不推进。重复短路会引入不一致风险。
func on_passive_disabled(_context: AbilityLifecycleContext) -> void:
	pass


## Phase B2 (Break): Ability 最后一个 disabled source 移除 (non-empty → empty)。
##
## 与 on_passive_disabled 对称: 外部注册型 component 按当前 Ability state
## (current_scale / stacks / 依赖关系) 重建状态; 不补 Break 期间错过的 tick。
##
## ❌ NoInstanceComponent / ActivateInstanceComponent **不应**实现此 hook。
func on_passive_enabled(_context: AbilityLifecycleContext) -> void:
	pass

## 序列化组件状态（可选覆盖）
func serialize() -> Dictionary:
	return {}

## 检查事件是否匹配触发器列表
## triggers: 触发器字典数组，每个包含 "event_kind" 和可选 "filter"
## trigger_mode: "any"（任一匹配）或 "all"（全部匹配）
static func match_triggers(triggers: Array[Dictionary], trigger_mode: String, event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if triggers.is_empty():
		return false
	if trigger_mode == "any":
		for trigger in triggers:
			if match_single_trigger(trigger, event_dict, context):
				return true
		return false
	for trigger in triggers:
		if not match_single_trigger(trigger, event_dict, context):
			return false
	return true

## 匹配单个触发器：event_kind → 通道 → 可选 precheck（只要三个 id）→ 可选 filter（要完整 ctx），都过才算匹配。
## 通道：direct trigger 只认寄给本 ability 的定向投递（context.is_direct_delivery），普通 trigger 只认广播 / 集内投递；
## 同一 ability 对同 kind 两种 trigger 并存也不会一事二触。
## precheck 在这里照样求值：post 派发的预过滤只是把它提前，定向投递与集内投递（激活请求 / grant 自投递）只有这一处。
static func match_single_trigger(trigger: Dictionary, event_dict: Dictionary, context: AbilityLifecycleContext) -> bool:
	if event_dict.get("kind", "") != str(trigger.get("event_kind", "")):
		return false
	if bool(trigger.get("direct", false)) != context.is_direct_delivery:
		return false
	if trigger.has("precheck") and not (trigger["precheck"] as Callable).call(event_dict, context.get_handler_context()):
		return false
	if trigger.has("filter") and trigger["filter"] is Callable:
		return trigger["filter"].call(event_dict, context)
	return true

## 将 TriggerConfig 列表转换为内部字典格式
static func convert_triggers(configs: Array[TriggerConfig]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trigger in configs:
		var trigger_dict := { "event_kind": trigger.event_kind }
		if trigger.has_precheck():
			trigger_dict["precheck"] = trigger.get_precheck()
		if trigger.filter.is_valid():
			trigger_dict["filter"] = trigger.filter
		if trigger.is_direct():
			trigger_dict["direct"] = true
		result.append(trigger_dict)
	return result

## 按 kind 收集 precheck：{ kind: Array[Callable] }，只含「该 kind 的每个（广播）trigger 都带 precheck」的 kind
## （有一个 trigger 没带，该 kind 就不能预过滤——事件可能经它触发）。direct trigger 不进广播注册表，不算在内。
## 供 get_post_event_prechecks 覆盖使用。
static func trigger_prechecks_by_kind(triggers: Array[Dictionary]) -> Dictionary:
	var by_kind := {}
	var disqualified := {}
	for trigger in triggers:
		if bool(trigger.get("direct", false)):
			continue
		var kind := str(trigger.get("event_kind", ""))
		if kind == "" or disqualified.has(kind):
			continue
		if not trigger.has("precheck"):
			disqualified[kind] = true
			by_kind.erase(kind)
			continue
		if not by_kind.has(kind):
			by_kind[kind] = [] as Array[Callable]
		(by_kind[kind] as Array[Callable]).append(trigger["precheck"])
	return by_kind

## 触发器列表里去重后的 event_kind（按首次出现的顺序），供 get_post_event_kinds 覆盖使用。
## direct trigger 不进广播注册表，跳过：一个 kind 只有 direct trigger 时不注册 post handler。
static func trigger_event_kinds(triggers: Array[Dictionary]) -> Array[String]:
	var kinds: Array[String] = []
	for trigger in triggers:
		if bool(trigger.get("direct", false)):
			continue
		var kind := str(trigger.get("event_kind", ""))
		if kind != "" and not kinds.has(kind):
			kinds.append(kind)
	return kinds
