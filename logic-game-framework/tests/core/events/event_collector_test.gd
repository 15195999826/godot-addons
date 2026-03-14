extends Node

func _init() -> void:
	TestFramework.register_test("EventCollector collects and flushes", _test_collect)

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
