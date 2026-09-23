extends Node

## TagContainer 计时层的查询 / 移除公开 API
##
## 钉住合同：
## - get_auto_duration_remaining：多层取最晚到期那层的剩余；没活层 0.0；随时钟递减；到期归零；
##   同名 loose / component 层没有时间，不参与
## - remove_auto_duration_tag：只清该 tag 活着的计时层（别的 tag、同名 loose / component 层不动）；
##   返回清掉的层数；层数变了广播一次 TagChanged；tag 不存在返回 0 不广播；
##   已到期但还没被 tick 清理的层不删、不计、不广播——到期广播归下一趟 cleanup_expired_tags 发


func _init() -> void:
	TestFramework.register_test("TagContainer.get_auto_duration_remaining 多层取最晚到期、随时钟递减、到期归零", _test_remaining_tracks_clock)
	TestFramework.register_test("TagContainer.get_auto_duration_remaining 同名 loose / component 层没有时间", _test_remaining_ignores_other_sources)
	TestFramework.register_test("TagContainer.remove_auto_duration_tag 清光该 tag 的计时层并广播一次", _test_remove_clears_and_notifies)
	TestFramework.register_test("TagContainer.remove_auto_duration_tag 别的 tag 与同名 loose / component 层不动", _test_remove_leaves_others)
	TestFramework.register_test("TagContainer.remove_auto_duration_tag tag 不存在返回 0 不广播", _test_remove_absent)
	TestFramework.register_test("TagContainer.remove_auto_duration_tag 已到期未清理的层不删不计不广播，到期广播留给下一趟 cleanup", _test_remove_expired_uncleaned)


## 把 TagChanged 广播记成 "tag:old>new" 串，便于一次断言顺序与次数。
static func _record_changes(tags: TagContainer) -> Array[String]:
	var changes: Array[String] = []
	tags.on_tag_changed(func(tag: String, old_count: int, new_count: int, _container: TagContainer) -> void:
		changes.append("%s:%d>%d" % [tag, old_count, new_count]))
	return changes


func _test_remaining_tracks_clock() -> void:
	var tags := TagContainer.create("remaining_clock")
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 0.0, 0.0001, "没有计时层返回 0")
	tags.set_logic_time(10.0)
	tags.add_auto_duration_tag("cooldown", 3.0)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 3.0)
	tags.add_auto_duration_tag("cooldown", 5.0)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 5.0, 0.0001, "多层取最晚到期那层")
	# 只拨钟不清理：剩余纯按时钟算
	tags.set_logic_time(12.0)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 3.0, 0.0001, "拨钟 2 秒后剩 3")
	tags.set_logic_time(14.0)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 1.0, 0.0001, "3 秒那层已到期，只剩 5 秒那层的 1")
	tags.set_logic_time(15.0)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 0.0, 0.0001, "全到期归零（层还没被清理也是 0）")
	# tick 清理之后照样 0
	tags.tick(0.0, 15.0)
	TestFramework.assert_false(tags.has_tag("cooldown"))
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 0.0, 0.0001, "清理后仍是 0")


func _test_remaining_ignores_other_sources() -> void:
	var tags := TagContainer.create("remaining_sources")
	tags.add_loose_tag("cooldown", 2)
	tags.add_component_tags("comp", {"cooldown": 1})
	TestFramework.assert_equal(3, tags.get_tag_stacks("cooldown"))
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 0.0, 0.0001, "loose / component 层没有时间")
	tags.add_auto_duration_tag("cooldown", 2.5)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 2.5)


func _test_remove_clears_and_notifies() -> void:
	var tags := TagContainer.create("remove_notify")
	tags.add_auto_duration_tag("cooldown", 3.0)
	tags.add_auto_duration_tag("cooldown", 5.0)
	var changes := _record_changes(tags)
	TestFramework.assert_equal(2, tags.remove_auto_duration_tag("cooldown"))
	TestFramework.assert_false(tags.has_tag("cooldown"))
	TestFramework.assert_equal(0, tags.get_auto_duration_tag_stacks("cooldown"))
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 0.0)
	TestFramework.assert_equal("cooldown:2>0", ",".join(changes))
	# 清过之后再加照常计时、照常广播
	tags.add_auto_duration_tag("cooldown", 1.0)
	TestFramework.assert_near(tags.get_auto_duration_remaining("cooldown"), 1.0)
	TestFramework.assert_equal("cooldown:2>0,cooldown:0>1", ",".join(changes))


func _test_remove_leaves_others() -> void:
	var tags := TagContainer.create("remove_others")
	tags.add_auto_duration_tag("cooldown", 3.0)
	tags.add_auto_duration_tag("burning", 4.0)
	tags.add_loose_tag("cooldown", 1)
	tags.add_component_tags("comp", {"cooldown": 1})
	var changes := _record_changes(tags)
	TestFramework.assert_equal(1, tags.remove_auto_duration_tag("cooldown"))
	TestFramework.assert_equal(2, tags.get_tag_stacks("cooldown"))
	TestFramework.assert_equal(1, tags.get_loose_tag_stacks("cooldown"))
	TestFramework.assert_equal(0, tags.get_auto_duration_tag_stacks("cooldown"))
	TestFramework.assert_true(tags.has_tag("burning"), "别的计时 tag 不动")
	TestFramework.assert_near(tags.get_auto_duration_remaining("burning"), 4.0)
	TestFramework.assert_equal("cooldown:3>2", ",".join(changes))


func _test_remove_absent() -> void:
	var tags := TagContainer.create("remove_absent")
	tags.add_loose_tag("cooldown", 1)
	var changes := _record_changes(tags)
	TestFramework.assert_equal(0, tags.remove_auto_duration_tag("cooldown"))
	TestFramework.assert_equal(0, tags.remove_auto_duration_tag("never_added"))
	TestFramework.assert_equal(1, tags.get_tag_stacks("cooldown"))
	TestFramework.assert_equal("", ",".join(changes))


func _test_remove_expired_uncleaned() -> void:
	var tags := TagContainer.create("remove_expired")
	tags.add_auto_duration_tag("cooldown", 1.0)
	# 拨过到期点但不 tick：层还躺在列表里，对外已经不存在
	tags.set_logic_time(5.0)
	TestFramework.assert_false(tags.has_tag("cooldown"))
	var changes := _record_changes(tags)
	TestFramework.assert_equal(0, tags.remove_auto_duration_tag("cooldown"))
	TestFramework.assert_equal("", ",".join(changes))
	TestFramework.assert_false(tags.has_tag("cooldown"))
	# 到期广播归 cleanup：remove 没把已到期的层吞掉，下一趟 tick 照常发 1>0
	tags.tick(0.0, 5.0)
	TestFramework.assert_equal("cooldown:1>0", ",".join(changes))
