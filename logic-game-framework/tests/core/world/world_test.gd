extends Node

const LogCounter := preload("res://addons/logic-game-framework/tests/log_counter.gd")

const MID_TICK_KIND := "world_test_mid_tick"

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

## 每次 tick 把自己的 type 记进共享日志，再跑一段可选的 on_tick(instance)——测试用它在一趟 base_tick 中途改系统表。
class TickLogSystem:
	extends System

	var _tick_log: Array[String]
	var _on_tick: Callable

	func _init(type_value: String, priority_value: int, tick_log: Array[String], on_tick: Callable = Callable()) -> void:
		super._init(priority_value)
		type = type_value
		_tick_log = tick_log
		_on_tick = on_tick

	func tick(_actors: Array[Actor], _dt: float) -> void:
		_tick_log.append(type)
		if _on_tick.is_valid():
			_on_tick.call(get_instance())

func _init() -> void:
	TestFramework.register_test("GameWorld manages instances", _test_world_instances)
	TestFramework.register_test("GameWorld.shutdown ends every instance and is idempotent", _test_shutdown_idempotent)
	TestFramework.register_test("GameWorld.create_instance is idempotent for the same instance", _test_create_instance_same_object_idempotent)
	TestFramework.register_test("GameWorld.create_instance asserts on an id clash and keeps the registered instance", _test_create_instance_id_clash_asserts)
	TestFramework.register_test("GameplayInstance owns its EventProcessor / EventCollector", _test_instance_owns_event_infrastructure)
	TestFramework.register_test("GameplayInstance runs systems and actors", _test_instance_lifecycle)
	TestFramework.register_test("System order: same priority keeps registration order", _test_system_order_same_priority)
	TestFramework.register_test("System order: mid-run insert does not disturb same-priority order", _test_system_order_mid_insert)
	TestFramework.register_test("System order: stable after remove", _test_system_order_after_remove)
	TestFramework.register_test("GameplayInstance.base_tick walks a snapshot: add_system from a post handler mid-trip neither re-ticks nor skips", _test_base_tick_add_system_in_post_handler)
	TestFramework.register_test("GameplayInstance.base_tick walks a snapshot: a system removed mid-trip is not ticked, the ones after it still are", _test_base_tick_remove_system_mid_trip)

func _test_world_instances() -> void:
	GameWorld.shutdown()
	var instance := DummyInstance.new("inst-1")
	TestFramework.assert_true(GameWorld.create_instance(instance) == instance, "create_instance 注册并原样返回")
	TestFramework.assert_equal(1, GameWorld.get_instance_count())
	TestFramework.assert_true(GameWorld.get_instance_by_id("inst-1") == instance)
	TestFramework.assert_true(GameWorld.has_running_instances() == false)
	GameWorld.shutdown()
	TestFramework.assert_equal(0, GameWorld.get_instance_count())
	GameWorld.shutdown()

## shutdown 结束全部 instance（running 与未启动的都结束）并清空注册表；已手动 end() 但仍在注册表里的
## instance 不会被再结束一次（场景常见的「world.end() 后 GameWorld.shutdown()」）；空表上再调同样安全。
func _test_shutdown_idempotent() -> void:
	GameWorld.shutdown()
	var running := DummyInstance.new("inst-shutdown-running")
	var ended := DummyInstance.new("inst-shutdown-ended")
	var created := DummyInstance.new("inst-shutdown-created")
	GameWorld.create_instance(running)
	GameWorld.create_instance(ended)
	GameWorld.create_instance(created)
	running.start()
	ended.start()
	ended.end()
	GameWorld.shutdown()
	TestFramework.assert_equal(0, GameWorld.get_instance_count())
	for instance: DummyInstance in [running, ended, created]:
		TestFramework.assert_equal("ended", instance.get_state())
		TestFramework.assert_equal(1, instance.end_calls)
	GameWorld.shutdown()
	TestFramework.assert_equal(0, GameWorld.get_instance_count())

## 同一对象重复注册：原样返回、注册表不变、不报警告也不报错。
func _test_create_instance_same_object_idempotent() -> void:
	GameWorld.shutdown()
	var instance := DummyInstance.new("inst-idem")
	var log_counter := LogCounter.new("inst-idem")
	OS.add_logger(log_counter)
	var first := GameWorld.create_instance(instance)
	var second := GameWorld.create_instance(instance)
	OS.remove_logger(log_counter)
	TestFramework.assert_true(first == instance and second == instance, "both calls return the same instance")
	TestFramework.assert_equal(1, GameWorld.get_instance_count())
	TestFramework.assert_equal(0, log_counter.errors)
	TestFramework.assert_equal(0, log_counter.matched_warnings)
	GameWorld.shutdown()

