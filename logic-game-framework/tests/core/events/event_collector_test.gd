extends Node

func _init() -> void:
	TestFramework.register_test("EventCollector collects and flushes", _test_collect)
	TestFramework.register_test("EventCollector isolates recorded events from caller mutation",
		_test_push_isolation)

func _test_collect() -> void:
	var collector := EventCollector.new()
	collector.push({ "kind": "damage" })
	collector.push({ "kind": "heal" })

	TestFramework.assert_equal(2, collector.get_count())
	TestFramework.assert_true(collector.has_events())

	var filtered := collector.filter_by_kind("damage")
	TestFramework.assert_equal(1, filtered.size())

	var flushed := collector.flush()
	TestFramework.assert_equal(2, flushed.size())
	TestFramework.assert_equal(0, collector.get_count())


func _test_push_isolation() -> void:
	var collector := EventCollector.new()
	var event_dict := {
		"kind": "damage",
		"payload": {"value": 12},
	}
	var returned := collector.push(event_dict)
	(returned.get("payload", {}) as Dictionary)["value"] = 99
	var flushed := collector.flush()
	var recorded := flushed[0] as Dictionary
	TestFramework.assert_equal(
		12,
		(recorded.get("payload", {}) as Dictionary).get("value", 0))
