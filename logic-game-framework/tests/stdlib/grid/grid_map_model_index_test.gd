extends Node

## GridMapModel 两本反向索引（占用 / 预订）的合同（ultra-grid-map 的模型，LGF stdlib grid 依赖它答「X 在哪 / X 订了哪」）：
## 1. 预订：reserve_tile / cancel_reservation / cancel_reservations_by / get_reserved_coords / is_reserved 三表一致；
##    预订不进 tile.metadata；空 id / 缺格 / 被占 / 被别人订走都拒绝；move_occupant 到目标格退订
## 2. 占用：place / move / remove / remove_occupant_of / find_occupant_position 与 tile.occupant 一致；
##    String 与 Object 占用者各按自己的相等性，不做跨类型 ==
## 3. 一个占用者同时只站一格：已在棋盘上的再 place 拒绝并报错
## 4. set_tile 整块替换作废旧占用与预订、新数据自带的 occupant 进索引；initialize 归零三表

const LogCounter := preload("res://addons/logic-game-framework/tests/log_counter.gd")


func _init() -> void:
	TestFramework.register_test("GridModelIndex: reservations keep the tile table and the reserver index in step", _test_reservation_index)
	TestFramework.register_test("GridModelIndex: occupants keep the tile table and the occupant index in step", _test_occupant_index)
	TestFramework.register_test("GridModelIndex: an occupant stands on one tile only", _test_one_tile_per_occupant)
	TestFramework.register_test("GridModelIndex: set_tile and initialize reset what they replace", _test_set_tile_and_initialize_reset)


static func _make_model() -> GridMapModel:
	var config := GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.orientation = GridMapConfig.Orientation.FLAT
	config.draw_mode = GridMapConfig.DrawMode.RADIUS
	config.radius = 2
	var model := GridMapModel.new()
	model.initialize(config)
	return model


func _test_reservation_index() -> void:
	var model := _make_model()
	TestFramework.assert_true(model.reserve_tile(HexCoord.new(1, 0), "mover"), "reserve (1,0) for mover")
	TestFramework.assert_true(model.reserve_tile(HexCoord.new(0, 1), "mover"), "reserve (0,1) for mover")
	TestFramework.assert_true(model.reserve_tile(HexCoord.new(1, 0), "mover"), "re-reserving the same tile is idempotent")
	TestFramework.assert_true(model.reserve_tile(HexCoord.new(-1, 0), "other"), "reserve (-1,0) for other")
	TestFramework.assert_false(model.reserve_tile(HexCoord.new(1, 0), "other"), "a tile reserved by someone else is refused")
	TestFramework.assert_false(model.reserve_tile(HexCoord.new(0, 0), ""), "an empty reserver id is refused")
	TestFramework.assert_false(model.reserve_tile(HexCoord.new(9, 9), "mover"), "a missing tile is refused")
	TestFramework.assert_equal("mover", model.get_reservation(HexCoord.new(1, 0)))
	TestFramework.assert_true(model.is_reserved(HexCoord.new(0, 1)))
	TestFramework.assert_false(model.is_reserved(HexCoord.new(0, 0)))
	TestFramework.assert_equal(2, model.get_reserved_coords("mover").size())
	TestFramework.assert_false(model.has_tile_metadata(HexCoord.new(1, 0), "reservation"), "reservations do not live in tile.metadata")

	model.cancel_reservation(HexCoord.new(1, 0))
	TestFramework.assert_equal("", model.get_reservation(HexCoord.new(1, 0)))
	TestFramework.assert_equal(1, model.get_reserved_coords("mover").size())
	TestFramework.assert_equal(1, model.cancel_reservations_by("mover"))
	TestFramework.assert_equal("", model.get_reservation(HexCoord.new(0, 1)))
	TestFramework.assert_equal(0, model.get_reserved_coords("mover").size())
	TestFramework.assert_equal(0, model.cancel_reservations_by("mover"))
	TestFramework.assert_equal(0, model.cancel_reservations_by("nobody"))
	TestFramework.assert_equal("other", model.get_reservation(HexCoord.new(-1, 0)))

	# 占用消费预订：move_occupant 到目标格时退订，退订后 other 名下为空
	TestFramework.assert_true(model.place_occupant(HexCoord.new(0, 0), "walker"), "setup: place walker")
	TestFramework.assert_true(model.move_occupant(HexCoord.new(0, 0), HexCoord.new(-1, 0)), "walker moves onto other's reservation")
	TestFramework.assert_equal("", model.get_reservation(HexCoord.new(-1, 0)))
	TestFramework.assert_equal(0, model.cancel_reservations_by("other"))
	TestFramework.assert_false(model.reserve_tile(HexCoord.new(-1, 0), "other"), "an occupied tile cannot be reserved")


