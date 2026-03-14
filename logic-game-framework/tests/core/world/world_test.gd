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

func _init() -> void:
	TestFramework.register_test("GameWorld manages instances", _test_world_instances)
	TestFramework.register_test("GameplayInstance runs systems and actors", _test_instance_lifecycle)

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
