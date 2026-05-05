extends Node


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map terrain tile map")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(10, 6, 8.0, Vector2.ZERO, 4)
	var terrain := nav_map.get_terrain_tile_map()
	_assert_equal(3, terrain.width, "terrain tile width should ceil-divide navcell width")
	_assert_equal(2, terrain.height, "terrain tile height should ceil-divide navcell height")
	_assert_equal(Vector2i(0, 0), nav_map.navcell_to_terrain_tile(Vector2i(0, 0)), "first navcell should map to first terrain tile")
	_assert_equal(Vector2i(0, 0), nav_map.navcell_to_terrain_tile(Vector2i(3, 3)), "tile should cover navcells_per_tile square")
	_assert_equal(Vector2i(1, 0), nav_map.navcell_to_terrain_tile(Vector2i(4, 3)), "next navcell group should map to next terrain tile")
	_assert_equal(Vector2i(2, 1), nav_map.navcell_to_terrain_tile(Vector2i(9, 5)), "edge navcell should map to ceil-divided edge terrain tile")

	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0x20)
	_assert_equal(0x20, nav_map.get_terrain_tile_data(Vector2i(1, 0)), "terrain tile data should be stored independently")
	_assert_equal(0x20, nav_map.get_navcell_terrain_data(Vector2i(4, 2)), "navcell should read its terrain tile data")
	_assert_equal(0, nav_map.get_navcell_data(Vector2i(4, 2)), "terrain tile data should not mutate navcell passability data")

	nav_map.or_navcell_data(Vector2i(4, 2), 0x1)
	_assert_equal(0x20, nav_map.get_navcell_terrain_data(Vector2i(4, 2)), "navcell mask writes should not mutate terrain tile data")


func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
