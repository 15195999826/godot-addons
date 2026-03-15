class_name IKFixedSlotSpace extends IKSpaceManager
## Fixed-slot container — each slot has a type tag, items must match.
## Used for: equipment slots, socket panel.

var _index_to_tag: Dictionary = {}   # { int: String }
var _tag_to_index: Dictionary = {}   # { String: int }
var _slot_flags: Dictionary = {}     # { int: int } (0=free, 1=occupied)
var _capacity: int = 0


func initialize(config: IKTypes.SpaceConfig) -> void:
	_index_to_tag.clear()
	_tag_to_index.clear()
	_slot_flags.clear()
	for i in range(config.fixed_slot_tags.size()):
		var tag: String = config.fixed_slot_tags[i]
		_index_to_tag[i] = tag
		_tag_to_index[tag] = i
		_slot_flags[i] = 0
	_capacity = config.fixed_slot_tags.size()


func can_add_item_to_slot(slot_index: int, _item_width: int = 1) -> bool:
	return is_valid_slot_index(slot_index) and is_slot_available(slot_index)


func is_slot_available(slot_index: int) -> bool:
	return _slot_flags.get(slot_index, 1) == 0


func is_valid_slot_index(slot_index: int) -> bool:
	return _index_to_tag.has(slot_index)


func get_recommended_slot_index(_item_width: int = 1) -> int:
	for i in range(_capacity):
		if _slot_flags.get(i, 1) == 0:
			return i
	return -1


func get_capacity() -> int:
	return _capacity


func update_slot_state(slot_index: int, flag: int) -> void:
	if is_valid_slot_index(slot_index):
		_slot_flags[slot_index] = flag


func get_slot_index_by_tag(tag: String) -> int:
	return _tag_to_index.get(tag, -1)


func get_slot_tag(slot_index: int) -> String:
	return _index_to_tag.get(slot_index, "")
