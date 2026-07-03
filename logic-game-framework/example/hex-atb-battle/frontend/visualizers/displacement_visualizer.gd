## DisplacementVisualizer - 强制位移事件转换器
##
## 将 actor_displaced 翻译为 MoveAction。动画时长直接读事件里的
## action_lock_duration_ms，避免 frontend 回查 ability config 或重算公式。
class_name FrontendDisplacementVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "DisplacementVisualizer"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.ACTOR_DISPLACED_EVENT


func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	var e := BattleEvents.ActorDisplacedEvent.from_dict(event)
	var duration := e.action_lock_duration_ms
	if duration <= 0.0:
		duration = config.move_duration

	var move_action := FrontendMoveAction.new(
		e.actor_id,
		HexCoord.from_dict(e.from_hex),
		HexCoord.from_dict(e.to_hex),
		duration,
		config.move_easing
	)
	return [move_action]
