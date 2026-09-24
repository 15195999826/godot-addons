## VisualFacingStateAction - 朝向状态变更卡片
##
## 由项目翻译员翻译朝向变化事件产生;VisualUpdater 瞬时 (无 duration / 无 lerp) 写入
## ActorVisualState.facing_direction。朝向编号含义由项目定。
##
## 不引入 turn-speed / facing-lock / 旋转动画。
class_name VisualFacingStateAction
extends VisualAction


## 目标 actor 的新朝向编号
var new_direction: int = 0


func _init(p_actor_id: String, p_new_direction: int) -> void:
	super._init(KIND_FACING_STATE, 0.0, 0.0)
	actor_id = p_actor_id
	new_direction = p_new_direction
