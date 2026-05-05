class_name SimNavPassabilityClassRegistry
extends RefCounted


const PASS_CLASS_BITS: int = 16

var _classes: Array[SimNavPassabilityClassConfig] = []
var _by_name: Dictionary = {}
var _next_bit := 0


func register(config: SimNavPassabilityClassConfig) -> int:
	if config == null:
		push_error("[SimNavPassabilityClassRegistry] register: config is null")
		return 0
	if _next_bit >= PASS_CLASS_BITS:
		push_error("[SimNavPassabilityClassRegistry] registry full")
		return 0
	if _by_name.has(config.class_name_id):
		push_error("[SimNavPassabilityClassRegistry] duplicate class: %s" % config.class_name_id)
		return 0
	config.bit_index = _next_bit
	_next_bit += 1
	_classes.append(config)
	_by_name[config.class_name_id] = config
	return 1 << config.bit_index


func get_pass_class(name_id: String) -> SimNavPassabilityClassConfig:
	return _by_name.get(name_id, null) as SimNavPassabilityClassConfig


func get_mask(name_id: String) -> int:
	var config := get_pass_class(name_id)
	if config == null:
		return 0
	return 1 << config.bit_index


func get_class_by_mask(mask: int) -> SimNavPassabilityClassConfig:
	for config in _classes:
		if (1 << config.bit_index) == mask:
			return config
	return null


func get_classes() -> Array[SimNavPassabilityClassConfig]:
	return _classes


func max_clearance() -> float:
	var max_value := 0.0
	for config in _classes:
		max_value = maxf(max_value, config.clearance)
	return max_value


func size() -> int:
	return _classes.size()
