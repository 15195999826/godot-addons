## Knockback Punch - 击退拳 (Tier 1 #4)
##
## 灵感: Into the Breach Titan Fist。
## 效果: 对相邻敌人造成 caster.atk 物理伤害, 然后沿 caster→target 方向推 1 格。
##   - 推到空格: target 移动 1 格
##   - 推到地图边界 / 占用格 (墙 / 角色): target 不移动 (N=1 撞正前方)
##                                       按 blocker.collision_profile 结算碰撞伤害
##
## V1 仅 ALLOWED_TARGET_KINDS = ["Character"]: target 必须是角色, 不能直接 push 环境物。
## 撞墙 / 撞 actor 通过 PushAction 内部 occupant 检查处理 (墙仍是合法 blocker)。
##
## Contract:
##   - 基础伤害走 DamageAction (含暴击 + on_critical 可扩展)
##   - 击退碰撞伤害 deterministic, 不进 PreDamageEvent (固定值)
##   - case 6: 若基础伤害已击杀 target, PushAction 整段跳过
##
## 后续变体 (不在 V1):
##   - Pull: distance + dir 反转
##   - Push N: distance > 1 (PushAction 已支持, 改 timeline 中传入即可)
##   - Wind Torrent: 群推 (一条直线全部 actor)
class_name HexBattleKnockbackPunch


const CONFIG_ID := "skill_knockback_punch"
const COOLDOWN_MS := 4000.0
const KNOCKBACK_DISTANCE := 1


## 基础伤害 = caster.atk (与 Strike 同模式)
static var _CASTER_ATK_DAMAGE: FloatResolver = HexBattleSkillHelpers.caster_atk_damage()


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("击退拳")
	.description("近战物理伤害, 并将目标击退 1 格 (撞物 / 撞墙时承受额外碰撞伤害)")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.meta(HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS, [HexBattleActor.KIND_CHARACTER])
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_ACTOR)
	.active_use(
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(HexBattleStdTimelines.MELEE_500)
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL
			),
			HexBattlePushAction.new(
				HexBattleTargetSelectors.current_target(),
				KNOCKBACK_DISTANCE,
				HexBattlePushAction.KIND_KNOCKBACK
			),
		])
		.build()
	)
	.build()
)
