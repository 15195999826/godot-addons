## Dota2IntentStepResult - systems 每 tick 推进 current intent 后返回的执行结果
##
## controller-intent-model.md「Systems report facts. Controller owns lifecycle.」
## movement / ability 系统推进 current intent 后返回此对象（事实），controller 据此
## 决定 keep / complete / fail / interrupt / replace。
class_name Dota2IntentStepResult
extends RefCounted


var status: String = Dota2IntentStatus.RUNNING
var reason: String = ""


func _init(p_status: String, p_reason: String = "") -> void:
	status = p_status
	reason = p_reason


static func running(reason: String = "") -> Dota2IntentStepResult:
	return Dota2IntentStepResult.new(Dota2IntentStatus.RUNNING, reason)


static func completed(reason: String = "") -> Dota2IntentStepResult:
	return Dota2IntentStepResult.new(Dota2IntentStatus.COMPLETED, reason)


static func failed(reason: String = "") -> Dota2IntentStepResult:
	return Dota2IntentStepResult.new(Dota2IntentStatus.FAILED, reason)


static func interrupted(reason: String = "") -> Dota2IntentStepResult:
	return Dota2IntentStepResult.new(Dota2IntentStatus.INTERRUPTED, reason)


func is_terminal() -> bool:
	return status != Dota2IntentStatus.RUNNING
