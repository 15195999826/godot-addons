## DisplacementTranslator - 强制位移事件翻译员
##
## 将 actor_displaced 翻译为 VisualMoveAction。动画时长直接读事件里的
## action_lock_duration_ms，避免 frontend 回查 ability config 或重算公式。
class_name FrontendDisplacementTranslator
extends Translator


func _init() -> void:
	translator_name = "DisplacementTranslator"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.ACTOR_DISPLACED_EVENT


func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
	var config := query.get_animation_config()
	var e := BattleEvents.ActorDisplacedEvent.from_dict(event)
	var duration := e.action_lock_duration_ms
	if duration <= 0.0:
		duration = config.move_duration

	var from_hex := HexCoord.from_dict(e.from_hex)
	var to_hex := HexCoord.from_dict(e.to_hex)
	var move_action := VisualMoveAction.new(
		e.actor_id,
		Vector2(from_hex.q, from_hex.r),
		Vector2(to_hex.q, to_hex.r),
		duration,
		config.move_easing
	)
	return [move_action]
