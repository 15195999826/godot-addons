class_name IKSpaceManager extends RefCounted
## Abstract base for slot/space management strategies.
## Subclasses implement validation and tracking for different container layouts.

func initialize(_config: IKTypes.SpaceConfig) -> void:
	pass

## Whether an item can be placed at the given slot.
func can_add_item_to_slot(_slot_index: int, _item_width: int = 1) -> bool:
	return false

## Whether a slot is currently unoccupied.
func is_slot_available(_slot_index: int) -> bool:
	return false

## Whether the slot index is within valid range.
func is_valid_slot_index(_slot_index: int) -> bool:
	return false

## Suggest the best available slot. Returns -1 if full.
func get_recommended_slot_index(_item_width: int = 1) -> int:
	return -1

## Total slot capacity.
func get_capacity() -> int:
	return 0

## Mark slot as occupied (flag=1) or free (flag=0).
func update_slot_state(_slot_index: int, _flag: int) -> void:
	pass

## Mark multiple contiguous slots for multi-width items.
func occupy(_slot_index: int, _item_width: int, _item_id: int) -> void:
	pass

## Free multiple contiguous slots.
func vacate(_slot_index: int, _item_width: int) -> void:
	pass

## Get slot index by tag name (Fixed containers only). Returns -1 if not found.
func get_slot_index_by_tag(_tag: String) -> int:
	return -1
