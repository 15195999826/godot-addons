## Cleanse #D - 清除友方 / 自身 1 个 negative buff
##
## V1 行为 (per Goal):
## - target: 友方 CharacterActor 或自己; 不能选敌方 / EnvironmentActor
## - range=3
## - effect: 移除 1 个 negative buff Ability (ability_tags 含 "buff" + "negative")
## - 选择优先级 (按 ability_tags 含):
##     1. "control" (Stun / Silence)
##     2. "passive_break" (Break)
##     3. 其它 negative (Poison / Expose)
##   同级按 AbilitySet.get_abilities() 顺序 (grant order)。
## - 目标无 negative buff 时 success no-op (metadata cleanse_removed=false)
## - 不附带 heal; 不做 Dispel enemy positive buff (V1 排除); 不抽框架层 Primitive Action
##   (skill-local 内嵌 SkillLocalAction)。
##
## 执行: target.ability_set.revoke_ability(buff.id, REVOKE_REASON_DISPELLED, "cleanse")
class_name HexBattleCleanse


const CONFIG_ID := "skill_cleanse"
const COOLDOWN_MS := 8000.0


# 优先级 (low int = high priority)
const _PRIORITY_CONTROL := 0
const _PRIORITY_PASSIVE_BREAK := 1
const _PRIORITY_OTHER := 2


class _CleanseAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.current_target(), HexBattleCleanse.CONFIG_ID)
		type = "cleanse_dispel"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], { "cleanse_removed": false })
		var targets := get_targets(ctx)
		if targets.is_empty():
			return ActionResult.create_success_result([], { "cleanse_removed": false })
		var target_id := targets[0]
		var target := battle.get_actor(target_id) as CharacterActor
		if target == null:
			return ActionResult.create_success_result([], { "cleanse_removed": false })

		# 找最高优先级的 negative buff
		var best_ability: Ability = null
		var best_priority := 999
		var best_index := 999999
		var idx := -1
		for ability in target.ability_set.get_abilities():
			idx += 1
			if ability.is_expired():
				continue
			if not ability.has_ability_tag(HexBattleBuffTags.TAG_BUFF):
				continue
			if not ability.has_ability_tag(HexBattleBuffTags.TAG_NEGATIVE):
				continue
			var prio := HexBattleCleanse._compute_priority(ability)
			if prio < best_priority or (prio == best_priority and idx < best_index):
				best_priority = prio
				best_index = idx
				best_ability = ability

		if best_ability == null:
			return ActionResult.create_success_result([], {
				"cleanse_removed": false,
				"target_actor_id": target_id,
			})

		var removed_id := best_ability.id
		var removed_cfg := best_ability.config_id
		target.ability_set.revoke_ability(
			best_ability.id,
			AbilitySet.REVOKE_REASON_DISPELLED,
			"cleanse",
		)
		return ActionResult.create_success_result([], {
			"cleanse_removed": true,
			"removed_ability_id": removed_id,
			"removed_config_id": removed_cfg,
			"target_actor_id": target_id,
		})


static func _compute_priority(ability: Ability) -> int:
	if ability.has_ability_tag(HexBattleBuffTags.TAG_CONTROL):
		return _PRIORITY_CONTROL
	if ability.has_ability_tag(HexBattleBuffTags.TAG_PASSIVE_BREAK):
		return _PRIORITY_PASSIVE_BREAK
	return _PRIORITY_OTHER


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("净化")
	.description("移除友方目标身上 1 个负面 buff (control → passive_break → 其它)")
	.ability_tags(["skill", "active", "ranged", "ally", "self", "cleanse"])
	.meta(HexBattleSkillMetaKeys.RANGE, 3)
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_ACTOR)
	.active_use(
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(HexBattleStdTimelines.MELEE_500)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val(HexBattleCues.CONTROL_CLEANSED),
		)])
		.on_tag(TimelineTags.HIT, [_CleanseAction.new()])
		.build()
	)
	.build()
)
