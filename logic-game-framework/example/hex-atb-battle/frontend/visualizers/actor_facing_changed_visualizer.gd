## Phase F · ActorFacingChangedVisualizer
##
## 监听 actor_facing_changed event → 翻译为 ApplyFacingStateAction (瞬时状态更新).
class_name FrontendActorFacingChangedVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "ActorFacingChangedVisualizer"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.ACTOR_FACING_CHANGED_EVENT


func translate(event: Dictionary, _context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var e := BattleEvents.ActorFacingChangedEvent.from_dict(event)
	if e.actor_id.is_empty():
		return []
	return [FrontendApplyFacingStateAction.new(e.actor_id, e.new_direction)]
