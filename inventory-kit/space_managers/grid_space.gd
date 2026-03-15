class_name IKGridSpace extends IKSpaceManager
## Grid container — 2D slot layout supporting multi-width items.
## Used for: The Bazaar board (10 horizontal slots, items occupy 1-3 slots).

var _grid_width: int = 1
var _grid_height: int = 1
var _slot_flags: Array[int] = []  ## 0=free, item_id=occupied


func initialize(config: IKTypes.SpaceConfig) -> void:
	_grid_width = maxi(config.grid_width, 1)
	_grid_height = maxi(config.grid_height, 1)
	_slot_flags.resize(_grid_width * _grid_height)
	_slot_flags.fill(0)


func can_add_item_to_slot(slot_index: int, item_width: int = 1) -> bool:
	return can_place_at(slot_index, item_width)


## Check if contiguous slots from slot_index are free for item_width.
func can_place_at(slot_index: int, item_width: int) -> bool:
	if not is_valid_slot_index(slot_index):
		return false
	# Ensure item fits within the same row
	var row := slot_index / _grid_width
	var col := slot_index % _grid_width
	if col + item_width > _grid_width:
		return false
	for i in range(item_width):
		var idx := slot_index + i
		if _slot_flags[idx] != 0:
			return false
	return true


func is_slot_available(slot_index: int) -> bool:
	if not is_valid_slot_index(slot_index):
		return false
	return _slot_flags[slot_index] == 0


func is_valid_slot_index(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _slot_flags.size()


## Find the first slot that can fit an item of given width.
func get_recommended_slot_index(item_width: int = 1) -> int:
	for row in range(_grid_height):
		for col in range(_grid_width - item_width + 1):
			var idx := row * _grid_width + col
			if can_place_at(idx, item_width):
				return idx
	return -1


func get_capacity() -> int:
	return _grid_width * _grid_height


func update_slot_state(slot_index: int, flag: int) -> void:
	if is_valid_slot_index(slot_index):
		_slot_flags[slot_index] = flag


## Mark contiguous slots as occupied by item_id.
func occupy(slot_index: int, item_width: int, item_id: int) -> void:
	for i in range(item_width):
		var idx := slot_index + i
		if is_valid_slot_index(idx):
			_slot_flags[idx] = item_id


## Free contiguous slots.
func vacate(slot_index: int, item_width: int) -> void:
	for i in range(item_width):
		var idx := slot_index + i
		if is_valid_slot_index(idx):
			_slot_flags[idx] = 0


## Coordinate conversion: (col, row) → linear index.
func coord_to_index(col: int, row: int) -> int:
	return row * _grid_width + col


## Linear index → (col, row).
func index_to_coord(index: int) -> Vector2i:
	return Vector2i(index % _grid_width, index / _grid_width)


func get_grid_width() -> int:
	return _grid_width


func get_grid_height() -> int:
	return _grid_height
