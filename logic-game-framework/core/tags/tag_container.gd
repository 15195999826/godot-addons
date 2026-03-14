## TagContainer - 标签容器
##
## 独立的 Tag 管理组件，可以被 AbilitySet 持有，也可以独立使用。
## 支持三种 Tag 来源：Loose Tags、Auto Duration Tags、Component Tags。
##
## [b]设计原则[/b]
## - 单一职责: 只管理 Tag，不关心 Ability
## - 可独立使用: 不需要 Ability 的场景也能用 Tag（如环境物体状态标记）
## - 三层 Tag 来源分离: 便于追踪和调试
##
## [b]三种 Tag 来源[/b]
## [codeblock]
## | 来源              | 特点                         | 典型用途           |
## |-------------------|------------------------------|-------------------|
## | Loose Tags        | 手动添加/移除，永不自动过期    | 冷却回合数、状态标记 |
## | Auto Duration Tags| 每层独立计时，tick 时自动清理  | 持续时间 Buff      |
## | Component Tags    | 随外部生命周期管理            | Ability 附加的 Tag |
## [/codeblock]
##
## [b]使用示例[/b]
## [codeblock]
## # 独立使用
## var tags := TagContainer.create("env_object_1")
## tags.add_loose_tag("interactive", 1)
## 
## # 检查 tag
## if tags.has_tag("interactive"):
##     print("可交互")
## 
## # 添加自动过期的 tag（3秒后过期）
## tags.add_auto_duration_tag("burning", 3.0)
## 
## # 监听 tag 变化
## var unsubscribe := tags.on_tag_changed(func(tag, old_count, new_count, container):
##     print("%s: %d -> %d" % [tag, old_count, new_count])
## )
## 
## # 取消监听
## unsubscribe.call()
## 
## # 被 AbilitySet 持有时，通过 ability_set.tag_container 访问
## var ability_set := actor.get_ability_set()
## ability_set.tag_container.add_loose_tag("stunned", 1)
## [/codeblock]
class_name TagContainer
extends RefCounted

var owner_id: String
var _loose_tags: Dictionary = {}
var _auto_duration_tags: Array[Dictionary] = []
var _component_tags: Dictionary = {}
var _current_logic_time: float = 0.0
var _callbacks: Array[Callable] = []

func _init(config: Dictionary) -> void:
	owner_id = str(config.get("owner_id", ""))


func add_loose_tag(tag: String, stacks: int = 1) -> void:
	Log.assert_crash(stacks > 0, "TagContainer", "add_loose_tag: stacks must be positive, got %d" % stacks)
	var old_count := get_tag_stacks(tag)
	var current := int(_loose_tags.get(tag, 0))
	_loose_tags[tag] = current + stacks
	var new_count := get_tag_stacks(tag)

	Log.debug("TagContainer", "添加 LooseTag: %s" % tag)

	if old_count != new_count:
		_notify_tag_changed(tag, old_count, new_count)


func remove_loose_tag(tag: String, stacks: int = -1) -> bool:
	if not _loose_tags.has(tag):
		return false
	var current := int(_loose_tags[tag])
	if current <= 0:
		return false

	var old_count := get_tag_stacks(tag)
	if stacks < 0 or stacks >= current:
		_loose_tags.erase(tag)
		Log.debug("TagContainer", "移除 LooseTag: %s" % tag)
	else:
		_loose_tags[tag] = current - stacks
		Log.debug("TagContainer", "减少 LooseTag 层数: %s" % tag)

	var new_count := get_tag_stacks(tag)
	if old_count != new_count:
		_notify_tag_changed(tag, old_count, new_count)

	return true


func has_loose_tag(tag: String) -> bool:
	return int(_loose_tags.get(tag, 0)) > 0


func get_loose_tag_stacks(tag: String) -> int:
	return int(_loose_tags.get(tag, 0))


func add_auto_duration_tag(tag: String, duration: float) -> void:
	var old_count := get_tag_stacks(tag)
	var expires_at := _current_logic_time + duration
	_auto_duration_tags.append({
		"tag": tag,
		"expiresAt": expires_at,
	})
	var new_count := get_tag_stacks(tag)

	Log.debug("TagContainer", "添加 AutoDurationTag: %s" % tag)

	if old_count != new_count:
		_notify_tag_changed(tag, old_count, new_count)


func get_auto_duration_tag_stacks(tag: String) -> int:
	var count := 0
	for entry in _auto_duration_tags:
		if entry["tag"] == tag and float(entry["expiresAt"]) > _current_logic_time:
			count += 1
	return count


