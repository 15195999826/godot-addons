extends Node

class DummyInstance:
	extends GameplayInstance

	var end_calls := 0

	func _init(id_value: String = "", processor_config: EventProcessorConfig = null):
		super._init(id_value, processor_config)
		type = "dummy"

	func tick(dt: float) -> void:
		base_tick(dt)

	func on_end() -> void:
		end_calls += 1

class CountingSystem:
	extends System

	var ticks := 0

	func _init() -> void:
		super._init(System.SystemPriority.NORMAL)
		type = "counting"

	func tick(_actors: Array, _dt: float) -> void:
		ticks += 1

class DummyActor:
	extends Actor

	func _init() -> void:
		type = "dummy_actor"

class OrderProbeSystem:
	extends System

	func _init(type_value: String, priority_value: int) -> void:
		super._init(priority_value)
		type = type_value

func _init() -> void:
	TestFramework.register_test("GameWorld manages instances", _test_world_instances)
	TestFramework.register_test("GameWorld.shutdown ends every instance and is idempotent", _test_shutdown_idempotent)
	TestFramework.register_test("GameplayInstance owns its EventProcessor / EventCollector", _test_instance_owns_event_infrastructure)
	TestFramework.register_test("GameplayInstance runs systems and actors", _test_instance_lifecycle)
	TestFramework.register_test("System order: same priority keeps registration order", _test_system_order_same_priority)
	TestFramework.register_test("System order: mid-run insert does not disturb same-priority order", _test_system_order_mid_insert)
	TestFramework.register_test("System order: stable after remove", _test_system_order_after_remove)

func _test_world_instances() -> void:
	GameWorld.shutdown()
	var instance := DummyInstance.new("inst-1")
	TestFramework.assert_true(GameWorld.create_instance(instance) == instance, "create_instance 注册并原样返回")
	TestFramework.assert_equal(1, GameWorld.get_instance_count())
	TestFramework.assert_true(GameWorld.get_instance_by_id("inst-1") == instance)
	TestFramework.assert_true(GameWorld.has_running_instances() == false)
	GameWorld.destroy_all_instances()
	TestFramework.assert_equal(0, GameWorld.get_instance_count())
	GameWorld.shutdown()

## shutdown 结束全部 instance（不论是否 running）并清空注册表；已手动 end() 但仍在注册表里的
## instance 不会被再结束一次（场景常见的「world.end() 后 GameWorld.shutdown()」）；空表上再调同样安全。
func _test_shutdown_idempotent() -> void:
	GameWorld.shutdown()
	var ended := DummyInstance.new("inst-shutdown-ended")
	var created := DummyInstance.new("inst-shutdown-created")
	GameWorld.create_instance(ended)
	GameWorld.create_instance(created)
	ended.start()
	ended.end()
	GameWorld.shutdown()
	TestFramework.assert_equal(0, GameWorld.get_instance_count())
	TestFramework.assert_equal(1, ended.end_calls)
	TestFramework.assert_equal(1, created.end_calls)
	TestFramework.assert_equal("ended", created.get_state())
	GameWorld.shutdown()
	TestFramework.assert_equal(0, GameWorld.get_instance_count())
	TestFramework.assert_equal(1, created.end_calls)

## 事件设施归 instance：各自一套 processor / collector，配置随构造传入，互不共享。
func _test_instance_owns_event_infrastructure() -> void:
	var a := DummyInstance.new("inst-events-a", EventProcessorConfig.new(7))
	var b := DummyInstance.new("inst-events-b")
	TestFramework.assert_true(a.event_processor != null and a.event_collector != null)
	TestFramework.assert_true(a.event_processor != b.event_processor, "processor 不共享")
	TestFramework.assert_true(a.event_collector != b.event_collector, "collector 不共享")
	TestFramework.assert_equal(7, a.event_processor._config.max_depth)
	TestFramework.assert_equal(EventProcessorConfig.DEFAULT_MAX_DEPTH, b.event_processor._config.max_depth)
	a.event_collector.push({"kind": "only_a"})
	TestFramework.assert_equal(1, a.event_collector.get_count())
	TestFramework.assert_equal(0, b.event_collector.get_count())

func _test_instance_lifecycle() -> void:
	var instance := DummyInstance.new("inst-2")
	var system := CountingSystem.new()
	instance.add_system(system)
	var actor: DummyActor = instance.add_actor(DummyActor.new()) as DummyActor
	TestFramework.assert_true(actor != null)
	TestFramework.assert_equal(1, instance.get_actor_count())
	TestFramework.assert_equal("created", instance.get_state())
	instance.start()
	TestFramework.assert_true(instance.is_running())
	instance.tick(1.0)
	TestFramework.assert_equal(1, system.ticks)
	instance.end()
	TestFramework.assert_equal("ended", instance.get_state())

func _system_types(instance: GameplayInstance) -> Array[String]:
	var types: Array[String] = []
	for system in instance.get_systems():
		types.append(system.type)
	return types

func _test_system_order_same_priority() -> void:
	var instance := DummyInstance.new("inst-order-1")
	instance.add_system(OrderProbeSystem.new("a", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("b", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("c", System.SystemPriority.NORMAL))
	TestFramework.assert_equal(["a", "b", "c"], _system_types(instance))

func _test_system_order_mid_insert() -> void:
	var instance := DummyInstance.new("inst-order-2")
	instance.add_system(OrderProbeSystem.new("n1", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("n2", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("n3", System.SystemPriority.NORMAL))
	# 中途插高档：整表重排后仍不得扰动 NORMAL 档相对序
	instance.add_system(OrderProbeSystem.new("h1", System.SystemPriority.HIGH))
	TestFramework.assert_equal(["h1", "n1", "n2", "n3"], _system_types(instance))
	# 中途插同档：排同档末尾
	instance.add_system(OrderProbeSystem.new("n4", System.SystemPriority.NORMAL))
	TestFramework.assert_equal(["h1", "n1", "n2", "n3", "n4"], _system_types(instance))
	# 中途插低档：排最后
	instance.add_system(OrderProbeSystem.new("l1", System.SystemPriority.LOW))
	TestFramework.assert_equal(["h1", "n1", "n2", "n3", "n4", "l1"], _system_types(instance))
	# 再插高档：落 h1 之后、NORMAL 之前（同档注册序）
	instance.add_system(OrderProbeSystem.new("h2", System.SystemPriority.HIGH))
	TestFramework.assert_equal(["h1", "h2", "n1", "n2", "n3", "n4", "l1"], _system_types(instance))

func _test_system_order_after_remove() -> void:
	var instance := DummyInstance.new("inst-order-3")
	instance.add_system(OrderProbeSystem.new("a", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("b", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("c", System.SystemPriority.NORMAL))
	instance.add_system(OrderProbeSystem.new("d", System.SystemPriority.NORMAL))
	TestFramework.assert_true(instance.remove_system("b"))
	TestFramework.assert_equal(["a", "c", "d"], _system_types(instance))
	# remove 后再插入：seq 不复用，新系统仍排同档末尾
	instance.add_system(OrderProbeSystem.new("e", System.SystemPriority.NORMAL))
	TestFramework.assert_equal(["a", "c", "d", "e"], _system_types(instance))
