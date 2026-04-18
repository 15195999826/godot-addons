## 荆棘反伤 - 受到伤害时反弹固定伤害
##
## 触发：自己受到伤害时
## 效果：对攻击者造成 2 点纯粹伤害
## 反伤循环防护：DamageEvent.is_reflected 标记由 _thorn_filter 过滤
class_name HexBattleThorn


const CONFIG_ID := "passive_thorn"
const REFLECT_DAMAGE := 2.0


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("荆棘反伤")
	.description("受到伤害时，对攻击者造成 2 点伤害")
	.ability_tags(["passive", "defensive", "reflect"])
	.component_config(
		NoInstanceConfig.builder()
		.trigger(TriggerConfig.new("damage", _thorn_filter()))
		.action(HexBattleReflectDamageAction.new(
			REFLECT_DAMAGE,
			BattleEvents.DamageType.PURE
		))
		.build()
	)
	.build()
)


## 反伤过滤器：受害方是自己 + 有攻击来源 + 来源不是自己 + 非已反弹的伤害
static func _thorn_filter() -> Callable:
	return func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var owner_id := ctx.owner_actor_id
		if owner_id.is_empty():
			return false
		var damage_event := BattleEvents.DamageEvent.from_dict(event_dict)
		var is_target := damage_event.target_actor_id == owner_id
		var has_source := not damage_event.source_actor_id.is_empty()
		var not_self_damage := damage_event.source_actor_id != owner_id
		return is_target and has_source and not_self_damage and not damage_event.is_reflected
