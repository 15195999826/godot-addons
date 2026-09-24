## VisualBuffStateAction - 对 actor.buffs 数组的瞬时增 / 改 / 删指令
##
## 由项目翻译员翻译 buff 相关事件流产生,VisualUpdater.apply_buff_state 应用。
##
## ADD/UPDATE 携带完整 summary 用以创建或覆盖;REMOVE 只用 buff_id 定位删除。
class_name VisualBuffStateAction
extends VisualAction


enum Op { ADD, UPDATE, REMOVE }


var op: Op
var buff_id: String = ""
var summary: BuffSummary = null


func _init(
	p_actor_id: String,
	p_op: Op,
	p_buff_id: String,
	p_summary: BuffSummary = null,
	p_delay: float = 0.0
) -> void:
	super._init(KIND_BUFF_STATE, 0.0, p_delay)
	actor_id = p_actor_id
	op = p_op
	buff_id = p_buff_id
	summary = p_summary
