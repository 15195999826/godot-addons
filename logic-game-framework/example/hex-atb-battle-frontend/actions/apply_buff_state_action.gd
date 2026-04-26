## ApplyBuffStateAction - 对 actor.buffs 数组的瞬时增 / 改 / 删指令
##
## 由 BuffVisualizer 翻译事件流(AbilityGranted/Stacks/Removed/DamageEvent)
## 产生,RenderWorld._apply_apply_buff_state_action 应用。
##
## ADD/UPDATE 携带完整 summary 用以创建或覆盖;REMOVE 只用 buff_id 定位删除。
class_name FrontendApplyBuffStateAction
extends FrontendVisualAction


enum Op { ADD, UPDATE, REMOVE }


var op: Op
var buff_id: String = ""
var summary: FrontendBuffSummary = null


func _init(
	p_actor_id: String,
	p_op: Op,
	p_buff_id: String,
	p_summary: FrontendBuffSummary = null,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.APPLY_BUFF_STATE, 0.0, p_delay)
	actor_id = p_actor_id
	op = p_op
	buff_id = p_buff_id
	summary = p_summary
