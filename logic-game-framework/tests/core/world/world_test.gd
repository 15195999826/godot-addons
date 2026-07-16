extends Node

class DummyInstance:
	extends GameplayInstance

	func _init(id_value: String = ""):
		super._init(id_value)
		type = "dummy"

	func tick(dt: float) -> void:
		base_tick(dt)

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
	TestFramework.register_test("GameplayInstance runs systems and actors", _test_instance_lifecycle)
	TestFramework.register_test("System order: same priority keeps registration order", _test_system_order_same_priority)
	TestFramework.register_test("System order: mid-run insert does not disturb same-priority order", _test_system_order_mid_insert)
	TestFramework.register_test("System order: stable after remove", _test_system_order_after_remove)

func _test_world_instances() -> void:
	GameWorld.init()
	var world := GameWorld
	var instance := world.create_instance(func():
		return DummyInstance.new("inst-1")
	)
	TestFramework.assert_true(instance != null)
	TestFramework.assert_equal(1, world.get_instance_count())
	TestFramework.assert_true(world.has_running_instances() == false)
	world.destroy_all_instances()
	TestFramework.assert_equal(0, world.get_instance_count())
	GameWorld.destroy()

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