func cleanup_expired_tags() -> void:
	var tag_old_counts := {}
	var removed_counts := {}
	for entry in _auto_duration_tags:
		if float(entry["expiresAt"]) <= _current_logic_time:
			var tag := str(entry["tag"])
			if not tag_old_counts.has(tag):
				tag_old_counts[tag] = get_tag_stacks(tag)
			removed_counts[tag] = int(removed_counts.get(tag, 0)) + 1

	var filtered: Array[Dictionary] = []
	for entry in _auto_duration_tags:
		if float(entry["expiresAt"]) > _current_logic_time:
			filtered.append(entry)
	_auto_duration_tags = filtered

	for tag in tag_old_counts.keys():
		var old_count := int(tag_old_counts[tag])
		var new_count := get_tag_stacks(tag)
		Log.debug("TagContainer", "AutoDurationTag 层过期: %s" % tag)
		if old_count != new_count:
			_notify_tag_changed(tag, old_count, new_count)


func add_component_tags(component_id: String, tags: Dictionary) -> void:
	if tags.is_empty():
		return

	var old_counts := {}
	for tag in tags.keys():
		old_counts[tag] = get_tag_stacks(str(tag))

	var existing := {}
	if _component_tags.has(component_id):
		existing = _component_tags[component_id]

	var merged := existing.duplicate()
	for tag in tags.keys():
		merged[tag] = int(merged.get(tag, 0)) + int(tags[tag])
	_component_tags[component_id] = merged

	var tag_list: Array[String] = []
	for tag in tags.keys():
		tag_list.append("%s:%s" % [str(tag), str(tags[tag])])
	Log.debug("TagContainer", "添加 ComponentTags: %s" % ", ".join(tag_list))

	for tag in old_counts.keys():
		var old_count := int(old_counts[tag])
		var new_count := get_tag_stacks(str(tag))
		if old_count != new_count:
			_notify_tag_changed(str(tag), old_count, new_count)


func remove_component_tags(component_id: String) -> void:
	if not _component_tags.has(component_id):
		return

	var tags: Dictionary = _component_tags[component_id]
	if tags.is_empty():
		_component_tags.erase(component_id)
		return

	var old_counts := {}
	for tag in tags.keys():
		old_counts[tag] = get_tag_stacks(str(tag))

	_component_tags.erase(component_id)

	var tag_list: Array[String] = []
	for tag in tags.keys():
		tag_list.append("%s:%s" % [str(tag), str(tags[tag])])
	Log.debug("TagContainer", "移除 ComponentTags: %s" % ", ".join(tag_list))

	for tag in old_counts.keys():
		var old_count := int(old_counts[tag])
		var new_count := get_tag_stacks(str(tag))
		if old_count != new_count:
			_notify_tag_changed(str(tag), old_count, new_count)


func has_tag(tag: String) -> bool:
	if _loose_tags.has(tag):
		return true

	for entry in _auto_duration_tags:
		if entry["tag"] == tag and float(entry["expiresAt"]) > _current_logic_time:
			return true

	for comp_tags in _component_tags.values():
		if comp_tags.has(tag) and int(comp_tags[tag]) > 0:
			return true

	return false


func get_tag_stacks(tag: String) -> int:
	var stacks := 0
	stacks += int(_loose_tags.get(tag, 0))
	for entry in _auto_duration_tags:
		if entry["tag"] == tag and float(entry["expiresAt"]) > _current_logic_time:
			stacks += 1
	for comp_tags in _component_tags.values():
		stacks += int(comp_tags.get(tag, 0))
	return stacks


func get_all_tags() -> Dictionary:
	var result := {}
	for tag in _loose_tags.keys():
		result[tag] = int(result.get(tag, 0)) + int(_loose_tags[tag])
	for entry in _auto_duration_tags:
		if float(entry["expiresAt"]) > _current_logic_time:
			var tag := str(entry["tag"])
			result[tag] = int(result.get(tag, 0)) + 1
	for comp_tags in _component_tags.values():
		for tag in comp_tags.keys():
			result[tag] = int(result.get(tag, 0)) + int(comp_tags[tag])
	return result


func get_logic_time() -> float:
	return _current_logic_time


func set_logic_time(logic_time: float) -> void:
	_current_logic_time = logic_time


func tick(dt: float, logic_time: float = -1.0) -> void:
	if logic_time >= 0.0:
		_current_logic_time = logic_time
	else:
		_current_logic_time += dt
	cleanup_expired_tags()


func on_tag_changed(callback: Callable) -> Callable:
	_callbacks.append(callback)
	return func() -> void:
		var index := _callbacks.find(callback)
		if index != -1:
			_callbacks.remove_at(index)


func _notify_tag_changed(tag: String, old_count: int, new_count: int) -> void:
	for callback in _callbacks:
		if callback.is_valid():
			callback.call(tag, old_count, new_count, self)
		else:
			Log.error("TagContainer", "Error in tag changed callback")


func get_snapshot() -> Dictionary:
	return get_all_tags().duplicate()


static func create(owner_id_value: String) -> TagContainer:
	return TagContainer.new({"owner_id": owner_id_value})
