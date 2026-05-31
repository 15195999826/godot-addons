## Dota2DecisionResult - brain decision 的输出（README.md（Controller / Intent 模型 节））
##
## decision 只在 current intent 需要被 create/replace/complete/fail/interrupt/重新考虑
## 时跑（不每 tick 跑）。三种动作：
##   KEEP   保持 current intent（不动）
##   CREATE 用 new_intent 替换 current intent（含首次创建 / interrupt-replace）
##   CLEAR  清空 current intent（下 tick 立即重决策）
class_name Dota2DecisionResult
extends RefCounted


const ACTION_KEEP := "keep"
const ACTION_CREATE := "create"
const ACTION_CLEAR := "clear"


var action: String = ACTION_KEEP
var new_intent: Dota2Intent = null
## interrupt-replace 时记录被打断的原因（事件 / debug 用）。
var replace_reason: String = ""


func _init(p_action: String, p_new_intent: Dota2Intent = null, p_replace_reason: String = "") -> void:
	action = p_action
	new_intent = p_new_intent
	replace_reason = p_replace_reason


static func keep() -> Dota2DecisionResult:
	return Dota2DecisionResult.new(ACTION_KEEP)


static func create(intent: Dota2Intent, replace_reason: String = "") -> Dota2DecisionResult:
	return Dota2DecisionResult.new(ACTION_CREATE, intent, replace_reason)


static func clear() -> Dota2DecisionResult:
	return Dota2DecisionResult.new(ACTION_CLEAR)