func _test_occupant_index() -> void:
	var model := _make_model()
	var actor := RefCounted.new()
	TestFramework.assert_true(model.find_occupant_position(actor) == null, "not on the board yet")
	TestFramework.assert_true(model.place_occupant(HexCoord.new(1, 0), actor), "place actor")
	TestFramework.assert_true(model.place_occupant(HexCoord.new(0, 1), "npc:1"), "place string occupant")
	TestFramework.assert_true((model.find_occupant_position(actor) as HexCoord).equals(HexCoord.new(1, 0)), "actor found by reference")
	TestFramework.assert_true((model.find_occupant_position("npc:1") as HexCoord).equals(HexCoord.new(0, 1)), "string occupant found by value")
	TestFramework.assert_true(model.find_occupant_position("npc:2") == null, "unknown string occupant")

	TestFramework.assert_true(model.move_occupant(HexCoord.new(1, 0), HexCoord.new(-1, 1)), "move actor")
	TestFramework.assert_true((model.find_occupant_position(actor) as HexCoord).equals(HexCoord.new(-1, 1)), "index follows the move")
	TestFramework.assert_true(model.remove_occupant_of(actor), "remove_occupant_of finds the actor without a coord")
	TestFramework.assert_true(model.get_occupant(HexCoord.new(-1, 1)) == null, "tile cleared")
	TestFramework.assert_true(model.find_occupant_position(actor) == null, "index cleared")
	TestFramework.assert_false(model.remove_occupant_of(actor), "second removal is a no-op")
	TestFramework.assert_false(model.remove_occupant_of(null), "null is a no-op")
	TestFramework.assert_true(model.remove_occupant(HexCoord.new(0, 1)), "remove string occupant by coord")
	TestFramework.assert_true(model.find_occupant_position("npc:1") == null, "index cleared for the string occupant too")


func _test_one_tile_per_occupant() -> void:
	var model := _make_model()
	var actor := RefCounted.new()
	TestFramework.assert_true(model.place_occupant(HexCoord.new(1, 0), actor), "place actor")
	var log_counter := LogCounter.new()
	OS.add_logger(log_counter)
	var placed_again := model.place_occupant(HexCoord.new(0, 1), actor)
	OS.remove_logger(log_counter)
	TestFramework.assert_false(placed_again, "an occupant already on the board is refused elsewhere")
	TestFramework.assert_equal(1, log_counter.errors)
	TestFramework.assert_true(model.get_occupant(HexCoord.new(0, 1)) == null, "the refused tile stays empty")
	TestFramework.assert_true((model.find_occupant_position(actor) as HexCoord).equals(HexCoord.new(1, 0)), "the actor still stands where it was")


func _test_set_tile_and_initialize_reset() -> void:
	var model := _make_model()
	var actor := RefCounted.new()
	TestFramework.assert_true(model.place_occupant(HexCoord.new(1, 0), actor), "place actor")
	TestFramework.assert_true(model.reserve_tile(HexCoord.new(0, 1), "mover"), "reserve for mover")

	model.set_tile(HexCoord.new(0, 1), GridMapModel.GridTileData.new(HexCoord.new(0, 1)))
	TestFramework.assert_equal("", model.get_reservation(HexCoord.new(0, 1)))
	TestFramework.assert_equal(0, model.cancel_reservations_by("mover"))
	var carrying := GridMapModel.GridTileData.new(HexCoord.new(1, 0))
	carrying.occupant = "npc:carried"
	model.set_tile(HexCoord.new(1, 0), carrying)
	TestFramework.assert_true(model.find_occupant_position(actor) == null, "the replaced tile drops the old occupant from the index")
	TestFramework.assert_true((model.find_occupant_position("npc:carried") as HexCoord).equals(HexCoord.new(1, 0)), "the new tile's occupant is indexed")
	TestFramework.assert_true(model.place_occupant(HexCoord.new(-1, 0), actor), "the dropped actor can be placed again")

	model.initialize(model.get_config())
	TestFramework.assert_true(model.find_occupant_position(actor) == null, "initialize clears the occupant index")
	TestFramework.assert_true(model.find_occupant_position("npc:carried") == null, "initialize clears string occupants too")
	TestFramework.assert_equal(0, model.cancel_reservations_by("mover"))
	TestFramework.assert_false(model.is_reserved(HexCoord.new(0, 1)))
