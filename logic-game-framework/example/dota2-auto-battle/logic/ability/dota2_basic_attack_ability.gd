## Dota2BasicAttackAbility - 基础攻击（首版即 LGF Ability，非 controller 直接掉血）
##
## lgf-skill-model.md / m1-contract.md 的最终边界从 M1 就位：
##   AttackTargetIntent
##     → Dota2BasicAttackAbility（AbilitySet.receive_event ABILITY_ACTIVATE_EVENT）
##       → on_timeline_start: attack_started 事件
##       → attack point keyframe（TimelineTags.HIT）→ Dota2DamageAction
##         → attack_landed / damage_applied /（致死）unit_died
##       → cooldown / cast timing 是 Ability/AbilitySet 执行状态（condition+cost）
##
## Timeline 故意最小（HIT @250ms / END @400ms），但 windup/backswing/projectile 之后
## 可在不改 intent 合同的前提下扩 keyframe。与 hex CrushingBlow 同构。
class_name Dota2BasicAttackAbility


const CONFIG_ID := "dota2_basic_attack"
const TIMELINE_ID := "dota2_basic_attack"


## attack point = TimelineTags.HIT @250ms；END @400ms。
## 总时长 (400ms) < 任何兵种 attack_interval_ms（900/1100），故 cooldown 严格 gate 攻击节奏。
static var BASIC_ATTACK_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	400.0,
	{
		TimelineTags.HIT: 250.0,
		TimelineTags.END: 400.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("Basic Attack")
	.description("Lane creep basic attack — Ability/Timeline/Action backed.")
	.ability_tags(["basic_attack", "active", "enemy"])
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([Dota2AttackStartedAction.new(
			Dota2TargetSelectors.current_target(),
			CONFIG_ID,
		)])
		.on_tag(TimelineTags.HIT, [Dota2DamageAction.new(
			Dota2TargetSelectors.current_target(),
		)])
		.condition(Condition.NoTagCondition.new(Dota2AttackCooldown.COOLDOWN_TAG))
		.cost(Dota2AttackCooldown.TimedCooldownCost.new())
		.build()
	)
	.build()
)


## 战斗启动时调一次，把基础攻击 timeline 注册进 TimelineRegistry。
static func register_timelines() -> void:
	TimelineRegistry.register(BASIC_ATTACK_TIMELINE)
