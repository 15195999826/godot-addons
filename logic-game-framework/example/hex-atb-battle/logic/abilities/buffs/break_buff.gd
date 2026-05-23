## Break Buff - 破坏状态 (passive control)
##
## V1 语义:
## - cant_use_passive gate tag (component-owned, 供 cleanse / UI / immunity 查询)
## - 内嵌 _BreakPassivesAction (SkillLocalAction) on_apply: 给目标当前每个 passive ability
##   add_disabled_source(buff.id); _UnbreakPassivesAction on_remove: remove_disabled_source。
## - TimeDurationConfig → 到期自动 ability.expire → on_remove → 撤销 source 引用
## - 多个 Break 实例独立: 每个 source_id 独立 add/remove; passive ability 的引用计数 Set
##   只有当最后一个 Break source 移除后 (empty → non-empty 边界) 才恢复; 由 Ability
##   层 _disabled_sources Dictionary + _notify_components_enabled hook 自动处理。
##
## Goal Phase B2 关键设计 (per advanced-skills-impl-plan):
## - Break = cant_use_passive + passive Ability disabled state + duration
## - Ability.receive_event() / tick_executions() 顶层短路 (在 core/abilities/core/ability.gd)
##   覆盖 triggered passive (Thorn / Deathrattle), periodic passive (DemonForm),
##   持久 stat modifier 由 StatModifierComponent / DynamicStatModifierComponent
##   的 on_passive_disabled / on_passive_enabled hook 撤销+重建。
## - NoInstanceComponent / ActivateInstanceComponent 严禁实现 break hook (注释明示)。
##
## semantic ability tags: buff / negative / control / passive_break
## functional gate tag: cant_use_passive (仅查询用; 不参与 ActiveGateway condition,
##   因为 passive 不走 active condition 链路, Ability 顶层 is_disabled 直接 gate)
class_name HexBattleBreakBuff


const CONFIG_ID := "buff_break"
const TAG_CANT_USE_PASSIVE := "cant_use_passive"
const PASSIVE_TAG := "passive"


const DEFAULT_DURATION_MS := 2000.0


static func create_config(duration_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("破坏")
		.description("被动技能在持续时间内失效")
		.ability_tags(["buff", "negative", "control", "passive_break"])
		.meta("duration_ms", duration_ms)
		.component_config(
			TagComponentConfig.builder()
			.tag(TAG_CANT_USE_PASSIVE)
			.build()
		)
		.component_config(TimeDurationConfig.new(duration_ms))
		.component_config(
			NoInstanceConfig.builder()
			.on_apply_actions(_on_apply_actions())
			.on_remove_actions(_on_remove_actions())
			.build()
		)
		.build()
	)


static func _on_apply_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		_BreakPassivesAction.new(),
		StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("control_broken"),
		),
	]
	return arr


static func _on_remove_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		_UnbreakPassivesAction.new(),
	]
	return arr


# ========== 内嵌 SkillLocalAction (Phase B2 V1 私有) ==========

## 给目标的所有 passive ability 添加 disabled source = self buff ability id。
## 仅过滤 ability_tags.has("passive"); 跳过 self / expired。
class _BreakPassivesAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleBreakBuff.CONFIG_ID)
		type = "break_passives"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var self_ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if self_ability == null:
			return ActionResult.create_success_result([], {})
		var owner_id := self_ability.owner_actor_id
		var actor := GameWorld.get_actor(owner_id)
		var aset := IAbilitySetOwner.get_ability_set(actor)
		if aset == null:
			return ActionResult.create_success_result([], {})
		var disabled_count := 0
		for ab in aset.get_abilities():
			if ab.id == self_ability.id:
				continue
			if ab.is_expired():
				continue
			if not ab.has_ability_tag(HexBattleBreakBuff.PASSIVE_TAG):
				continue
			ab.add_disabled_source(self_ability.id)
			disabled_count += 1
		return ActionResult.create_success_result([], { "disabled_passive_count": disabled_count })


## 撤销本 Break buff 的 disabled source 引用。
## 其它 Break 实例的 source 仍在的话, passive 保持 disabled 直到最后一个移除。
class _UnbreakPassivesAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleBreakBuff.CONFIG_ID)
		type = "unbreak_passives"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var self_ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if self_ability == null:
			return ActionResult.create_success_result([], {})
		var owner_id := self_ability.owner_actor_id
		var actor := GameWorld.get_actor(owner_id)
		var aset := IAbilitySetOwner.get_ability_set(actor)
		if aset == null:
			return ActionResult.create_success_result([], {})
		for ab in aset.get_abilities():
			if ab.id == self_ability.id:
				continue
			# 注意: 即使 ab.is_expired(), 也要 remove (idempotent; 不影响清理)
			ab.remove_disabled_source(self_ability.id)
		return ActionResult.create_success_result([], {})
