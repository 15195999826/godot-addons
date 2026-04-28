## ApplyShieldStateAction - 对 actor.shields 数组的瞬时增 / 改 / 删指令
##
## 由 ShieldBarVisualizer 翻译事件流(AbilityGranted / AbilityRemoved /
## DamageEvent.consumption_records)产生,RenderWorld._apply_apply_shield_state_action
## 应用。
##
## 与 ApplyBuffStateAction 平行:这条专门维护 shields 数组,粒度是单个 shield
## 实例(每个独立 ward 实例一条 record),保留 capacity/priority 等数据给
## ShieldBarView 决定如何显示(聚合 / 分段 / 按来源分色)。
##
## ADD/UPDATE 携带完整 summary 用以创建或覆盖;REMOVE 只用 shield_id 定位删除。
class_name FrontendApplyShieldStateAction
extends FrontendVisualAction


enum Op { ADD, UPDATE, REMOVE }


var op: Op
var shield_id: String = ""
var summary: FrontendShieldSummary = null


func _init(
	p_actor_id: String,
	p_op: Op,
	p_shield_id: String,
	p_summary: FrontendShieldSummary = null,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.APPLY_SHIELD_STATE, 0.0, p_delay)
	actor_id = p_actor_id
	op = p_op
	shield_id = p_shield_id
	summary = p_summary
