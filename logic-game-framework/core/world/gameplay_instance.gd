class_name GameplayInstance
extends RefCounted

var id: String
var type: String = "instance"
var _systems: Array[System] = []
var _system_seq_counter: int = 0
var _actors: Array[Actor] = []
var _actor_id_2_actor_dic: Dictionary = {}
var _logic_time: float = 0.0
var _state: String = "created"
## 本 instance 的事件设施：pre / post handler 注册表、递归深度、trace 与本帧事件队列都是 instance 级状态，
## 随 instance 生灭，两个 instance 互不可见。强边只向下（instance → processor / collector），两者都不回指 instance。
var event_processor: EventProcessor
var event_collector: EventCollector

func _init(id_value: String = "", processor_config: EventProcessorConfig = null):
	id = id_value if id_value != "" else IdGenerator.generate("instance")
	event_processor = EventProcessor.new(processor_config)
	event_collector = EventCollector.new()

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
	_cleanup_event_handlers()


## 清空本 instance event_processor 上的 pre / post handler 注册表：结束的 instance 不再派发事件。
##
## 不 revoke ability、不跑 on_remove；ability 手上残留的注销闭包按 id 查表，查不到即无操作。
func _cleanup_event_handlers() -> void:
	event_processor.remove_all_handlers()

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
	# 先登记 post 派发里的先后，再让 actor 同步 id：之后任何 grant 注册的 handler 都排得上 registry 顺序
	event_processor.note_actor_added(actor.get_id())
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
	event_processor.note_actor_removed(actor_id)
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
	# (priority, 注册序) 双键 = 全序：sort_custom 不稳定，单键 priority 下
	# 同档相对序无合同，中途 add_system 会整表乱重排（ADR 0027）。
	system._registration_seq = _system_seq_counter
	_system_seq_counter += 1
	_systems.append(system)
	_systems.sort_custom(func(a: System, b: System) -> bool:
		if a.priority != b.priority:
			return a.priority < b.priority
		return a._registration_seq < b._registration_seq
	)
	system.on_register(self)
	_log_tick_order("add_system:%s" % system.type)

func remove_system(system_type: String) -> bool:
	for i in range(_systems.size()):
		if _systems[i].type == system_type:
			var system := _systems[i]
			system.on_unregister()
			_systems.remove_at(i)
			_log_tick_order("remove_system:%s" % system_type)
			return true
	return false

## debug 日志：系统表每次变更打一行完整 tick 顺序。不进事件流/录制/存档。
func _log_tick_order(action: String) -> void:
	var parts: Array[String] = []
	for system in _systems:
		parts.append("%s(%d)" % [system.type, system.priority])
	Log.info("GameplayInstance", "[%s] tick order: %s" % [action, " -> ".join(parts)])

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
