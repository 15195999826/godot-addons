## MoveTranslator - 移动事件翻译员
##
## 将 move_start 事件翻译为 VisualMoveAction
class_name FrontendMoveTranslator
extends Translator


func _init() -> void:
	translator_name = "MoveTranslator"


## 检查是否为移动开始事件
func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.MOVE_START_EVENT


## 翻译移动事件为 VisualMoveAction
func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
	var config := query.get_animation_config()

	var e := BattleEvents.MoveStartEvent.from_dict(event)
	var actor_id := e.actor_id
	# 注意：from_hex/to_hex 在 BattleEvents 中是 Dictionary，需要转换为 HexCoord；卡片只带 axial 浮点
	var from_hex := HexCoord.from_dict(e.from_hex)
	var to_hex := HexCoord.from_dict(e.to_hex)

	var move_action := VisualMoveAction.new(
		actor_id,
		Vector2(from_hex.q, from_hex.r),
		Vector2(to_hex.q, to_hex.r),
		config.move_duration,
		config.move_easing
	)

	return [move_action]
