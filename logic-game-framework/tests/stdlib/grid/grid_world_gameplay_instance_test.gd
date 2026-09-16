extends Node

## GridWorldGameplayInstance（stdlib 电池）合同：
## 1. configure_grid 建棋盘、configure_grid_model 采用现成棋盘，两者都只发一次 grid_configured
## 2. 录像快照的 map_config：未配图 {}，配图后 = 棋盘 to_config_dict()
## 3. clear_grid_footprint：只清 occupant 就是自己的格子（String occupant / 别人的占用不动、不报错）；
##    预订按 id 无条件扫全图（坐标无效、没有 hex_position 的 actor 也扫）；null 是 no-op；不动 registry、不动 hex_position
## 4. remove_actor 先清足迹再出 registry（actor_removed handler 里读到的棋盘已是清后状态）；未知 id 返回 false


## 站在棋盘上的最小 actor（有 hex_position 即满足 IGridOccupant）。
class GridProbeActor:
	extends BattleActor

	var hex_position: HexCoord = HexCoord.invalid()

	func _init() -> void:
		type = "grid_probe"


func _init() -> void:
	TestFramework.register_test("GridWorld: configure_grid / configure_grid_model set the board and emit grid_configured once each", _test_configure_grid)
	TestFramework.register_test("GridWorld: snapshot map_config follows the board", _test_map_config)
	TestFramework.register_test("GridWorld: clear_grid_footprint clears only the actor's own occupant and reservations", _test_clear_footprint)
	TestFramework.register_test("GridWorld: remove_actor releases the footprint before leaving the registry", _test_remove_actor)
	TestFramework.register_test("GridWorld: clear_grid_footprint scans reservations by id even without a valid position", _test_clear_footprint_scans_reservations_by_id)
	TestFramework.register_test("GridWorld: the board is already clear inside the actor_removed handler", _test_remove_actor_clears_board_before_signal)


static func _make_config() -> GridMapConfig:
	var config := GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.orientation = GridMapConfig.Orientation.FLAT
	config.draw_mode = GridMapConfig.DrawMode.RADIUS
	config.radius = 2
	return config


func _test_configure_grid() -> void:
	var world := GridWorldGameplayInstance.new("grid_world_t1")
	var configs: Array[GridMapConfig] = []
	world.grid_configured.connect(func(config: GridMapConfig) -> void:
		configs.append(config))
	TestFramework.assert_true(world.grid == null, "a fresh world has no board")

	var config := _make_config()
	world.configure_grid(config)
	TestFramework.assert_true(world.grid != null, "configure_grid should build the board")
	TestFramework.assert_true(world.grid.get_config() == config, "the board keeps the given config")
	TestFramework.assert_equal(1, configs.size())
	TestFramework.assert_true(configs[0] == config, "grid_configured carries the board's config")

	var model := GridMapModel.new()
	model.initialize(_make_config())
	world.configure_grid_model(model)
	TestFramework.assert_true(world.grid == model, "configure_grid_model adopts the given board")
	TestFramework.assert_equal(2, configs.size())
	TestFramework.assert_true(configs[1] == model.get_config(), "grid_configured carries the adopted board's config")


func _test_map_config() -> void:
	var world := GridWorldGameplayInstance.new("grid_world_t2")
	TestFramework.assert_true(world.capture_world_snapshot().map_config.is_empty(), "no board → empty map_config")
	world.configure_grid(_make_config())
	TestFramework.assert_true(world.capture_world_snapshot().map_config == world.grid.to_config_dict(),
		"the board's config dict goes into the snapshot")


func _test_clear_footprint() -> void:
	GameWorld.shutdown()
	var world := GameWorld.create_instance(GridWorldGameplayInstance.new("grid_world_t3")) as GridWorldGameplayInstance
	world.configure_grid(_make_config())
	var grid := world.grid
	var mover := world.add_actor(GridProbeActor.new()) as GridProbeActor
	var other := world.add_actor(GridProbeActor.new()) as GridProbeActor
	var overlay := world.add_actor(GridProbeActor.new()) as GridProbeActor
	var plain := world.add_actor(BattleActor.new())
	mover.hex_position = HexCoord.new(1, 0)
	TestFramework.assert_true(grid.place_occupant(mover.hex_position, mover), "setup: place mover")
	other.hex_position = HexCoord.new(0, 1)
	TestFramework.assert_true(grid.place_occupant(other.hex_position, other), "setup: place other")
	TestFramework.assert_true(grid.place_occupant(HexCoord.new(-1, 0), "npc:string_occupant"), "setup: place string occupant")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(2, 0), mover.get_id()), "setup: reserve for mover")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(0, 2), mover.get_id()), "setup: reserve for mover")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(-2, 0), other.get_id()), "setup: reserve for other")

	# 站在 String occupant 格上的 actor：不报错、不清别人的占用
	overlay.hex_position = HexCoord.new(-1, 0)
	world.clear_grid_footprint(overlay)
	TestFramework.assert_equal("npc:string_occupant", grid.get_occupant(HexCoord.new(-1, 0)))

	# 没有 hex_position 的 actor 与 null：no-op
	world.clear_grid_footprint(plain)
	world.clear_grid_footprint(null)
	TestFramework.assert_true(grid.get_occupant(HexCoord.new(1, 0)) == mover, "no-op calls leave the board alone")

	world.clear_grid_footprint(mover)
	TestFramework.assert_true(grid.get_occupant(HexCoord.new(1, 0)) == null, "own occupant cleared")
	TestFramework.assert_equal("", grid.get_reservation(HexCoord.new(2, 0)))
	TestFramework.assert_equal("", grid.get_reservation(HexCoord.new(0, 2)))
	TestFramework.assert_true(grid.get_occupant(HexCoord.new(0, 1)) == other, "other's occupant untouched")
	TestFramework.assert_equal(other.get_id(), grid.get_reservation(HexCoord.new(-2, 0)))
	TestFramework.assert_true(world.get_actor(mover.get_id()) == mover, "clear_grid_footprint does not touch the registry")
	TestFramework.assert_true(mover.hex_position.is_valid(), "clear_grid_footprint does not touch hex_position")

	# 站在别人格上（occupant 是别人）的 actor：别人的占用不动
	overlay.hex_position = HexCoord.new(0, 1)
	world.clear_grid_footprint(overlay)
	TestFramework.assert_true(grid.get_occupant(HexCoord.new(0, 1)) == other, "another actor's occupant untouched")
	GameWorld.destroy_instance(world.id)


