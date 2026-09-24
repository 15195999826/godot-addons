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
## 投递通道也由 trigger 声明：`.direct()` 的 trigger 只收**寄给本 ability 实例**的事件（EventProcessor.deliver_to_ability，
## 如投射物系统把结局投回发射它的 ability），不进广播注册表、广播来的同 kind 事件也不匹配；不声明的照旧按 kind 订阅广播。
## 「收件人是不是我」不必再写 precheck——processor 按回执只重建收件实例的 context。定向投递不问 owner 的
## is_event_responsive：人死了这封回信还处不处理，由 direct trigger 自己的 filter 定。
class_name TriggerConfig
extends RefCounted


## 默认的主动技能激活触发器：匹配 ABILITY_ACTIVATE_EVENT，验证 ability_instance_id 和 source_id（纯 id，走 precheck）
static var ABILITY_ACTIVATE := TriggerConfig.new(GameEvent.ABILITY_ACTIVATE_EVENT).precheck(
	func(event_dict: Dictionary, h: HandlerContext) -> bool:
		if h.ability_id == "" or h.owner_id == "":
			return false
		return str(event_dict.get("ability_instance_id", "")) == h.ability_id \
			and str(event_dict.get("source_id", "")) == h.owner_id
)


## "自己被 grant 到 owner 身上时激活" 触发器。
##
## 典型用途：buff 挂一个 ActivateInstanceConfig + 此 trigger + loop timeline，
## grant 瞬间 AbilitySet 广播 ABILITY_GRANTED_EVENT，本 buff 响应后启动自己的 loop（如 DOT）。
##
## 匹配条件：事件的 actor_id == owner_id 且 ability.id == 自己的 instance id（严格同实例）。
## 用 instance id 而非 config_id 避免同 actor 上多个同 config 实例互相激活对方。
static var GRANTED_SELF := TriggerConfig.new(GameEvent.ABILITY_GRANTED_EVENT).precheck(
	func(event_dict: Dictionary, h: HandlerContext) -> bool:
		if h.ability_id == "" or h.owner_id == "":
			return false
		if str(event_dict.get("actor_id", "")) != h.owner_id:
			return false
		var ability_dict := event_dict.get("ability", {}) as Dictionary
		if ability_dict == null:
			return false
		return str(ability_dict.get("id", "")) == h.ability_id
)


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
