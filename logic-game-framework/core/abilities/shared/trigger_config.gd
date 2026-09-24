## 触发器配置（扳机：什么事件扣动本 component）
##
## 用于 NoInstanceConfig / ActivateInstanceConfig / ActiveUseConfig 的 .trigger()。无状态、跨 ability 实例共享
## （static var 配置），所以自己不知道「我是谁」，「我」由运行时递进来。
##
## 一个 trigger 的条件分两段，按顺序求值，都是可选项：
##   ① event_filter(event_dict, me: HandlerContext) -> bool —— 只看事件 + 本 ability 的三个 id（owner / ability / config），
##      纯函数、不查世界。post 派发时 EventProcessor 在重建 context 之前就跑它：同 kind 的全部 trigger 都带 event_filter
##      的登记，全不过就整条跳过（纯加速，不改结果；match_single_trigger 里照样再判一次，定向投递也走同一段）。
##   ② context_filter(event_dict, ctx: AbilityLifecycleContext) -> bool —— 要完整 ctx（actor / 属性 / 世界）的条件，
##      只对通过 ① 的登记、重建 context 之后跑。
## 「是不是我造成的 / 打在我身上的」这类只比 id 的条件写 event_filter；写进 context_filter 就得先造 ctx 才能拒绝，
## 满场几十个订阅者时这是扇出的大头。event_filter 是回调、处理器读不懂它：派发仍遍历该 kind 的全部登记，只是每条
## 被拒的成本从重建 context 降到一次调用（要不遍历得能索引，见 CLAUDE.md「未来考量」）。
##
## 投递通道也由 trigger 声明：`.direct()` 的 trigger 只收**寄给本 ability 实例**的事件（EventProcessor.deliver_to_ability：
## procedure 寄来的激活请求、grant_ability 寄来的 grant 通知、投射物系统投回发射者的结局），不进广播注册表、广播来的
## 同 kind 事件也不匹配；不声明的照旧按 kind 订阅广播。「收件人是不是我」不必写 event_filter——processor 按地址只重建
## 收件实例的 context。定向投递不问 owner 的 is_event_responsive：人死了这封信还处不处理，由 direct trigger 自己的条件定。
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

## 第二段：func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool，要完整 ctx。经 context_filter() 设置；
## 构造函数的第二个位置参数写的是同一个字段（旧写法，保留兼容，新代码用链式）。
var filter: Callable

## 第一段：func(event: Dictionary, me: HandlerContext) -> bool，只看事件 + 三个 id。经 event_filter() 设置。
var _event_filter: Callable

## 只收定向投递（寄给本 ability 实例的事件）。经 direct() 设置。
var _direct := false


func _init(
	event_kind: String = "",
	filter: Callable = Callable()
) -> void:
	self.event_kind = event_kind
	self.filter = filter


## 返回带第一段条件的新 TriggerConfig（copy-with）。本对象是共享配置，不原地改：
## 对 TriggerConfig.ABILITY_ACTIVATE 这类 static 调链式方法不会污染全场。
func event_filter(fn: Callable) -> TriggerConfig:
	var copy := _copy()
	copy._event_filter = fn
	return copy


## 返回带第二段条件的新 TriggerConfig（copy-with，同 event_filter）。
func context_filter(fn: Callable) -> TriggerConfig:
	var copy := _copy()
	copy.filter = fn
	return copy


## 返回只收定向投递的新 TriggerConfig（copy-with，同 event_filter）。
func direct() -> TriggerConfig:
	var copy := _copy()
	copy._direct = true
	return copy


func get_event_filter() -> Callable:
	return _event_filter


func has_event_filter() -> bool:
	return _event_filter.is_valid()


func is_direct() -> bool:
	return _direct


func _copy() -> TriggerConfig:
	var copy := TriggerConfig.new(event_kind, filter)
	copy._event_filter = _event_filter
	copy._direct = _direct
	return copy
