extends Node

var _instances: Dictionary = {}
var event_processor: EventProcessor
var event_collector: EventCollector
var _initialized := false

func _init():
	# 延迟初始化以避免循环依赖
	pass

func _ready() -> void:
	_ensure_initialized()

func _ensure_initialized() -> void:
	if event_processor == null:
		event_processor = EventProcessor.new()
	if event_collector == null:
		event_collector = EventCollector.new()

func init(config: EventProcessorConfig = null) -> void:
	if _initialized:
		Log.warning("GameWorld", "GameWorld already initialized, reinitializing...")
		shutdown()
	event_processor = EventProcessor.new(config)
	event_collector = EventCollector.new()
	initialize()

func destroy() -> void:
	if _initialized:
		shutdown()

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	Log.info("GameWorld", "GameWorld initialized")

func shutdown() -> void:
	_end_all_instances()
	_instances.clear()
	_initialized = false
	Log.info("GameWorld", "GameWorld shutdown")

func create_instance(factory: Callable) -> GameplayInstance:
	var instance: GameplayInstance = factory.call()
	if instance == null or instance.id == "":
		Log.warning("GameWorld", "Instance factory returned invalid instance")
		return instance
	if _instances.has(instance.id):
		Log.warning("GameWorld", "Instance already exists: %s" % instance.id)
		return _instances[instance.id]
	_instances[instance.id] = instance
	Log.debug("GameWorld", "Instance created: %s (%s)" % [instance.id, instance.type])
	return instance

func get_instance_by_id(id_value: String) -> GameplayInstance:
	return _instances.get(id_value, null)

func get_instances_by_type(type_value: String) -> Array[GameplayInstance]:
	var result: Array[GameplayInstance] = []
	for inst in _instances.values():
		if inst and _matches_instance_type(inst, type_value):
			result.append(inst)
	return result

func destroy_instance(id_value: String) -> bool:
	var instance: GameplayInstance = _instances.get(id_value)
	if instance == null:
		return false
	instance.end()
	_instances.erase(id_value)
	Log.debug("GameWorld", "Instance destroyed: %s" % id_value)
	return true

func destroy_all_instances() -> void:
	_end_all_instances()
	_instances.clear()
	Log.debug("GameWorld", "All instances destroyed")

func tick_all(dt: float) -> void:
	for instance in _instances.values():
		if _is_running_instance(instance):
			instance.tick(dt)

func get_instance_count() -> int:
	return _instances.size()

func has_running_instances() -> bool:
	for instance in _instances.values():
		if _is_running_instance(instance):
			return true
	return false

func get_debug_info() -> Dictionary:
	var instances_info := []
	for instance: GameplayInstance in _instances.values():
		instances_info.append({
			"id": instance.id,
			"type": instance.type,
			"state": instance.get_state(),
			"actorCount": instance.get_actor_count(),
		})
	return {
		"initialized": _initialized,
		"instanceCount": _instances.size(),
		"instances": instances_info,
	}

func _end_all_instances() -> void:
	for instance: GameplayInstance in _instances.values():
		if instance:
			instance.end()

func _is_running_instance(instance: GameplayInstance) -> bool:
	return instance != null and instance.is_running()

func _matches_instance_type(instance: GameplayInstance, type_value: String) -> bool:
	return instance.type == type_value


# ========== Actor 查询（统一入口） ==========

## 通过完整 Actor ID 获取 Actor
## Actor ID 格式: "{instance_id}:{local_id}"
## 如果 ID 格式无效或找不到，返回 null
func get_actor(actor_id: String) -> Actor:
	var parsed: Dictionary = ActorId.parse(actor_id)
	if parsed.instance_id.is_empty():
		return null
	var instance := get_instance_by_id(parsed.instance_id)
	if instance == null:
		return null
	return instance.get_actor(actor_id)
