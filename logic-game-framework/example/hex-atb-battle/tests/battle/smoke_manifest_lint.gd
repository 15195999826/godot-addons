## Smoke: manifest lint —— 把「注释里的合同」变成跑得动的合同
##
## 收敛计划(inkmon docs/plan/hex-skill-applayer-convergence-plan.md) P2。
## 遍历 HexBattleAllSkills 总花名册做四断言, 覆盖四类静默失效面:
##   1. timeline 可解析: 每个 config 引用的 timeline_id 在 register_all_timelines()
##      后必须命中 TimelineRegistry(抓漏注册 / 改 id 没同步)
##   2. BUFF_REGISTRY 覆盖: 带 buff tag 的 config_id ∈ BuffVisualizer 白名单
##      (不接图标 = buff 永远不显示, 无报错)
##   3. cue 存在性: 全部静态声明的 cue ⊆ frontend 认识的 cue 集合
##      (stage_cue_visualizer 对未知 cue 静默跳过) + HexBattleCues 菜单登记
##   4. tag 词表 + active 技能 RANGE / TARGETING meta 必填
##      (tag typo 静默漏行为; RANGE 缺省被读成 1 是踩过的坑)
##
## 覆盖边界: cue 收集走 StageCueAction.get_fixed_cue()(str_val 静态值)与
## HexBattleDamageAction.get_callback_actions(); FlowAction 分支内今天没有 cue,
## 不递归(新增"分支里发 cue"的技能时把该分支 action 暴露给本 lint)。
## 直接 GameEvent.StageCue.create 的调用点(demon_form/totem_attack)靠
## 「必须引用 HexBattleCues 常量」的约定覆盖, 静态收集不到。
extends Node


## 暂无视觉的 cue(逻辑已 emit、美术未接)。新增豁免必须同步 HexBattleCues 注释。
const CUE_NO_VISUAL_YET: Array[String] = [
	HexBattleCues.DEMON_FORM_PULSE,
]

## 有意无视觉: 投射物动画承载, visualizer 明文跳过。
const CUE_INTENTIONAL_NO_VFX: Array[String] = [
	HexBattleCues.MAGIC_FIREBALL,
	HexBattleCues.RANGED_ARROW,
]

## 带 buff tag 但豁免头顶图标的 config_id(当前无; 加入时写明理由)。
const BUFF_ICON_EXEMPT: Array[String] = []

## 纯描述性 tag 词表(无代码消费方, 不 const 化; 承重 tag 见 HexBattleSkillTags /
## HexBattleBuffTags)。新描述词入表即可, typo 会在断言 4 红。
const DESCRIPTIVE_TAGS: Array[String] = [
	"melee", "ranged", "magic", "projectile", "aoe", "line",
	"debuff", "shield", "lifesteal", "swap", "summon", "stance", "surge",
	"stun", "silence", "cleanse", "fire_tile", "totem",
	"dynamic", "regen", "reflect", "defensive", "offensive", "deathrattle",
	"periodic", "equipment", "attack_effect", "critical_strike",
	"character_rules", "auto_attack", "move", "action",
]


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: manifest lint (P2 四断言) ===")
	HexBattleAllSkills.register_all_timelines()

	var failures: Array[String] = []
	var configs := HexBattleAllSkills.all_abilities()
	_check_timelines(configs, failures)
	_check_buff_registry(configs, failures)
	_check_cues(configs, failures)
	_check_tags_and_meta(configs, failures)

	if failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - manifest lint %d configs clean" % configs.size())
		get_tree().quit(0)
		return
	for f in failures:
		print("  [LINT] " + f)
	print("SMOKE_TEST_RESULT: FAIL - %d lint violation(s)" % failures.size())
	get_tree().quit(1)


# ============================================================
# 断言 1: timeline 可解析
# ============================================================

func _check_timelines(configs: Array[AbilityConfig], failures: Array[String]) -> void:
	for cfg in configs:
		for au in cfg.active_use_components:
			if not TimelineRegistry.has(au.timeline_id):
				failures.append("%s: active_use timeline '%s' 未注册" % [cfg.config_id, au.timeline_id])
		for comp in cfg.components:
			if comp is ActivateInstanceConfig:
				var aic := comp as ActivateInstanceConfig
				if not TimelineRegistry.has(aic.timeline_id):
					failures.append("%s: component timeline '%s' 未注册" % [cfg.config_id, aic.timeline_id])


# ============================================================
# 断言 2: BUFF_REGISTRY 覆盖
# ============================================================

func _check_buff_registry(configs: Array[AbilityConfig], failures: Array[String]) -> void:
	for cfg in configs:
		if not cfg.ability_tags.has(HexBattleBuffTags.TAG_BUFF):
			continue
		if cfg.config_id in BUFF_ICON_EXEMPT:
			continue
		if not FrontendBuffVisualizer.BUFF_REGISTRY.has(cfg.config_id):
			failures.append("%s: 带 buff tag 但未接 BUFF_REGISTRY(头顶图标永不显示)" % cfg.config_id)


# ============================================================
# 断言 3: cue 存在性
# ============================================================

