## ActorFacingChangedTranslator
##
## 监听 actor_facing_changed event → 翻译为 VisualFacingStateAction (瞬时状态更新).
class_name FrontendActorFacingChangedTranslator
extends Translator


func _init() -> void:
	translator_name = "ActorFacingChangedTranslator"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.ACTOR_FACING_CHANGED_EVENT


func translate(event: Dictionary, _query: VisualStateQuery) -> Array[VisualAction]:
	var e := BattleEvents.ActorFacingChangedEvent.from_dict(event)
	if e.actor_id.is_empty():
		return []
	return [VisualFacingStateAction.new(e.actor_id, e.new_direction)]
