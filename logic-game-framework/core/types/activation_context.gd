extends RefCounted
class_name ActivationContext

var source_actor_id: String
var targets: Array[Actor]
var logic_time: float

func _init(source_actor_id_value: String, targets_value: Array[Actor], logic_time_value: float) -> void:
	source_actor_id = source_actor_id_value
	targets = targets_value
	logic_time = logic_time_value
