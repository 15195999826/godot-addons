## MutableEvent - 可修改事件
##
## 封装事件的原始数据和修改操作。
## 修改按类型分组后按固定顺序计算：SET → ADD → MULTIPLY
## - 多个 SET 只取最后一个
## - 所有 ADD 累加
## - 所有 MULTIPLY 依次相乘
class_name MutableEvent
extends RefCounted

var original: Dictionary
var phase: String
var cancelled := false
var cancel_reason := ""
var cancelled_by := ""
var _modifications: Array[Modification] = []

func _init(original_event_dict: Dictionary, phase_value: String):
	original = original_event_dict
	phase = phase_value

func get_modifications() -> Array[Modification]:
	return _modifications

func add_modification(modification: Modification) -> void:
	_modifications.append(modification)

func add_modifications(modifications: Array[Modification]) -> void:
	_modifications.append_array(modifications)

func cancel(handler_id: String, reason: String) -> void:
	cancelled = true
	cancelled_by = handler_id
	cancel_reason = reason

func get_current_value(field: String) -> Variant:
	var original_value: Variant = original.get(field, null)
	if typeof(original_value) not in [TYPE_INT, TYPE_FLOAT]:
		return original_value

	var grouped := _get_grouped_field_mods(field)
	if grouped.sets.is_empty() and grouped.adds.is_empty() and grouped.muls.is_empty():
		return original_value

	return _compute_value(float(original_value), grouped)

func to_final_event() -> Dictionary:
	if _modifications.is_empty():
		return original

	var final_event := original.duplicate(true)
	for field in _get_modified_fields():
		final_event[field] = get_current_value(field)
	return final_event

func get_original_values() -> Dictionary:
	var result := {}
	for field in _get_modified_fields():
		result[field] = original.get(field, null)
	return result

func get_final_values() -> Dictionary:
	var result := {}
	for field in _get_modified_fields():
		result[field] = get_current_value(field)
	return result

func get_field_computation_steps(field: String) -> Dictionary:
	var original_value: Variant = original.get(field, null)
	if typeof(original_value) not in [TYPE_INT, TYPE_FLOAT]:
		return {}

	var grouped := _get_grouped_field_mods(field)
	if grouped.sets.is_empty() and grouped.adds.is_empty() and grouped.muls.is_empty():
		return {}

	var steps: Array[Dictionary] = []
	var value := float(original_value)
	var sets: Array[Modification] = grouped.sets
	var adds: Array[Modification] = grouped.adds
	var muls: Array[Modification] = grouped.muls

	if not sets.is_empty():
		var last_set: Modification = sets[-1]
		value = last_set.value
		steps.append(_create_step(last_set, "set", value))

	for mod in adds:
		value += mod.value
		steps.append(_create_step(mod, "add", value))

	for mod in muls:
		value *= mod.value
		steps.append(_create_step(mod, "multiply", value))

	return {
		"field": field,
		"originalValue": original_value,
		"finalValue": value,
		"steps": steps,
	}

func get_all_computation_steps() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for field in _get_modified_fields():
		var record := get_field_computation_steps(field)
		if not record.is_empty():
			records.append(record)
	return records

func format_computation_log(field: String) -> String:
	var record := get_field_computation_steps(field)
	if record.is_empty():
		return "%s: no modifications" % field

	var lines: Array[String] = ["%s: %s \t \t%s" % [field, str(record["originalValue"]), str(record["finalValue"])]]

	for step: Dictionary in record["steps"]:
		var source: String = str(step.get("sourceName", "")) if step.get("sourceName") else str(step.get("sourceId", "unknown"))
		var op_sign := _get_operation_sign(step)
		lines.append("  [%s] %s%s -> %s" % [source, op_sign, str(step.get("value", "")), str(step.get("resultValue", ""))])

	return "\n".join(lines)

func _get_modified_fields() -> Array[String]:
	var fields := {}
	for mod in _modifications:
		fields[mod.field] = true
	var result: Array[String] = []
	result.assign(fields.keys())
	return result

func _get_grouped_field_mods(field: String) -> Dictionary:
	var sets: Array[Modification] = []
	var adds: Array[Modification] = []
	var muls: Array[Modification] = []

	for mod in _modifications:
		if mod.field != field:
			continue
		match mod.operation:
			Modification.Operation.SET:
				sets.append(mod)
			Modification.Operation.ADD:
				adds.append(mod)
			Modification.Operation.MULTIPLY:
				muls.append(mod)

	return {
		"sets": sets,
		"adds": adds,
		"muls": muls,
	}

func _compute_value(base_value: float, grouped: Dictionary) -> float:
	var value := base_value
	var sets: Array[Modification] = grouped.sets
	var adds: Array[Modification] = grouped.adds
	var muls: Array[Modification] = grouped.muls
	if not sets.is_empty():
		value = sets[-1].value
	for mod in adds:
		value += mod.value
	for mod in muls:
		value *= mod.value
	return value

func _create_step(mod: Modification, operation: String, result_value: float) -> Dictionary:
	return {
		"sourceId": mod.source_id if mod.source_id != "" else "unknown",
		"sourceName": mod.source_name if mod.source_name != "" else null,
		"operation": operation,
		"value": mod.value,
		"resultValue": result_value,
	}

func _get_operation_sign(step: Dictionary) -> String:
	match step.get("operation", "") as String:
		"add":
			return "+" if (step.get("value", 0.0) as float) >= 0 else ""
		"multiply":
			return "x"
		_:
			return "="
