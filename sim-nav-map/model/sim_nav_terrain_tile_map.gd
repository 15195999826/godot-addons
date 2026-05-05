class_name SimNavTerrainTileMap
extends RefCounted


var width: int = 0
var height: int = 0
var navcells_per_tile: int = 1

var _data: PackedInt32Array = PackedInt32Array()


func _init(navcell_width: int = 0, navcell_height: int = 0, p_navcells_per_tile: int = 1) -> void:
	navcells_per_tile = maxi(1, p_navcells_per_tile)
	width = _ceil_div(navcell_width, navcells_per_tile)
	height = _ceil_div(navcell_height, navcells_per_tile)
	_data.resize(width * height)


func navcell_to_tile(coord: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	var tile_x: int = coord.x / navcells_per_tile
	@warning_ignore("integer_division")
	var tile_y: int = coord.y / navcells_per_tile
	return Vector2i(tile_x, tile_y)


func tile_origin_navcell(tile: Vector2i) -> Vector2i:
	return tile * navcells_per_tile


func is_valid_tile(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


func get_tile_data(tile: Vector2i) -> int:
	if not is_valid_tile(tile):
		return 0
	return int(_data[_index(tile)])


func set_tile_data(tile: Vector2i, value: int) -> void:
	if not is_valid_tile(tile):
		return
	_data[_index(tile)] = value


func get_navcell_terrain_data(coord: Vector2i) -> int:
	return get_tile_data(navcell_to_tile(coord))


func _index(tile: Vector2i) -> int:
	return tile.y * width + tile.x


func _ceil_div(value: int, divisor: int) -> int:
	if value <= 0:
		return 0
	return (value + divisor - 1) / divisor
