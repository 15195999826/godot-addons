## 触发器配置（扳机：什么事件扣动本 component）
##
## 用于 NoInstanceConfig / ActivateInstanceConfig / ActiveUseConfig 的 .trigger()。无状态、跨 ability 实例共享
## （static var 配置），所以自己不知道「我是谁」，「我」由运行时递进来。
##
## 一个 trigger 的条件分两段，按顺序求值：
##   ① precheck(event_dict, h: HandlerContext) -> bool —— 只看事件 + 本 ability 的三个 id（owner / ability / config），
##      不需要 actor。post 派发时 EventProcessor 在重建 context 之前就能跑它：同 kind 的全部 trigger 都带 precheck 的登记，
##      不过就整条跳过（纯加速，不改结果；match_single_trigger 里照样再判一次，定向投递也走同一段）。
##   ② filter(event_dict, ctx: AbilityLifecycleContext) -> bool —— 要完整 ctx（actor / 属性 / 世界）的条件。
## 只比 id 的条件写 precheck，别写 filter：写进 filter 就得先造 ctx 才能拒绝。
##
## 投递通道也由 trigger 声明：`.direct()` 的 trigger 只收**寄给本 ability 实例**的事件（EventProcessor.deliver_to_ability：
## procedure 寄来的激活请求、grant_ability 寄来的 grant 通知、投射物系统投回发射者的结局），不进广播注册表、广播来的
## 同 kind 事件也不匹配；不声明的照旧按 kind 订阅广播。「收件人是不是我」不必写 precheck——processor 按地址只重建
## 收件实例的 context。定向投递不问 owner 的 is_event_responsive：人死了这封信还处不处理，由 direct trigger 自己的 filter 定。
class_name TriggerConfig
extends RefCounted


## 默认的主动技能激活触发器：只收寄给本实例的 ABILITY_ACTIVATE_EVENT——procedure 经 EventProcessor.deliver_to_ability
## 按地址（source_id 的 actor、ability_instance_id 的实例）投递，「是不是叫我」由地址保证，trigger 不再比 id。
static var ABILITY_ACTIVATE := TriggerConfig.new(GameEvent.ABILITY_ACTIVATE_EVENT).direct()


## "自己被 grant 到 owner 身上时激活" 触发器。
##
## 典型用途：buff 挂一个 ActivateInstanceConfig + 此 trigger + loop timeline，
## grant 瞬间 AbilitySet.grant_ability 把 ABILITY_GRANTED_EVENT 只寄给刚 grant 的那个实例（deliver_to_ability），
## 本 buff 收到后启动自己的 loop（如 DOT）。只寄给新实例所以天然严格同实例：同 actor 上多个同 config 实例互不激活。
static var GRANTED_SELF := TriggerConfig.new(GameEvent.ABILITY_GRANTED_EVENT).direct()


## 事件类型（如 GameEvent.ABILITY_ACTIVATE_EVENT）
var event_kind: String

## 第二段：func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool，要完整 ctx
var filter: Callable

## 第一段：func(event: Dictionary, h: HandlerContext) -> bool，只看事件 + 三个 id。经 precheck() 设置。
var _precheck: Callable

## 只收定向投递（寄给本 ability 实例的事件）。经 direct() 设置。
var _direct := false


func _init(
	event_kind: String = "",
	filter: Callable = Callable()
) -> void:
	self.event_kind = event_kind
	self.filter = filter


## 返回带 precheck 的新 TriggerConfig（copy-with）。本对象是共享配置，不原地改：
## 对 TriggerConfig.ABILITY_ACTIVATE 这类 static 调 precheck() 不会污染全场。
func precheck(fn: Callable) -> TriggerConfig:
	var copy := TriggerConfig.new(event_kind, filter)
	copy._precheck = fn
	copy._direct = _direct
	return copy


## 返回只收定向投递的新 TriggerConfig（copy-with，同 precheck）。
func direct() -> TriggerConfig:
	var copy := TriggerConfig.new(event_kind, filter)
	copy._precheck = _precheck
	copy._direct = true
	return copy


func get_precheck() -> Callable:
	return _precheck


func has_precheck() -> bool:
	return _precheck.is_valid()


func is_direct() -> bool:
	return _direct
