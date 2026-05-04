## 易伤 Buff - 受到伤害放大 1.5x, 持续 5 秒
##
## 设计要点:
## - 不主动扣血(对比 PoisonBuff): 只在 pre_damage 阶段 modify_intent 把 damage * 1.5
## - filter 仅"target == owner"维度: 自伤 / 反伤打回攻击者也算 target 收到的伤害, 都吃放大
## - 重复施放语义沿用 ApplyBuffAction 默认: 多个独立 ExposeBuff 实例并存,
##   各自独立 expire, 各自挂一个 PreEventComponent → 实际伤害放大 = 1.5^N
## - duration 到期由 TimeDurationComponent 自动 ability.expire(EXPIRE_REASON_TIME_DURATION)
##
## 这是 LGF PreEvent modify_intent 通路的第一个生产用例(ward 已迁到 ShieldComponent)。
class_name HexBattleExposeBuff


const CONFIG_ID := "buff_expose"
const DURATION_MS := 5000.0
const DAMAGE_AMP_MULT := 1.5


static var EXPOSE_BUFF := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("易伤")
	.description("受到伤害提高 50%, 持续 5 秒")
	.ability_tags(["buff", "negative"])
	.component_config(_build_pre_damage_config())
	.component_config(TimeDurationConfig.new(DURATION_MS))
	.build()
)


## 仅当 pre_damage.target_actor_id == owner 时放大伤害 1.5x。
## 字段名 "target_actor_id" 来自 HexBattlePreEvents.PreDamageEvent.to_dict()。
static func _build_pre_damage_config() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", DAMAGE_AMP_MULT, ctx.ability.config_id, "易伤"),
			]),
		func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return event_dict.get("target_actor_id", "") == ctx.owner_actor_id,
		"Expose +50%"
	)
