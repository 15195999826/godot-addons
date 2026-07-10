## Summon Totem #C0 - 召唤图腾主动技能
##
## V1 行为:
## - cast 后 timeline HIT @ t=400ms → HexBattleSpawnActorAction 在 caster 邻格 spawn TOTEM
## - spawned totem 自带 HexBattleTotemAttack (每 3s 最近敌方造 atk 伤害) +
##   HexBattleTotemLifetime (15s 后自动消失)
## - cooldown 8000ms; range=0 (skill 自身不需要 target, 仅以 caster 为锚)
##
## 已知局限 (本框架技能=召唤演示, 不求尽善尽美): cost 在 activation 付, spawn 在
## HIT(t=400ms) resolve; 若 caster 6 邻格全占满, HexBattleSpawnActorAction 返回
## success no-op (spawn_failed:"no_free_neighbor"), cooldown 照付但图腾不出 ("空放")。
## AI 只查 RANGE+cooldown, 不预判 spawn 可行性。可玩战斗若需要可加 ring-2 fallback 或
## spawn-feasibility cast-eligibility predicate; 演示场景下可接受, 不修。
class_name HexBattleSummonTotem


const CONFIG_ID := "skill_summon_totem"
const TIMELINE_ID := "skill_summon_totem"
const COOLDOWN_MS := 8000.0
const TOTEM_LIFETIME_MS := 15000.0


static var SUMMON_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	600.0,
	{
		TimelineTags.HIT: 400.0,
		TimelineTags.END: 600.0,
	}
)


static var ABILITY := create_config(TOTEM_LIFETIME_MS)


static func create_config(totem_lifetime_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("召唤图腾")
		.description("在身旁召唤一个图腾, 自动每 3s 攻击最近敌人, %.1fs 后消失" % (totem_lifetime_ms / 1000.0))
		.ability_tags(["skill", "active", "self", "summon"])
		.meta(HexBattleSkillMetaKeys.RANGE, 0)
		.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_SELF)
		.meta("totem_lifetime_ms", totem_lifetime_ms)
		.active_use(
			HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
			.timeline(SUMMON_TIMELINE)
			.on_timeline_start([StageCueAction.new(
				HexBattleTargetSelectors.ability_owner(),
				Resolvers.str_val(HexBattleCues.SUMMON_TOTEM_CAST),
			)])
			.on_tag(TimelineTags.HIT, [
				HexBattleSpawnActorAction.new(
					HexBattleTargetSelectors.ability_owner(),
					HexBattleClassConfig.CharacterClass.TOTEM,
					[
						HexBattleTotemAttack.ABILITY,
						HexBattleTotemLifetime.create_config(totem_lifetime_ms),
					],
				),
			])
			.build()
		)
		.build()
	)
