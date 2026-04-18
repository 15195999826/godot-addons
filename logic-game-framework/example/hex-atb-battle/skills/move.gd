## 移动 - 移动到相邻格子（两阶段）
##
## 阶段：
##   START  (0ms):   StartMoveAction 预订目标格
##   EXECUTE (100ms): ApplyMoveAction 实际到达
##   END   (200ms):
class_name HexBattleMove


const CONFIG_ID := "action_move"
const TIMELINE_ID := "action_move"


static var MOVE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	200.0,
	{
		TimelineTags.START: 0.0,
		TimelineTags.EXECUTE: 100.0,
		TimelineTags.END: 200.0,
	}
)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("移动")
	.description("移动到相邻格子")
	.ability_tags(["action", "move"])
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			GameEvent.ABILITY_ACTIVATE_EVENT,
			HexBattleSkillHelpers.ability_activate_filter
		))
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.START, [HexBattleStartMoveAction.new(
			HexBattleTargetSelectors.ability_owner(),
			HexBattleSkillHelpers.target_coord_from_event()
		)])
		.on_tag(TimelineTags.EXECUTE, [HexBattleApplyMoveAction.new(
			HexBattleTargetSelectors.ability_owner(),
			HexBattleSkillHelpers.target_coord_from_event()
		)])
		.build()
	)
	.build()
)
