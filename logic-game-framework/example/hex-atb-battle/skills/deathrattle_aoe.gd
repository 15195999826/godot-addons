## 亡语：死亡爆发 - 死亡时对所有敌方单位造成 20 点纯粹伤害
##
## 触发：自己死亡时
## 效果：AoE 对所有存活敌方造成 20 点真伤
class_name HexBattleDeathrattleAoe


const CONFIG_ID := "passive_deathrattle_aoe"
const AOE_DAMAGE := 20.0


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("死亡爆发")
	.description("死亡时，对所有敌方单位造成 20 点纯粹伤害")
	.ability_tags(["passive", "offensive", "deathrattle"])
	.component_config(
		NoInstanceConfig.builder()
		.trigger(TriggerConfig.new("death", _deathrattle_filter()))
		.action(HexBattleDamageAction.new(
			HexBattleTargetSelectors.all_enemies(),
			AOE_DAMAGE,
			BattleEvents.DamageType.PURE
		))
		.build()
	)
	.build()
)


## 亡语过滤：仅当死亡者是自己时触发
static func _deathrattle_filter() -> Callable:
	return func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var owner_id := ctx.owner_actor_id
		if owner_id.is_empty():
			return false
		var death_event := BattleEvents.DeathEvent.from_dict(event_dict)
		return death_event.actor_id == owner_id
