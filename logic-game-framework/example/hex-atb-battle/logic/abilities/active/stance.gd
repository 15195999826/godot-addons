## Stance #14 - 姿态切换 (Wrath / Calm)
##
## 设计卡: 两姿态主动切换。Wrath 造伤+50%/受伤+50%; Calm 造伤-25%/受伤-25%。
##
## 实现 (per phase-03-stance.md):
##   - 单 Ability + 2 个 loose tag (stance:skill_stance:wrath / :calm)
##   - NoInstance lifecycle: on_apply 默认进入 Wrath; on_remove 清两 tag
##   - 主动 use timeline 切换 tag (FlowAction.if_ + LooseTagAction)
##   - outgoing / incoming damage 修正由本 Ability 挂的两个 PreEventConfig 决定:
##     incoming filter target_actor_id == owner / outgoing filter source_actor_id == owner.
##
## V1 受控边界 (phase 文档): 测试 / 装备路径保证同一 actor 不会有多个 skill_stance 实例。
## 若未来引入 loadout / AI grant, 需补 AbilityConfig.unique_by_config (本 phase 不实现)。
class_name HexBattleStance


const CONFIG_ID := "skill_stance"
const TIMELINE_ID := "skill_stance"
const WRATH_TAG := "stance:skill_stance:wrath"
const CALM_TAG := "stance:skill_stance:calm"
const WRATH_MULT := 1.5
const CALM_MULT := 0.75
const COOLDOWN_MS := 2000.0


static var STANCE_TIMELINE := TimelineData.new(TIMELINE_ID, 300.0, {
	TimelineTags.HIT: 150.0,
	TimelineTags.END: 300.0,
})


# ============================================================
# Predicates / mult lookup
# ============================================================

## flow predicate: 当前是否处于 Wrath 状态 (用于切换分支)
static func _has_wrath(ctx: ExecutionContext) -> bool:
	var oid := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var actor := GameWorld.get_actor(oid)
	var aset := IAbilitySetOwner.get_ability_set(actor)
	return aset != null and aset.has_tag(WRATH_TAG)


## PreEvent handler 共用: 根据 ability_set 当前 stance tag 选择 multiplier
static func _stance_mult(ctx: AbilityLifecycleContext) -> float:
	if ctx.ability_set == null:
		return 1.0
	if ctx.ability_set.has_tag(WRATH_TAG):
		return WRATH_MULT
	if ctx.ability_set.has_tag(CALM_TAG):
		return CALM_MULT
	return 1.0


# ============================================================
# PreEventConfig: incoming / outgoing damage 修正
# ============================================================

static func _incoming_pre_event() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			var mult := _stance_mult(ctx)
			if is_equal_approx(mult, 1.0):
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", mult, ctx.ability.config_id, "姿态受伤"),
			]),
		func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return str(event_dict.get("target_actor_id", "")) == ctx.owner_actor_id,
		"Stance incoming"
	)


static func _outgoing_pre_event() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			var mult := _stance_mult(ctx)
			if is_equal_approx(mult, 1.0):
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", mult, ctx.ability.config_id, "姿态造伤"),
			]),
		func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return str(event_dict.get("source_actor_id", "")) == ctx.owner_actor_id,
		"Stance outgoing"
	)


# ============================================================
# Ability definition
# ============================================================

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("姿态切换")
	.description("在 Wrath (造伤/受伤 +50%) 与 Calm (造伤/受伤 -25%) 间切换")
	.ability_tags(["skill", "active", "self", "stance"])
	.component_config(NoInstanceConfig.builder()
		.on_apply_actions(_on_apply_actions())
		.on_remove_actions(_on_remove_actions())
		.build())
	.component_config(_incoming_pre_event())
	.component_config(_outgoing_pre_event())
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("melee_slash")
		)])
		.on_tag(TimelineTags.HIT, [FlowAction.if_(
			_has_wrath,
			_wrath_to_calm_actions(),
			_calm_to_wrath_actions(),
		)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())


# ============================================================
# Lifecycle / switch action arrays (typed Array[Action.BaseAction])
# ============================================================

static func _on_apply_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
		LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
		LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
	]
	return arr


static func _on_remove_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
		LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
	]
	return arr


static func _wrath_to_calm_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
		LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
	]
	return arr


static func _calm_to_wrath_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
		LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
	]
	return arr
