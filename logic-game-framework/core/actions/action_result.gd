class_name ActionResult
extends RefCounted

var success: bool
var event_dicts: Array[Dictionary]
var failure_reason: String = ""
var data: Dictionary = {}

func _init(p_success: bool, p_event_dicts: Array[Dictionary], p_failure_reason: String = "", p_data: Dictionary = {}):
	success = p_success
	event_dicts = p_event_dicts
	failure_reason = p_failure_reason
	data = p_data

static func create_success_result(p_event_dicts: Array[Dictionary], p_data: Dictionary = {}) -> ActionResult:
	return ActionResult.new(true, p_event_dicts, "", p_data)

static func create_failure_result(reason: String, p_event_dicts: Array[Dictionary] = []) -> ActionResult:
	return ActionResult.new(false, p_event_dicts, reason, {})
