class_name IKUnorderedSpace extends IKSpaceManager
## Unordered container — items have no specific position, only capacity matters.
## Used for: backpacks, stash, temporary storage.

var _capacity: int = -1  ## -1 = unlimited
var _item_count: int = 0


func initialize(config: IKTypes.SpaceConfig) -> void:
	_capacity = config.capacity
	_item_count = 0


func can_add_item_to_slot(_slot_index: int, _item_width: int = 1) -> bool:
	return _capacity < 0 or _item_count < _capacity


func is_slot_available(_slot_index: int) -> bool:
	return _capacity < 0 or _item_count < _capacity


func is_valid_slot_index(_slot_index: int) -> bool:
	return true  # Any index is valid for unordered


func get_recommended_slot_index(_item_width: int = 1) -> int:
	if _capacity < 0 or _item_count < _capacity:
		return 0
	return -1


func get_capacity() -> int:
	return _capacity


func update_slot_state(_slot_index: int, flag: int) -> void:
	if flag > 0:
		_item_count += 1
	else:
		_item_count = maxi(_item_count - 1, 0)


func get_item_count() -> int:
	return _item_count
