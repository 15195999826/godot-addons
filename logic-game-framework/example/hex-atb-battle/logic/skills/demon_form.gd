## Demon Form #15 - 恶魔形态被动
##
## 设计卡: passive, 每 3s 永久 +2 atk, 无上限。
##
## 实现 (per phase-04-demon-form.md):
##   - 单 passive Ability + StatModifierConfig.scale_by_stacks() (§0.X 前置)
##   - GRANTED_SELF trigger 启动 periodic tick timeline (3s loop)
##   - _DemonFormTickAction (SkillLocalAction, 私有, 不进 public actions):
##       每 tick: ability.add_stacks(1) + 自动同步 StatModifierComponent 更新 atk modifier
##       (§0.X on_stacks_changed hook 走 update_modifier 原子更新);
##       push AbilityStacksChanged + stageCue(demon_form_pulse)
class_name HexBattleDemonForm


const CONFIG_ID := "passive_demon_form"
const TICK_TIMELINE_ID := "passive_demon_form_tick"
const CUE_DEMON_FORM_PULSE := "demon_form_pulse"
const TICK_INTERVAL_MS := 3000.0
const ATK_PER_STACK := 2.0
const MAX_STACKS := 999999


static var DEMON_FORM_TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)


class _DemonFormTickAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleDemonForm.CONFIG_ID)
		type = "demon_form_tick"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if ability == null or ability.is_expired():
			return ActionResult.create_success_result([], {})
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var actor := battle.get_character_actor(ability.owner_actor_id) if battle != null else null
		if actor == null or actor.is_dead():
			return ActionResult.create_success_result([], {})

		var stacks_before := ability.get_stacks()
		ability.add_stacks(1)  # §0.X: on_stacks_changed 自动更新 StatModifier
		var stacks_after := ability.get_stacks()

		var events: Array[Dictionary] = []
		var stacks_changed := GameEvent.AbilityStacksChanged.create(
			ability.owner_actor_id,
			ability.id,
			ability.config_id,
			stacks_before,
			stacks_after,
		)
		events.append(ctx.event_collector.push(stacks_changed.to_dict()))

		var cue_targets: Array[String] = [ability.owner_actor_id]
		var stage_cue := GameEvent.StageCue.create(
			ability.owner_actor_id,
			cue_targets,
			HexBattleDemonForm.CUE_DEMON_FORM_PULSE,
			{ "stacks": stacks_after }
		)
		events.append(ctx.event_collector.push(stage_cue.to_dict()))

		return ActionResult.create_success_result(events, { "demon_stacks": stacks_after })


static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("恶魔形态")
	.description("每 3 秒永久 +2 攻击力,无上限")
	.ability_tags(["passive", "buff", "positive"])
	.stacks(0, MAX_STACKS, Ability.OVERFLOW_CAP)
	.component_config(StatModifierConfig.builder()
		.modifier(HexBattleCharacterAttributeSet.atk_attribute, AttributeModifier.Type.ADD_BASE, ATK_PER_STACK)
		.scale_by_stacks()
		.build())
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_end([_DemonFormTickAction.new()])
		.build())
	.build())
