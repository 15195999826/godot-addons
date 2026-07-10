## Execute - 斩杀
##
## 灵感:TFT Dark Star / StS Bane / Dota2 斧王 Culling Blade。
## 效果:目标「有效血量」(hp + 能挡 PURE 的护盾)低于 max_hp 的 20% → 造成
## effective_hp+1 的 PURE 伤害(护盾段被吸、生命归零 = 斩杀);否则退化为
## caster.atk 的普攻。命中并击杀时额外播放 execute_kill 醒目特效。
##
## 契约示范(填补 pattern 速查空格「条件分支伤害 / 斩杀」):
##   单个既有 HexBattleDamageAction + Resolver 内基于 target 状态分支 damage 值。
##   0 新 Action / 0 新 Condition / 0 新事件字段 —— LGF 表达"条件伤害"的惯用法。
##   target 取自 ctx.get_current_event()(与 current_target selector 同源)。
##
## PURE = 判决伤害,仅被 universal/["all"] 护盾吸(physical/magical 盾挡不住 PURE,
## 故不计入有效血量);仍走完整 pre/post(减伤 / thorn 反伤不绕过)。
class_name HexBattleExecute


const CONFIG_ID := "skill_execute"
const COOLDOWN_MS := 6000.0
const KILL_HP_THRESHOLD := 0.2


## HIT tag 时按 ctx 解析一次。target 取自当前事件(与 current_target selector
## 同源 —— Strike 已证此刻 ctx 当前事件带 target_actor_id)。
static var _EXECUTE_DAMAGE: FloatResolver = Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
	var event := ctx.get_current_event()
	var target_id: String = event.get("target_actor_id", "") if not event.is_empty() else ""
	if target_id == "":
		return 0.0
	var target := GameWorld.get_actor(target_id)
	if target == null or not (target is CharacterActor):
		return 0.0
	var t := target as CharacterActor
	var max_hp: float = t.attribute_set.max_hp
	if max_hp <= 0.0:
		return 0.0
	var pure_str := BattleEvents._damage_type_to_string(BattleEvents.DamageType.PURE)
	var shield_sum := HexBattleShieldResolver.sum_absorbable_capacity(t, pure_str)
	var effective_hp: float = t.attribute_set.hp + shield_sum
	if effective_hp / max_hp < KILL_HP_THRESHOLD:
		# 斩杀:打穿能挡 PURE 的护盾段后,生命恰好归零(+1 保证致死)
		return effective_hp + 1.0
	# 高血退化为普攻 = caster.atk(strike.gd 模板)
	var caster := HexBattleSkillHelpers.caster(ctx)
	if caster == null:
		return 0.0
	return caster.attribute_set.atk
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("斩杀")
	.description("有效血量低于 20% 的敌人被斩杀(造成等同其有效血量的真实伤害),否则普通攻击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_ACTOR)
	.active_use(
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(HexBattleStdTimelines.MELEE_500)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val(HexBattleCues.MELEE_HEAVY)
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_EXECUTE_DAMAGE,
				BattleEvents.DamageType.PURE
			).on_kill(
				StageCueAction.new(
					HexBattleTargetSelectors.current_target(),
					Resolvers.str_val(HexBattleCues.EXECUTE_KILL)
				)
			),
		])
		.build()
	)
	.build()
)
