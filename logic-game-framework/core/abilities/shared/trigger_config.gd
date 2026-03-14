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
