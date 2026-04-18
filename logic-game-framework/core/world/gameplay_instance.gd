class_name GameplayInstance
extends RefCounted

var id: String
var type: String = "instance"
var _systems: Array[System] = []
var _actors: Array[Actor] = []
var _actor_id_2_actor_dic: Dictionary = {}
var _logic_time: float = 0.0
var _state: String = "created"

func _init(id_value: String = ""):
	id = id_value if id_value != "" else IdGenerator.generate("instance")

func get_logic_time() -> float:
	return _logic_time

func get_state() -> String:
	return _state

func is_running() -> bool:
	return _state == "running"

func get_actor_count() -> int:
	return _actors.size()

func tick(_dt: float) -> void:
	pass

func base_tick(dt: float) -> void:
	if not is_running():
		return
	_logic_time += dt
	for system in _systems:
		if system.get_enabled():
			system.tick(_actors, dt)

func start() -> void:
	if _state != "created":
		Log.warning("GameplayInstance", "Cannot start instance in state: %s" % _state)
		return
	_state = "running"
	on_start()

func pause() -> void:
	if _state == "running":
		_state = "paused"
		on_pause()

func resume() -> void:
	if _state == "paused":
		_state = "running"
		on_resume()

func end() -> void:
	if _state == "ended":
		return
	_state = "ended"
	on_end()
	for actor in _actors:
		actor.on_despawn()
	for system in _systems:
		system.on_unregister()
	_cleanup_pre_event_handlers()


## 清理所有 actor 注册在 EventProcessor 的 PreEvent handler。
##
## 不 revoke ability（保留 `_abilities` 数组以支持复活等语义），只清 handler
## 注册表中的 PreHandlerRegistration，防止跨战斗 handler 孤儿化累积。
##
## handler 的重新注册应在 actor 重新"激活"时由项目层负责（例如：新战斗开始、
## 复活动画播完等）。本框架不假设何时重新激活。
func _cleanup_pre_event_handlers() -> void:
	var processor := GameWorld.event_processor
	if processor == null:
		return
	for actor in _actors:
		processor.remove_handlers_by_owner_id(actor.get_id())

func on_start() -> void:
	pass

func on_pause() -> void:
	pass

func on_resume() -> void:
	pass

func on_end() -> void:
	pass

func add_actor(actor: Actor) -> Actor:
	if actor == null:
		return null
	Log.assert_crash(not actor.is_id_valid(), "GameplayInstance", "Actor already has an ID '%s'. Do not set ID before add_actor()." % actor.get_id())
	var local_id := IdGenerator.generate(actor.type)
	actor.set_id(ActorId.format(id, local_id))
	actor._instance_id = id
	actor._on_id_assigned()
	_actors.append(actor)
	_actor_id_2_actor_dic[actor.get_id()] = actor
	actor.on_spawn()
	return actor

func remove_actor(actor_id: String) -> bool:
	var actor: Actor = _actor_id_2_actor_dic.get(actor_id, null)
	if actor == null:
		return false
	actor.on_despawn()
	_actors.erase(actor)
	_actor_id_2_actor_dic.erase(actor_id)
	return true

func get_actor(actor_id: String) -> Actor:
	return _actor_id_2_actor_dic.get(actor_id, null)

func get_actors() -> Array[Actor]:
	return _actors

func get_actors_by_type(actor_type: String) -> Array[Actor]:
	var results: Array[Actor] = []
	for actor in _actors:
		if actor.type == actor_type:
			results.append(actor)
	return results

func find_actors(predicate: Callable) -> Array[Actor]:
	var results: Array[Actor] = []
	for actor in _actors:
		if predicate.call(actor):
			results.append(actor)
	return results

func add_system(system: System) -> void:
	for existing in _systems:
		if existing.type == system.type:
			Log.warning("GameplayInstance", "System already exists: %s" % system.type)
			return
	_systems.append(system)
	_systems.sort_custom(func(a: System, b: System) -> bool: return a.priority < b.priority)
	system.on_register(self)

func remove_system(system_type: String) -> bool:
	for i in range(_systems.size()):
		if _systems[i].type == system_type:
			var system := _systems[i]
			system.on_unregister()
			_systems.remove_at(i)
			return true
	return false

func get_system(system_type: String) -> System:
	for system in _systems:
		if system.type == system_type:
			return system
	return null

func get_systems() -> Array[System]:
	return _systems

func serialize_base() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor in _actors:
		actors.append(actor.serialize_base())
	return {
		"id": id,
		"type": type,
		"state": _state,
		"logicTime": _logic_time,
		"actors": actors,
	}
