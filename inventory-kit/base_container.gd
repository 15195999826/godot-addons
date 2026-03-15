class_name IKBaseContainer extends RefCounted
## Base container implementation with space manager integration.
## Project-layer containers extend this and add game-specific validation.

var _id: int = -1
var _item_ids: Array[int] = []
var _space_config: IKTypes.SpaceConfig
var _space_manager: IKSpaceManager

## Signals emitted when items change.
signal item_added(item: IKTypes.ItemInstance)
signal item_removed(item: IKTypes.ItemInstance)
signal item_moved(old_location: IKTypes.ItemLocation, item: IKTypes.ItemInstance)


func _init(config: IKTypes.SpaceConfig = null) -> void:
	if config:
		_space_config = config


## Called by ItemSystem when registering this container.
func init_container(container_id: int) -> void:
	_id = container_id
	if _space_config:
		_space_manager = _create_space_manager(_space_config)


func get_container_id() -> int:
	return _id


func get_all_items() -> Array[int]:
	return _item_ids


func get_item_count() -> int:
	return _item_ids.size()


func get_space_manager() -> IKSpaceManager:
	return _space_manager


## Override in subclass for game-specific validation.
func can_add_item(item: IKTypes.ItemInstance, slot_index: int) -> bool:
	if _space_manager == null:
		return false
	return _space_manager.can_add_item_to_slot(slot_index)


## Override in subclass for game-specific validation.
func can_move_item(_item: IKTypes.ItemInstance, slot_index: int) -> bool:
	if _space_manager == null:
		return false
	return _space_manager.is_slot_available(slot_index)


func on_item_added(item: IKTypes.ItemInstance) -> void:
	_item_ids.append(item.item_id)
	if _space_manager:
		_space_manager.update_slot_state(item.location.slot_index, 1)
	item_added.emit(item)


func on_item_moved(old_location: IKTypes.ItemLocation, item: IKTypes.ItemInstance) -> void:
	if _space_manager:
		_space_manager.update_slot_state(old_location.slot_index, 0)
		_space_manager.update_slot_state(item.location.slot_index, 1)
	item_moved.emit(old_location, item)


func on_item_removed(item: IKTypes.ItemInstance) -> void:
	_item_ids.erase(item.item_id)
	if _space_manager:
		_space_manager.update_slot_state(item.location.slot_index, 0)
	item_removed.emit(item)


func _create_space_manager(config: IKTypes.SpaceConfig) -> IKSpaceManager:
	var manager: IKSpaceManager
	match config.space_type:
		IKTypes.SpaceType.UNORDERED:
			manager = IKUnorderedSpace.new()
		IKTypes.SpaceType.FIXED:
			manager = IKFixedSlotSpace.new()
		IKTypes.SpaceType.GRID:
			manager = IKGridSpace.new()
		_:
			push_error("IKBaseContainer: unknown space type %d" % config.space_type)
			return null
	manager.initialize(config)
	return manager
