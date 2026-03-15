class_name IKItemSystem extends RefCounted
## Central item management system — all item operations go through here.
## Containers are notified via callbacks; they never modify items directly.

## Emitted after any item operation completes.
signal item_created(item_id: int, location: IKTypes.ItemLocation)
signal item_moved(item_id: int, from_location: IKTypes.ItemLocation, to_location: IKTypes.ItemLocation)
signal item_destroyed(item_id: int)

var _item_map: Dictionary = {}       # { int item_id: IKTypes.ItemInstance }
var _container_map: Dictionary = {}  # { int container_id: IKBaseContainer }
var _next_item_id: int = 1
var _next_container_id: int = 0
var _void_container: IKVoidContainer
var _void_container_id: int = -1


func _init() -> void:
	_void_container = IKVoidContainer.new()
	register_container(_void_container)
	_void_container_id = _void_container.get_container_id()


# ---- Container Management ----

## Register a container and assign it a unique ID.
func register_container(container: IKBaseContainer) -> int:
	var id := _next_container_id
	_next_container_id += 1
	container.init_container(id)
	_container_map[id] = container
	return id


## Unregister a container (items inside are NOT automatically moved).
func unregister_container(container_id: int) -> void:
	_container_map.erase(container_id)


func get_container(container_id: int) -> IKBaseContainer:
	return _container_map.get(container_id)


func get_void_container_id() -> int:
	return _void_container_id


# ---- Item Management ----

## Create a new item at the given location. Returns the assigned item_id, or -1 on failure.
func create_item(location: IKTypes.ItemLocation) -> int:
	var container: IKBaseContainer = _container_map.get(location.container_id)
	if container == null:
		push_error("IKItemSystem.create_item: container %d not found" % location.container_id)
		return -1

	var item_id := _next_item_id
	_next_item_id += 1

	var item := IKTypes.ItemInstance.new(item_id, location.duplicate_location())

	# Auto-assign slot if -1
	if item.location.slot_index < 0 and container.get_space_manager():
		item.location.slot_index = container.get_space_manager().get_recommended_slot_index()

	if not container.can_add_item(item, item.location.slot_index):
		push_warning("IKItemSystem.create_item: container %d rejected item" % location.container_id)
		return -1

	_item_map[item_id] = item
	container.on_item_added(item)
	item_created.emit(item_id, item.location)
	return item_id


## Move an item to a new location. Returns true on success.
func move_item(item_id: int, target_location: IKTypes.ItemLocation) -> bool:
	var item: IKTypes.ItemInstance = _item_map.get(item_id)
	if item == null:
		push_error("IKItemSystem.move_item: item %d not found" % item_id)
		return false

	var target_container: IKBaseContainer = _container_map.get(target_location.container_id)
	if target_container == null:
		push_error("IKItemSystem.move_item: target container %d not found" % target_location.container_id)
		return false

	var old_location := item.location.duplicate_location()
	var same_container := (old_location.container_id == target_location.container_id)

	if same_container:
		# Intra-container move
		if not target_container.can_move_item(item, target_location.slot_index):
			return false
		item.location = target_location.duplicate_location()
		target_container.on_item_moved(old_location, item)
	else:
		# Cross-container move
		if not target_container.can_add_item(item, target_location.slot_index):
			return false
		var old_container: IKBaseContainer = _container_map.get(old_location.container_id)
		item.location = target_location.duplicate_location()
		if old_container:
			var old_item := IKTypes.ItemInstance.new(item.item_id, old_location)
			old_container.on_item_removed(old_item)
		target_container.on_item_added(item)

	item_moved.emit(item_id, old_location, target_location)
	return true


## Destroy an item — removes from its container and the item map.
func destroy_item(item_id: int) -> bool:
	var item: IKTypes.ItemInstance = _item_map.get(item_id)
	if item == null:
		push_error("IKItemSystem.destroy_item: item %d not found" % item_id)
		return false

	var container: IKBaseContainer = _container_map.get(item.location.container_id)
	if container:
		container.on_item_removed(item)
	_item_map.erase(item_id)
	item_destroyed.emit(item_id)
	return true


## Get item instance by ID.
func get_item(item_id: int) -> IKTypes.ItemInstance:
	return _item_map.get(item_id)


## Get the container an item is currently in.
func get_item_container(item_id: int) -> IKBaseContainer:
	var item: IKTypes.ItemInstance = _item_map.get(item_id)
	if item == null:
		return null
	return _container_map.get(item.location.container_id)


## Get all item IDs in the system.
func get_all_item_ids() -> Array[int]:
	var ids: Array[int] = []
	for key: int in _item_map.keys():
		ids.append(key)
	return ids
