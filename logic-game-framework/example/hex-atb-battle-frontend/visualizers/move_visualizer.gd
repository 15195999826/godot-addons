## MoveVisualizer - 移动事件转换器
##
## 将 move_start 事件翻译为 MoveAction
class_name FrontendMoveVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "MoveVisualizer"


## 检查是否为移动开始事件
func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == "move_start"


## 翻译移动事件为 MoveAction
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	
	var e := BattleEvents.MoveStartEvent.from_dict(event)
	var actor_id := e.actor_id
	# 注意：from_hex/to_hex 在 BattleEvents 中是 Dictionary，需要转换为 HexCoord
	var from_hex := HexCoord.from_dict(e.from_hex)
	var to_hex := HexCoord.from_dict(e.to_hex)
	
	var move_action := FrontendMoveAction.new(
		actor_id,
		from_hex,
		to_hex,
		config.move_duration,
		config.move_easing
	)
	
	return [move_action]
