## DeathTranslator - 死亡事件翻译员
##
## 将 death 事件翻译为死亡动画卡片
class_name FrontendDeathTranslator
extends Translator


func _init() -> void:
	translator_name = "DeathTranslator"


## 检查是否为死亡事件
func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.DEATH_EVENT


## 翻译死亡事件为卡片
func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
	var config := query.get_animation_config()

	var e := BattleEvents.DeathEvent.from_dict(event)
	var actor_id := e.actor_id
	var killer_id := e.killer_actor_id

	var actions: Array[VisualAction] = []

	# 死亡动画
	var death_action := VisualDeathAction.new(
		actor_id,
		config.death_duration,
		killer_id
	)
	actions.append(death_action)

	return actions