func _known_cues() -> Dictionary:
	var known := {}
	for c in FrontendStageCueVisualizer.MELEE_ATTACK_CUES:
		known[c] = true
	for c in FrontendStageCueVisualizer.HEAL_CUES:
		known[c] = true
	known[FrontendStageCueVisualizer.EXECUTE_KILL_CUE] = true
	for c in FrontendStageCueVisualizer.CONTROL_FLOATING_TEXTS.keys():
		known[c] = true
	for c in FrontendStageCueVisualizer.CONE_DEBUG_CUES:
		known[c] = true
	for c in CUE_INTENTIONAL_NO_VFX:
		known[c] = true
	for c in CUE_NO_VISUAL_YET:
		known[c] = true
	return known


func _check_cues(configs: Array[AbilityConfig], failures: Array[String]) -> void:
	var known := _known_cues()
	for cfg in configs:
		for action in _collect_actions(cfg):
			if action is StageCueAction:
				var cue := (action as StageCueAction).get_fixed_cue()
				if cue != "" and not known.has(cue):
					failures.append("%s: cue '%s' 不在 frontend 注册表也不在豁免名单(会静默无视觉)" % [cfg.config_id, cue])


## 收集 config 树上全部静态可达 action(含 DamageAction 回调链)。
func _collect_actions(cfg: AbilityConfig) -> Array[Action.BaseAction]:
	var out: Array[Action.BaseAction] = []
	for au in cfg.active_use_components:
		_append_component_actions(out, au.on_timeline_start_actions, au.on_timeline_end_actions, au.tag_actions)
	for comp in cfg.components:
		if comp is ActivateInstanceConfig:
			var aic := comp as ActivateInstanceConfig
			_append_component_actions(out, aic.on_timeline_start_actions, aic.on_timeline_end_actions, aic.tag_actions)
		elif comp is NoInstanceConfig:
			var nic := comp as NoInstanceConfig
			out.append_array(nic.actions)
			out.append_array(nic.on_apply_actions)
			out.append_array(nic.on_remove_actions)
	# DamageAction 回调链(execute 的 on_kill cue 藏在这里)
	var with_callbacks: Array[Action.BaseAction] = []
	for a in out:
		with_callbacks.append(a)
		if a is HexBattleDamageAction:
			with_callbacks.append_array((a as HexBattleDamageAction).get_callback_actions())
	return with_callbacks


func _append_component_actions(
	out: Array[Action.BaseAction],
	start_actions: Array[Action.BaseAction],
	end_actions: Array[Action.BaseAction],
	tag_actions: Array[TagActionsEntry],
) -> void:
	out.append_array(start_actions)
	out.append_array(end_actions)
	for entry in tag_actions:
		out.append_array(entry.get_actions())


# ============================================================
# 断言 4: tag 词表 + active 必填 meta
# ============================================================

func _known_tags() -> Dictionary:
	var known := {}
	for t in [
		HexBattleSkillTags.TAG_SKILL, HexBattleSkillTags.TAG_ACTIVE,
		HexBattleSkillTags.TAG_PASSIVE, HexBattleSkillTags.TAG_INTRINSIC,
		HexBattleSkillTags.TAG_STATUS, HexBattleSkillTags.TAG_LIFETIME,
		HexBattleSkillTags.TAG_ENEMY, HexBattleSkillTags.TAG_ALLY,
		HexBattleSkillTags.TAG_SELF, HexBattleSkillTags.TAG_HEAL,
		HexBattleSkillTags.TAG_CONE,
		HexBattleBuffTags.TAG_BUFF, HexBattleBuffTags.TAG_NEGATIVE,
		HexBattleBuffTags.TAG_POSITIVE, HexBattleBuffTags.TAG_CONTROL,
		HexBattleBuffTags.TAG_PASSIVE_BREAK,
	]:
		known[t] = true
	for t in DESCRIPTIVE_TAGS:
		known[t] = true
	return known


func _check_tags_and_meta(configs: Array[AbilityConfig], failures: Array[String]) -> void:
	var known := _known_tags()
	var valid_targeting := [
		HexBattleSkillMetaKeys.TARGETING_ACTOR,
		HexBattleSkillMetaKeys.TARGETING_COORD,
		HexBattleSkillMetaKeys.TARGETING_SELF,
	]
	for cfg in configs:
		for tag in cfg.ability_tags:
			if not known.has(tag):
				failures.append("%s: tag '%s' 不在词表(typo? 新词先入 DESCRIPTIVE_TAGS 或常量类)" % [cfg.config_id, tag])
		# active 技能(有 active_use 组件)必填 RANGE + TARGETING —— stance 的
		# "RANGE 缺省被读成 1" 坑从此结构性消灭
		if cfg.active_use_components.is_empty():
			continue
		if not cfg.metadata.has(HexBattleSkillMetaKeys.RANGE):
			failures.append("%s: active 技能缺 RANGE meta(缺省会被 can_use_skill_on 读成 1)" % cfg.config_id)
		var targeting: Variant = cfg.metadata.get(HexBattleSkillMetaKeys.TARGETING, null)
		if targeting == null:
			failures.append("%s: active 技能缺 TARGETING meta(actor/coord/self)" % cfg.config_id)
		elif not (str(targeting) in valid_targeting):
			failures.append("%s: TARGETING '%s' 不是合法取值" % [cfg.config_id, str(targeting)])
