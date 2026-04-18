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
## 所属 GameplayInstance 的弱引用。
##
## 持强引用会和 GameplayInstance._systems 形成循环引用（GDScript RefCounted 无循环 GC），
## 导致 instance 及其所有 system 即便 shutdown 后仍被拖住无法释放。
## 弱引用让 instance 销毁完全由 GameWorld 决定，system 只是附属。
var _instance_ref: WeakRef = null

func _init(priority_value: int = SystemPriority.NORMAL):
	priority = priority_value

func get_enabled() -> bool:
	return _enabled

func set_enabled(value: bool) -> void:
	_enabled = value

func on_register(instance: GameplayInstance) -> void:
	_instance_ref = weakref(instance) if instance != null else null

func on_unregister() -> void:
	_instance_ref = null

func tick(_actors: Array[Actor], _dt: float) -> void:
	pass

## 返回所属 GameplayInstance；instance 已销毁时返回 null，调用方需短路。
func get_instance() -> GameplayInstance:
	if _instance_ref == null:
		return null
	return _instance_ref.get_ref() as GameplayInstance

func get_logic_time() -> float:
	var instance := get_instance()
	if instance == null:
		return 0.0
	return instance.get_logic_time()

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