## 同 id 异对象：恰一条断言、什么都不注册、返回 null，注册表里仍是先注册的那个。
func _test_create_instance_id_clash_asserts() -> void:
	GameWorld.shutdown()
	var first := DummyInstance.new("inst-clash")
	var impostor := DummyInstance.new("inst-clash")
	GameWorld.create_instance(first)
	var log_counter := LogCounter.new("create_instance")
	TestFramework.expect_script_errors(1)
	OS.add_logger(log_counter)
	var result := GameWorld.create_instance(impostor)
	OS.remove_logger(log_counter)
	TestFramework.assert_true(result == null, "an id clash registers nothing and returns null")
	TestFramework.assert_true(GameWorld.get_instance_by_id("inst-clash") == first, "the registered instance stays")
	TestFramework.assert_equal(1, GameWorld.get_instance_count())
	TestFramework.assert_equal(1, log_counter.matched_errors)
	TestFramework.assert_equal(1, log_counter.errors)
	GameWorld.shutdown()

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

## base_tick 的本趟名单 = 开趟时的系统表快照。system tick 里可以当场 process_post_event（stdlib ProjectileSystem 的形状），
## handler 里 add_system 会就地重排 _systems：活数组遍历下，排到当前位置之前的新系统把正在 tick 的那个顶到下一格、
## 让它本趟再 tick 一次，排到后面的新系统则当趟就被 tick。合同：已在表里的每个恰 tick 一次；中途加入的不论排到哪，
## 都从下一趟开始 tick。
func _test_base_tick_add_system_in_post_handler() -> void:
	var instance := DummyInstance.new("inst-mid-tick-add")
	var tick_log: Array[String] = []
	instance.add_system(TickLogSystem.new("dispatcher", System.SystemPriority.NORMAL, tick_log,
		func(ticking_instance: GameplayInstance) -> void:
			ticking_instance.event_processor.process_post_event({"kind": MID_TICK_KIND})))
	instance.add_system(TickLogSystem.new("tail", System.SystemPriority.NORMAL, tick_log))
	instance.event_processor.register_post_handler(PostHandlerRegistration.new(
		"world_test_mid_tick_add", MID_TICK_KIND, "", "", "",
		func(_event_dict: Dictionary, _handler_context: HandlerContext) -> bool:
			if instance.get_system("late_high") == null:
				instance.add_system(TickLogSystem.new("late_high", System.SystemPriority.HIGH, tick_log))
				instance.add_system(TickLogSystem.new("late_low", System.SystemPriority.LOW, tick_log))
			return true))
	instance.start()

	instance.tick(1.0)
	TestFramework.assert_equal(["dispatcher", "tail"], tick_log)
	TestFramework.assert_equal(["late_high", "dispatcher", "tail", "late_low"], _system_types(instance))

	tick_log.clear()
	instance.tick(1.0)
	TestFramework.assert_equal(["late_high", "dispatcher", "tail", "late_low"], tick_log)
	# handler 捕获了 instance（instance → processor → registration → handler → instance）；end() 清注册表拆环。
	instance.end()

## 同一份快照也管 remove_system：中途被移除的 system 已 on_unregister，本趟不再 tick；排在它后面的照常 tick
## （活数组遍历下，移除当前位置及之前的 system 会让数组左移、跳过下一个）。
func _test_base_tick_remove_system_mid_trip() -> void:
	var instance := DummyInstance.new("inst-mid-tick-remove")
	var tick_log: Array[String] = []
	instance.add_system(TickLogSystem.new("first", System.SystemPriority.NORMAL, tick_log))
	instance.add_system(TickLogSystem.new("remover", System.SystemPriority.NORMAL, tick_log,
		func(ticking_instance: GameplayInstance) -> void:
			ticking_instance.remove_system("first")
			ticking_instance.remove_system("victim")))
	instance.add_system(TickLogSystem.new("victim", System.SystemPriority.NORMAL, tick_log))
	instance.add_system(TickLogSystem.new("tail", System.SystemPriority.NORMAL, tick_log))
	instance.start()

	instance.tick(1.0)
	TestFramework.assert_equal(["first", "remover", "tail"], tick_log)
	TestFramework.assert_equal(["remover", "tail"], _system_types(instance))
	instance.end()
