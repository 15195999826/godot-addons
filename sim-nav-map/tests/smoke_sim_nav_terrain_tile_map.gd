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
	_test_tile_projection_and_storage()
	_test_terrain_masks_derive_navcell_passability()
	_test_register_after_terrain_data_rebuilds_passability()


func _test_tile_projection_and_storage() -> void:
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

	nav_map.or_navcell_data(Vector2i(4, 2), 0x1)
	_assert_equal(0x20, nav_map.get_navcell_terrain_data(Vector2i(4, 2)), "navcell mask writes should not mutate terrain tile data")


func _test_terrain_masks_derive_navcell_passability() -> void:
	var nav_map := SimNavMap.new(10, 6, 8.0, Vector2.ZERO, 4)
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 0x20))
	var ship_mask := nav_map.register_passability_class(_class_config("ship", 0x40))

	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0x20)
	_assert_equal(ground_mask, nav_map.get_navcell_data(Vector2i(4, 2)) & ground_mask, "water terrain should block ground mask")
	_assert_equal(0, nav_map.get_navcell_data(Vector2i(4, 2)) & ship_mask, "water terrain should not block ship mask")
	_assert_equal(true, nav_map.is_dirty_navcell(Vector2i(4, 2)), "terrain edit should mark covered navcell dirty")
	_assert_equal(16, nav_map.collect_dirty_navcells().size(), "terrain tile edit should dirty affected navcells_per_tile square")
	_assert_equal(false, nav_map.is_passable_navcell(Vector2i(4, 2), ground_mask), "ground should not pass blocked terrain")
	_assert_equal(true, nav_map.is_passable_navcell(Vector2i(4, 2), ship_mask), "ship should pass terrain not in its mask")

	nav_map.clear_dirty_navcells()
	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0x20)
	_assert_equal(false, nav_map.has_dirty_navcells(), "same terrain value should not dirty navcells")

	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0)
	_assert_equal(0, nav_map.get_navcell_data(Vector2i(4, 2)) & ground_mask, "clearing terrain should clear derived ground block")
	_assert_equal(true, nav_map.is_dirty_navcell(Vector2i(4, 2)), "clearing terrain should mark changed navcell dirty")

	nav_map.clear_dirty_navcells()
	nav_map.or_navcell_data(Vector2i(4, 2), ship_mask)
	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0x20)
	_assert_equal(ship_mask, nav_map.get_navcell_data(Vector2i(4, 2)) & ship_mask, "manual navcell data should compose with terrain data")
	_assert_equal(0x20, nav_map.get_navcell_terrain_data(Vector2i(4, 2)), "manual navcell writes should not mutate terrain tile data")


func _test_register_after_terrain_data_rebuilds_passability() -> void:
	var nav_map := SimNavMap.new(8, 4, 8.0, Vector2.ZERO, 2)
	nav_map.set_terrain_tile_data(Vector2i(1, 0), 0x20)
	_assert_equal(false, nav_map.has_dirty_navcells(), "terrain with no passability classes should not dirty navcells")
	var ground_mask := nav_map.register_passability_class(_class_config("ground", 0x20))
	_assert_equal(false, nav_map.is_passable_navcell(Vector2i(2, 1), ground_mask), "registering class should derive existing terrain data")
	_assert_equal(true, nav_map.is_dirty_navcell(Vector2i(2, 1)), "registering terrain-aware class should dirty changed navcells")
	nav_map.clear_dirty_navcells()
	_assert_equal(0, nav_map.rebuild_terrain_passability(), "unchanged terrain rebuild should be stable")


func _class_config(name_id: String, terrain_mask: int) -> SimNavPassabilityClassConfig:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = name_id
	config.terrain_mask = terrain_mask
	config.affects_pathfinding = true
	return config


func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
