## HexBattleSkillPresets - 零结构差异技能家族的声明收口
##
## 收口规则(docs/plan/hex-skill-applayer-convergence-plan.md P5): 「选目标 → 挂 buff/盾」
## 家族 9 个技能骨架逐字相同、每文件仅 ~8 行是信息, 按 fireball.gd 的抽象判据
## (技能数 × 参数量 × 结构差异)反推该抽。8 个收进本 preset;
## **poison 保留全显式**当家族教学范本 —— 想看 preset 展开后的完整 builder 链,
## 读 poison.gd。
##
## 与"AI 模仿沙盒"哲学的边界: preset 只收零变化样板; 任何带独有机制的技能
## (execute 的条件伤害 / shadow_step 的位移 / lifesteal 的 on_hit 回调)不进 preset,
## 保持显式 builder 链。
class_name HexBattleSkillPresets


## 单体 buff/护盾施加技能标准骨架:
## 标准 MELEE_500 节奏(HIT@300) + 标准门控四件套 + HIT 时对目标施加 buff_config。
##
## targeting 决定目标选择器与合法性协议:
##   TARGETING_ACTOR → current_target(敌方单体, 配 TAG_ENEMY)
##   TARGETING_SELF  → ability_owner(自施, 配 TAG_SELF; range 应为 0)
## cue_id 非空时在 timeline_start 对同一目标发 StageCue(传 HexBattleCues 常量)。
## use_shield_action=true 走 HexBattleApplyShieldAction(护盾组件接线), 否则 ApplyBuffAction。
static func buff_applier(
	config_id: String,
	display_name: String,
	description: String,
	ability_tags: Array[String],
	skill_range: int,
	targeting: String,
	cooldown_ms: float,
	buff_config: AbilityConfig,
	cue_id: String = "",
	use_shield_action: bool = false,
	extra_meta: Dictionary = {},
) -> AbilityConfig:
	Log.assert_crash(
		targeting == HexBattleSkillMetaKeys.TARGETING_ACTOR
			or targeting == HexBattleSkillMetaKeys.TARGETING_SELF,
		"HexBattleSkillPresets",
		"buff_applier 只支持 ACTOR/SELF targeting, got: %s" % targeting)

	var apply_target := _applier_target(targeting)
	var apply_action: Action.BaseAction
	if use_shield_action:
		apply_action = HexBattleApplyShieldAction.new(apply_target, buff_config)
	else:
		apply_action = HexBattleApplyBuffAction.new(apply_target, buff_config)

	var active_builder := HexBattleCooldownSystem.apply_standard_active_gating(
		ActiveUseConfig.builder(), cooldown_ms
	).timeline(HexBattleStdTimelines.MELEE_500)
	if cue_id != "":
		active_builder = active_builder.on_timeline_start([StageCueAction.new(
			_applier_target(targeting),
			Resolvers.str_val(cue_id),
		)])
	var hit_actions: Array[Action.BaseAction] = [apply_action]
	active_builder = active_builder.on_tag(TimelineTags.HIT, hit_actions)

	var config_builder := (
		AbilityConfig.builder()
		.config_id(config_id)
		.display_name(display_name)
		.description(description)
		.ability_tags(ability_tags)
		.meta(HexBattleSkillMetaKeys.RANGE, skill_range)
		.meta(HexBattleSkillMetaKeys.TARGETING, targeting)
	)
	for meta_key: String in extra_meta:
		config_builder = config_builder.meta(meta_key, extra_meta[meta_key])
	return config_builder.active_use(active_builder.build()).build()


static func _applier_target(targeting: String) -> TargetSelector:
	if targeting == HexBattleSkillMetaKeys.TARGETING_SELF:
		return HexBattleTargetSelectors.ability_owner()
	return HexBattleTargetSelectors.current_target()
