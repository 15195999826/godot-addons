extends Node

## GameWorld —— GameplayInstance 注册表（Autoload）。
##
## 只管 instance 的注册 / 查找 / 批量结束，以及按 actor id 反查 actor 与它所属的 instance。
## 事件设施（EventProcessor / EventCollector）归各 GameplayInstance 所有，不挂在这里。

var _instances: Dictionary = {}


## 结束并注销全部 instance，拿到干净的注册表。幂等，任何要干净注册表的时刻都可以调：场景 / 测试的开头与收尾、
## 重建世界（新游戏 / 读档）之前；已手动 end() 但仍在表里的 instance 不会被再结束一次。
func shutdown() -> void:
	_end_all_instances()
	_instances.clear()
	Log.info("GameWorld", "GameWorld shutdown")


## 注册 instance 并原样返回。start() / add_actor / grant 放到本调用之后——
## context 的 instance 按 owner id 从注册表反查，注册前一律为 null。
## 同一对象重复注册幂等（原样返回、不重复登记）；同 id 的另一个对象是合同违反：断言并返回 null、
## 不登记（否则调用方拿着没注册的新实例继续跑，context 反查到的却是旧实例，静默错位）。
func create_instance(instance: GameplayInstance) -> GameplayInstance:
	if instance == null or instance.id == "":
		Log.warning("GameWorld", "create_instance: instance is null or has no id")
		return instance
	var registered: GameplayInstance = _instances.get(instance.id, null)
	if registered == instance:
		return instance
	if registered != null:
		Log.assert_crash(false, "GameWorld",
			"create_instance: id '%s' 已被另一个 instance (%s) 占用，同 id 异对象不能并存；先 destroy_instance 再注册" % [instance.id, registered.type])
		return null
	_instances[instance.id] = instance
	Log.debug("GameWorld", "Instance registered: %s (%s)" % [instance.id, instance.type])
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
			"actor_count": instance.get_actor_count(),
		})
	return {
		"instance_count": _instances.size(),
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
	var instance := get_instance_of_actor(actor_id)
	if instance == null:
		return null
	return instance.get_actor(actor_id)


## 通过完整 Actor ID 反查它所属的 GameplayInstance
## 与 Actor.get_owner_gameplay_instance() 同一机制（id 自描述归属），但不需要先拿到 Actor。
## 如果 ID 格式无效或实例不存在，返回 null
func get_instance_of_actor(actor_id: String) -> GameplayInstance:
	return get_instance_by_id(ActorId.extract_instance_id(actor_id))
