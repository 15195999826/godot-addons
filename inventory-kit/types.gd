class_name IKTypes
## Core data structures for InventoryKit.

## Space manager type.
enum SpaceType { UNORDERED, FIXED, GRID }

## Item location — (container_id, slot_index) pair.
class ItemLocation extends RefCounted:
	var container_id: int
	var slot_index: int  ## -1 = unordered (position irrelevant)

	func _init(p_container_id: int = -1, p_slot_index: int = -1) -> void:
		container_id = p_container_id
		slot_index = p_slot_index

	func duplicate_location() -> ItemLocation:
		return ItemLocation.new(container_id, slot_index)

	func equals(other: ItemLocation) -> bool:
		return container_id == other.container_id and slot_index == other.slot_index

	func _to_string() -> String:
		return "ItemLocation(container=%d, slot=%d)" % [container_id, slot_index]


## Base item instance — framework only tracks ID + location.
## Project layer extends this with game-specific fields.
class ItemInstance extends RefCounted:
	var item_id: int           ## Unique ID assigned by ItemSystem
	var location: ItemLocation ## Current position

	func _init(p_item_id: int = -1, p_location: ItemLocation = null) -> void:
		item_id = p_item_id
		location = p_location if p_location else ItemLocation.new()


## Configuration for creating a space manager.
class SpaceConfig extends RefCounted:
	var space_type: SpaceType = SpaceType.UNORDERED
	var capacity: int = -1               ## -1 = unlimited (unordered)
	var grid_width: int = 1              ## Grid only
	var grid_height: int = 1             ## Grid only
	var fixed_slot_tags: Array[String] = []  ## Fixed only

	static func unordered(p_capacity: int = -1) -> SpaceConfig:
		var cfg := SpaceConfig.new()
		cfg.space_type = SpaceType.UNORDERED
		cfg.capacity = p_capacity
		return cfg

	static func fixed(p_slot_tags: Array[String]) -> SpaceConfig:
		var cfg := SpaceConfig.new()
		cfg.space_type = SpaceType.FIXED
		cfg.fixed_slot_tags = p_slot_tags
		cfg.capacity = p_slot_tags.size()
		return cfg

	static func grid(p_width: int, p_height: int) -> SpaceConfig:
		var cfg := SpaceConfig.new()
		cfg.space_type = SpaceType.GRID
		cfg.grid_width = p_width
		cfg.grid_height = p_height
		cfg.capacity = p_width * p_height
		return cfg