func _test_remove_actor() -> void:
	GameWorld.shutdown()
	var world := GameWorld.create_instance(GridWorldGameplayInstance.new("grid_world_t4")) as GridWorldGameplayInstance
	world.configure_grid(_make_config())
	var grid := world.grid
	var actor := world.add_actor(GridProbeActor.new()) as GridProbeActor
	actor.hex_position = HexCoord.new(1, -1)
	TestFramework.assert_true(grid.place_occupant(actor.hex_position, actor), "setup: place actor")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(0, -1), actor.get_id()), "setup: reserve for actor")
	var removed_ids: Array[String] = []
	world.actor_removed.connect(func(actor_id: String) -> void:
		removed_ids.append(actor_id))

	TestFramework.assert_true(world.remove_actor(actor.get_id()), "remove_actor returns true for a registered actor")
	TestFramework.assert_true(world.get_actor(actor.get_id()) == null, "actor left the registry")
	TestFramework.assert_true(grid.get_occupant(HexCoord.new(1, -1)) == null, "actor left the board")
	TestFramework.assert_equal("", grid.get_reservation(HexCoord.new(0, -1)))
	TestFramework.assert_equal(1, removed_ids.size())
	TestFramework.assert_false(world.remove_actor("grid_world_t4:nobody"), "unknown id returns false")
	GameWorld.destroy_instance(world.id)


## D8：预订按 actor id 无条件扫全图——坐标无效的 IGridOccupant 与没有 hex_position 的 actor 也扫；
## 占用那一半只在坐标有效时看。
func _test_clear_footprint_scans_reservations_by_id() -> void:
	GameWorld.shutdown()
	var world := GameWorld.create_instance(GridWorldGameplayInstance.new("grid_world_t5")) as GridWorldGameplayInstance
	world.configure_grid(_make_config())
	var grid := world.grid
	var drifter := world.add_actor(GridProbeActor.new()) as GridProbeActor
	var plain := world.add_actor(BattleActor.new())
	TestFramework.assert_false(drifter.hex_position.is_valid(), "setup: the drifter has no valid position")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(1, 0), drifter.get_id()), "setup: reserve for drifter")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(-1, 1), drifter.get_id()), "setup: reserve for drifter")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(0, -1), plain.get_id()), "setup: reserve for plain")

	world.clear_grid_footprint(drifter)
	TestFramework.assert_equal("", grid.get_reservation(HexCoord.new(1, 0)))
	TestFramework.assert_equal("", grid.get_reservation(HexCoord.new(-1, 1)))
	TestFramework.assert_equal(plain.get_id(), grid.get_reservation(HexCoord.new(0, -1)))

	world.clear_grid_footprint(plain)
	TestFramework.assert_equal("", grid.get_reservation(HexCoord.new(0, -1)))
	GameWorld.destroy_instance(world.id)


## D8：remove_actor 先清足迹再出 registry——actor_removed 的 handler 读棋盘时占用与预订都已清掉，
## actor 也已不在 registry。
func _test_remove_actor_clears_board_before_signal() -> void:
	GameWorld.shutdown()
	var world := GameWorld.create_instance(GridWorldGameplayInstance.new("grid_world_t6")) as GridWorldGameplayInstance
	world.configure_grid(_make_config())
	var grid := world.grid
	var actor := world.add_actor(GridProbeActor.new()) as GridProbeActor
	actor.hex_position = HexCoord.new(0, 1)
	TestFramework.assert_true(grid.place_occupant(actor.hex_position, actor), "setup: place actor")
	TestFramework.assert_true(grid.reserve_tile(HexCoord.new(1, 1), actor.get_id()), "setup: reserve for actor")
	var seen := { "fired": false, "occupant_gone": false, "reservation": "unset", "still_registered": true }
	var on_removed := func(actor_id: String) -> void:
		seen["fired"] = true
		seen["occupant_gone"] = grid.get_occupant(HexCoord.new(0, 1)) == null
		seen["reservation"] = grid.get_reservation(HexCoord.new(1, 1))
		seen["still_registered"] = world.get_actor(actor_id) != null
	# 闭包捕获 world：ONE_SHOT 派发一次即断开，不留 world → signal → 闭包 → world 的环
	world.actor_removed.connect(on_removed, CONNECT_ONE_SHOT)

	TestFramework.assert_true(world.remove_actor(actor.get_id()), "remove_actor returns true")
	TestFramework.assert_true(seen["fired"], "actor_removed fired")
	TestFramework.assert_true(seen["occupant_gone"], "inside actor_removed the occupant is already cleared")
	TestFramework.assert_equal("", seen["reservation"])
	TestFramework.assert_false(seen["still_registered"], "inside actor_removed the actor has already left the registry")
	GameWorld.destroy_instance(world.id)
