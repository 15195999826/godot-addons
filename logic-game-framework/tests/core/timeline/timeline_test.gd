extends Node

func _init() -> void:
	TestFramework.register_test("TimelineData validates timelines", _test_validate)
	TestFramework.register_test("TimelineData sorts tags by time", _test_sorted_tags)
	TestFramework.register_test("TimelineData sorts same-time tags by definition order", _test_sorted_tags_tie_break)

func _test_validate() -> void:
	var timeline := TimelineData.new("", 0.0, { "late": 2.0, "neg": -1.0 })
	var errors := timeline.validate()
	TestFramework.assert_true(errors.size() >= 2)

func _test_sorted_tags() -> void:
	var timeline := TimelineData.new("timeline-1", 1.0, { "end": 1.0, "start": 0.0, "mid": 0.5 })
	var tags := timeline.get_sorted_tags()
	TestFramework.assert_equal(3, tags.size())
	TestFramework.assert_equal("start", tags[0]["name"])
	TestFramework.assert_equal("mid", tags[1]["name"])
	TestFramework.assert_equal("end", tags[2]["name"])

func _test_sorted_tags_tie_break() -> void:
	# 同 time 按定义序（声明顺序），定义序特意非字母序
	var timeline := TimelineData.new("t-sorted", 1.0, { "b": 0.5, "a": 0.5, "c": 0.2 })
	var sorted_tags := timeline.get_sorted_tags()
	TestFramework.assert_equal(3, sorted_tags.size())
	TestFramework.assert_equal("c", sorted_tags[0]["name"])
	TestFramework.assert_equal("b", sorted_tags[1]["name"])
	TestFramework.assert_equal("a", sorted_tags[2]["name"])
