class_name System
extends RefCounted

const SystemPriority = {
	"HIGHEST": 0,
	"HIGH": 100,
	"NORMAL": 500,
	"LOW": 900,
	"LOWEST": 1000,
}

var type: String = "system"
var priority: int = SystemPriority.NORMAL
var _enabled := true
var _instance: GameplayInstance = null

func _init(priority_value: int = SystemPriority.NORMAL):
	priority = priority_value

func get_enabled() -> bool:
	return _enabled

func set_enabled(value: bool) -> void:
	_enabled = value

func on_register(instance: GameplayInstance) -> void:
	_instance = instance

func on_unregister() -> void:
	_instance = null

func tick(_actors: Array[Actor], _dt: float) -> void:
	pass

func get_logic_time() -> float:
	if _instance == null:
		return 0.0
	return _instance.get_logic_time()

func filter_actors_by_type(actors: Array[Actor], actor_type: String) -> Array[Actor]:
	var results: Array[Actor] = []
	for actor in actors:
		if actor.type == actor_type:
			results.append(actor)
	return results



class NoopSystem:
	extends System

	func _init(priority_value: int = SystemPriority.NORMAL):
		super._init(priority_value)
		type = "noop"
