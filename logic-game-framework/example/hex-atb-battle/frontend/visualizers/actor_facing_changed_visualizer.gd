## Phase F · ActorFacingChangedVisualizer
##
## 监听 actor_facing_changed event → 翻译为 ApplyFacingStateAction (瞬时状态更新).
class_name FrontendActorFacingChangedVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "ActorFacingChangedVisualizer"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == "actor_facing_changed"


func translate(event: Dictionary, _context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var actor_id := str(event.get("actor_id", ""))
	if actor_id.is_empty():
		return []
	var new_direction := int(event.get("new_direction", 0))
	return [FrontendApplyFacingStateAction.new(actor_id, new_direction)]
