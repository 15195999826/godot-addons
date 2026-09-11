extends Node

func _init() -> void:
	TestFramework.register_test("EventProcessor pre modifies event", _test_pre_modify)
	TestFramework.register_test("EventProcessor pre cancels event", _test_pre_cancel)
	TestFramework.register_test("EventProcessor pre handlers are isolated per instance", _test_pre_handlers_isolated_per_instance)
	TestFramework.register_test("EventProcessor post dispatches in owner order then registration order", _test_post_dispatch_order)
	TestFramework.register_test("EventProcessor owner order survives handler cleanup, not registry removal", _test_owner_order_lifecycle)
	TestFramework.register_test("EventProcessor unregister is idempotent; owner removal clears both tables", _test_handler_removal)
	TestFramework.register_test("EventProcessor dispatch iterates a snapshot of the handlers", _test_dispatch_iterates_snapshot)
	TestFramework.register_test("EventProcessor export_trace_log prints pre intents and post handlers", _test_export_trace_log)

func _test_pre_modify() -> void:
	var config := EventProcessorConfig.new(5, 2)
	var processor := EventProcessor.new(config)

	var registration := PreHandlerRegistration.new(
		"h1",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-1",  # ability_id
		"config-1",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.modify_intent("h1", [
				Modification.multiply("damage", 0.5),
			])
	)
	processor.register_pre_handler(registration)

	var mutable := processor.process_pre_event({ "kind": "damage", "damage": 100.0 })
	TestFramework.assert_near(50.0, float(mutable.get_current_value("damage")))
	TestFramework.assert_true(not mutable.cancelled)

func _test_pre_cancel() -> void:
	var config := EventProcessorConfig.new(5, 2)
	var processor := EventProcessor.new(config)

	var registration := PreHandlerRegistration.new(
		"h2",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-1",  # ability_id
		"config-1",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.cancel_intent("h2", "immune")
	)
	processor.register_pre_handler(registration)

	var mutable := processor.process_pre_event({ "kind": "damage", "damage": 100.0 })
	TestFramework.assert_true(mutable.cancelled)
	TestFramework.assert_equal("immune", mutable.cancel_reason)

## processor 归 instance：注册在 A 上的 pre handler，B 派发同 kind 事件时看不到。
func _test_pre_handlers_isolated_per_instance() -> void:
	var a := GameplayInstance.new("processor-isolation-a")
	var b := GameplayInstance.new("processor-isolation-b")
	a.event_processor.register_pre_handler(PreHandlerRegistration.new(
		"h-iso",  # id
		"damage",  # event_kind
		"actor-a",  # owner_id
		"ability-a",  # ability_id
		"config-a",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.cancel_intent("h-iso", "only_a")
	))

	TestFramework.assert_true(a.event_processor.process_pre_event({ "kind": "damage", "damage": 1.0 }).cancelled)
	TestFramework.assert_false(b.event_processor.process_pre_event({ "kind": "damage", "damage": 1.0 }).cancelled)

## 派发顺序 = owner 进 registry 的顺序 → 注册顺序，与谁先注册无关；没登记过的 owner 排在最后。
## handler 收到的 HandlerContext 带着本条注册的 owner id。
func _test_post_dispatch_order() -> void:
	var processor := EventProcessor.new(EventProcessorConfig.new(5))
	processor.note_actor_added("actor-a")
	processor.note_actor_added("actor-b")
	var dispatched: Array[String] = []
	for entry: Array in [["b1", "actor-b"], ["unlisted", "actor-x"], ["a1", "actor-a"], ["a2", "actor-a"]]:
		processor.register_post_handler(_labeled_post_registration(entry[0], entry[1], dispatched))

	processor.process_post_event({ "kind": "damage" })
	var expected: Array[String] = ["a1@actor-a", "a2@actor-a", "b1@actor-b", "unlisted@actor-x"]
	TestFramework.assert_equal(expected, dispatched)

## 按 owner 清 handler 不动它在 registry 里的先后——inkmon 换 AbilitySet 前按 owner 清表，随后重新 grant 的
## handler 仍按 registry 顺序派发；note_actor_removed 才注销序号，之后再注册的 handler 排到最后。
func _test_owner_order_lifecycle() -> void:
	var processor := EventProcessor.new(EventProcessorConfig.new(5))
	processor.note_actor_added("actor-a")
	processor.note_actor_added("actor-b")
	var dispatched: Array[String] = []
	processor.register_post_handler(_labeled_post_registration("b1", "actor-b", dispatched))
	processor.register_post_handler(_labeled_post_registration("a1", "actor-a", dispatched))

	processor.remove_handlers_by_owner_id("actor-a")
	processor.register_post_handler(_labeled_post_registration("a2", "actor-a", dispatched))
	processor.process_post_event({ "kind": "damage" })
	var after_cleanup: Array[String] = ["a2@actor-a", "b1@actor-b"]
	TestFramework.assert_equal(after_cleanup, dispatched)

	dispatched.clear()
	processor.note_actor_removed("actor-a")
	processor.register_post_handler(_labeled_post_registration("a3", "actor-a", dispatched))
	processor.process_post_event({ "kind": "damage" })
	var after_removal: Array[String] = ["b1@actor-b", "a3@actor-a"]
	TestFramework.assert_equal(after_removal, dispatched)

