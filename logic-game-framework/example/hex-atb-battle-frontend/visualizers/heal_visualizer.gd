## HealVisualizer - 治疗事件转换器
##
## 将 heal 事件翻译为飘字和血条更新动作
class_name FrontendHealVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "HealVisualizer"


## 检查是否为治疗事件
func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == "heal"


## 翻译治疗事件为视觉动作
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	
	var e := BattleEvents.HealEvent.from_dict(event)
	var target_id := e.target_actor_id
	var heal_amount := e.heal_amount
	
	var target_position := context.get_actor_position(target_id)
	var current_hp := context.get_actor_hp(target_id)
	var max_hp := context.get_actor_max_hp(target_id)
	
	var actions: Array[FrontendVisualAction] = []
	
	# 1. 治疗飘字
	var text := "+%d" % roundi(heal_amount)
	var color := Color(0.2, 1.0, 0.2)  # 绿色
	
	var floating_text := FrontendFloatingTextAction.new(
		target_id,
		text,
		color,
		target_position,
		FrontendFloatingTextAction.FloatingTextStyle.HEAL,
		config.heal_floating_text_duration
	)
	actions.append(floating_text)
	
	# 2. 血条更新
	var new_hp := minf(current_hp + heal_amount, max_hp)
	var update_hp := FrontendUpdateHPAction.new(
		target_id,
		current_hp,
		new_hp,
		config.heal_hp_bar_duration
	)
	actions.append(update_hp)
	
	return actions
