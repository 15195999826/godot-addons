## RegenerationVisualizer - 自然恢复事件转换器
##
## RegenerationEvent 不是 HealEvent: 不走 heal pipeline, 但 replay/frontend 仍需把
## actual_amount 写回 HP state, 否则前端血条会和逻辑 HP 漂移。
class_name FrontendRegenerationVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "RegenerationVisualizer"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.REGENERATION_EVENT


func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var e := BattleEvents.RegenerationEvent.from_dict(event)
	var target_id := e.target_actor_id
	if target_id.is_empty() or e.actual_amount <= 0.0:
		return []

	var config := context.get_animation_config()
	var target_position := context.get_actor_position(target_id)
	var actions: Array[FrontendVisualAction] = []
	actions.append(FrontendFloatingTextAction.new(
		target_id,
		"+%d" % roundi(e.actual_amount),
		Color(0.35, 1.0, 0.45),
		target_position,
		FrontendFloatingTextAction.FloatingTextStyle.HEAL,
		config.heal_floating_text_duration
	))
	actions.append(FrontendApplyHPDeltaAction.new(target_id, e.actual_amount))
	return actions