## 注销闭包按 id 注销、重复调用无害；按 owner 清理同时清 pre / post 两张表且只动该 owner；remove_all_handlers 清空两张表。
func _test_handler_removal() -> void:
	var processor := EventProcessor.new(EventProcessorConfig.new(5))
	var calls := { "actor-1": 0, "actor-2": 0 }
	var unregister := processor.register_post_handler(_counting_post_registration("h-once", "actor-1", calls))
	unregister.call()
	unregister.call()
	processor.process_post_event({ "kind": "damage" })
	TestFramework.assert_equal(0, calls["actor-1"])

	processor.register_pre_handler(PreHandlerRegistration.new(
		"h-pre",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-pre",  # ability_id
		"config-pre",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.cancel_intent("h-pre", "actor-1 pre")
	))
	processor.register_post_handler(_counting_post_registration("h-1", "actor-1", calls))
	processor.register_post_handler(_counting_post_registration("h-2", "actor-2", calls))
	processor.remove_handlers_by_owner_id("actor-1")
	TestFramework.assert_false(processor.process_pre_event({ "kind": "damage" }).cancelled)
	processor.process_post_event({ "kind": "damage" })
	TestFramework.assert_equal(0, calls["actor-1"])
	TestFramework.assert_equal(1, calls["actor-2"])

	processor.remove_all_handlers()
	processor.process_post_event({ "kind": "damage" })
	TestFramework.assert_equal(1, calls["actor-2"])

## 派发遍历注册表快照（pre / post 同一规则）：handler 在派发中注销自己，同 kind 的下一个 handler 照常执行；
## 派发中注册的 handler 从下一条事件起才收到。
func _test_dispatch_iterates_snapshot() -> void:
	var processor := EventProcessor.new(EventProcessorConfig.new(5))
	var dispatched: Array[String] = []
	var unregisters := {}
	unregisters["pre-a"] = processor.register_pre_handler(PreHandlerRegistration.new(
		"h-pre-a",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-pre-a",  # ability_id
		"config-pre-a",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			dispatched.append("pre-a")
			(unregisters["pre-a"] as Callable).call()
			processor.register_pre_handler(_labeled_pre_registration("pre-late", dispatched))
			return EventPhase.pass_intent()
	))
	processor.register_pre_handler(_labeled_pre_registration("pre-b", dispatched))
	unregisters["post-a"] = processor.register_post_handler(PostHandlerRegistration.new(
		"h-post-a",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-post-a",  # ability_id
		"config-post-a",  # config_id
		func(_event_dict: Dictionary, _context: HandlerContext) -> bool:
			dispatched.append("post-a")
			(unregisters["post-a"] as Callable).call()
			processor.register_post_handler(_labeled_post_registration("post-late", "actor-1", dispatched))
			return true
	))
	processor.register_post_handler(_labeled_post_registration("post-b", "actor-1", dispatched))

	processor.process_pre_event({ "kind": "damage" })
	processor.process_post_event({ "kind": "damage" })
	var first_event: Array[String] = ["pre-a", "pre-b", "post-a", "post-b@actor-1"]
	TestFramework.assert_equal(first_event, dispatched)

	dispatched.clear()
	processor.process_pre_event({ "kind": "damage" })
	processor.process_post_event({ "kind": "damage" })
	var second_event: Array[String] = ["pre-b", "pre-late", "post-b@actor-1", "post-late@actor-1"]
	TestFramework.assert_equal(second_event, dispatched)
	# 两个 handler 捕获了 processor：清表断开 processor → 注册 → handler → processor 的环
	processor.remove_all_handlers()

## trace_level 2 时 export_trace_log 打出每个 pre handler 的意图与每个 post handler 是否触发。
func _test_export_trace_log() -> void:
	var processor := EventProcessor.new(EventProcessorConfig.new(5, 2))
	var dispatched: Array[String] = []
	processor.register_pre_handler(PreHandlerRegistration.new(
		"h-trace-pre",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-trace-pre",  # ability_id
		"config-trace-pre",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			return EventPhase.cancel_intent("h-trace-pre", "traced")
	))
	processor.register_post_handler(_labeled_post_registration("trace-post", "actor-1", dispatched))
	processor.process_pre_event({ "kind": "damage" })
	processor.process_post_event({ "kind": "damage" })

	var trace_log := processor.export_trace_log()
	TestFramework.assert_true(trace_log.contains("[config-trace-pre] -> cancel"), trace_log)
	TestFramework.assert_true(trace_log.contains("[config-trace-post] -> triggered"), trace_log)


## 触发时往 dispatched 记 label、放行的 pre 注册。
static func _labeled_pre_registration(label: String, dispatched: Array[String]) -> PreHandlerRegistration:
	return PreHandlerRegistration.new(
		"h-" + label,  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-" + label,  # ability_id
		"config-" + label,  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			dispatched.append(label)
			return EventPhase.pass_intent()
	)


## 触发时往 dispatched 记 "<label>@<HandlerContext.owner_id>" 的 post 注册。
static func _labeled_post_registration(label: String, owner_id: String, dispatched: Array[String]) -> PostHandlerRegistration:
	return PostHandlerRegistration.new(
		"h-" + label,  # id
		"damage",  # event_kind
		owner_id,  # owner_id
		"ability-" + label,  # ability_id
		"config-" + label,  # config_id
		func(_event_dict: Dictionary, context: HandlerContext) -> bool:
			dispatched.append("%s@%s" % [label, context.owner_id])
			return true
	)


static func _counting_post_registration(registration_id: String, owner_id: String, calls: Dictionary) -> PostHandlerRegistration:
	return PostHandlerRegistration.new(
		registration_id,  # id
		"damage",  # event_kind
		owner_id,  # owner_id
		"ability-" + registration_id,  # ability_id
		"config-" + registration_id,  # config_id
		func(_event_dict: Dictionary, _context: HandlerContext) -> bool:
			calls[owner_id] += 1
			return true
	)
