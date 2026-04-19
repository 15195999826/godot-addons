## 触发器配置
##
## 定义事件触发器的配置，用于 ActivateInstanceConfig 和 ActiveUseConfig。
## 无状态
class_name TriggerConfig
extends RefCounted


## 默认的主动技能激活触发器：匹配 ABILITY_ACTIVATE_EVENT，验证 abilityInstanceId 和 sourceId
static var ABILITY_ACTIVATE := TriggerConfig.new(
	GameEvent.ABILITY_ACTIVATE_EVENT,
	func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var ability_ref: Ability = ctx.ability
		var owner_id: String = ctx.owner_actor_id
		if ability_ref == null or owner_id == "":
			return false
		# 使用强类型事件
		var event := GameEvent.AbilityActivate.from_dict(event_dict)
		return event.ability_instance_id == ability_ref.id \
			and event.source_id == owner_id
)


## "自己被 grant 到 owner 身上时激活" 触发器。
##
## 典型用途：buff 挂一个 ActivateInstanceConfig + 此 trigger + loop timeline，
## grant 瞬间 AbilitySet 广播 ABILITY_GRANTED_EVENT，本 buff 响应后启动自己的 loop（如 DOT）。
##
## 匹配条件：事件的 actor_id == owner_id 且 ability.id == 自己的 instance id（严格同实例）。
## 用 instance id 而非 config_id 避免同 actor 上多个同 config 实例互相激活对方。
static var GRANTED_SELF := TriggerConfig.new(
	GameEvent.ABILITY_GRANTED_EVENT,
	func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var ability_ref: Ability = ctx.ability
		var owner_id: String = ctx.owner_actor_id
		if ability_ref == null or owner_id == "":
			return false
		var event := GameEvent.AbilityGranted.from_dict(event_dict)
		if event.actor_id != owner_id:
			return false
		return str(event.ability.get("id", "")) == ability_ref.id
)


## 事件类型（如 GameEvent.ABILITY_ACTIVATE_EVENT）
var event_kind: String

## 过滤器函数，签名: func(event: Dictionary, ctx: AbilityLifecycleContext) -> bool
var filter: Callable


func _init(
	event_kind: String = "",
	filter: Callable = Callable()
) -> void:
	self.event_kind = event_kind
	self.filter = filter
