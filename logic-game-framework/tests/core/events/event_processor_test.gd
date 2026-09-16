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
	TestFramework.register_test("EventProcessor trace_level 0 keeps no trace; trace_level 1 records the chain", _test_trace_level_gate)

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
	# pre-a / post-a 捕获了 processor：自注销失效时它们留在表里成环，清表免得用例失败时再多出泄漏
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

## trace_level 0：不建 trace、派发中没有 current trace id，handler 照常执行；
## trace_level 1：pre / post 各留一条带 cancel 结果与起止时间的 trace，派发中的 current trace id 就是这条 trace 的 id。
func _test_trace_level_gate() -> void:
	var seen := { "silent_id": "unset", "traced_id": "unset" }

	var silent := EventProcessor.new(EventProcessorConfig.new(5, 0))
	silent.register_pre_handler(PreHandlerRegistration.new(
		"h-silent",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-silent",  # ability_id
		"config-silent",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			seen["silent_id"] = silent.get_current_trace_id()
			return EventPhase.cancel_intent("h-silent", "quiet")
	))
	var mutable := silent.process_pre_event({ "kind": "damage", "damage": 1.0 })
	silent.process_post_event({ "kind": "damage" })
	TestFramework.assert_true(mutable.cancelled, "handlers still run with tracing off")
	TestFramework.assert_equal("quiet", mutable.cancel_reason)
	TestFramework.assert_equal(0, silent.get_traces().size())
	TestFramework.assert_equal("", seen["silent_id"])
	TestFramework.assert_equal("", silent.get_current_trace_id())
	TestFramework.assert_equal(0, silent.get_current_depth())
	TestFramework.assert_equal("(No traces recorded)", silent.export_trace_log())
	# handler 捕获了 processor：清表断环
	silent.remove_all_handlers()

	var traced := EventProcessor.new(EventProcessorConfig.new(5, 1))
	traced.register_pre_handler(PreHandlerRegistration.new(
		"h-traced",  # id
		"damage",  # event_kind
		"actor-1",  # owner_id
		"ability-traced",  # ability_id
		"config-traced",  # config_id
		func(_mutable: MutableEvent, _context: HandlerContext) -> Intent:
			seen["traced_id"] = traced.get_current_trace_id()
			return EventPhase.cancel_intent("h-traced", "loud")
	))
	traced.process_pre_event({ "kind": "damage", "damage": 1.0 })
	traced.process_post_event({ "kind": "damage" })
	var traces := traced.get_traces()
	TestFramework.assert_equal(2, traces.size())
	var pre_trace: Dictionary = traces[0]
	TestFramework.assert_equal(EventPhase.PHASE_PRE, pre_trace["phase"])
	TestFramework.assert_equal(pre_trace["trace_id"], seen["traced_id"])
	TestFramework.assert_true(pre_trace["cancelled"], "level 1 records the cancel")
	TestFramework.assert_equal("loud", pre_trace["cancel_reason"])
	TestFramework.assert_equal("h-traced", pre_trace["cancelled_by"])
	TestFramework.assert_true(pre_trace.has("original_values") and pre_trace.has("end_time"), "level 1 records values and end time")
	var post_trace: Dictionary = traces[1]
	TestFramework.assert_equal(EventPhase.PHASE_POST, post_trace["phase"])
	TestFramework.assert_true(post_trace.has("end_time"), "post trace is finalized")
	TestFramework.assert_equal("", traced.get_current_trace_id())
	TestFramework.assert_equal(0, traced.get_current_depth())
	traced.remove_all_handlers()


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
