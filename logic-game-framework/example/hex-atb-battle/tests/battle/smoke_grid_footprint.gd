## Smoke: grid 占用与 registry 对称 —— remove_actor 后该 actor 在棋盘上既无 occupant 也无 reservation，
## 同格别人的占用（overlay 形状：站在别人格上但 occupant 不是自己）与别人的预订一律不动；
## 未知 id 的 remove_actor 返回 false 且不碰棋盘。另钉录像快照的 map_config：配图后等于棋盘的
## to_config_dict()，未配图为 {}；hex 的 configure_grid 同时把棋盘灌进 UGridMap autoload。
##
## 全部是 HexWorldGameplayInstance 层的既有合同；grid 归属搬家（core → stdlib）不得改变其中任何一条。
extends Node


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	var status := _run()
	GameWorld.shutdown()
	if status == "":
		print("SMOKE_TEST_RESULT: PASS - grid footprint is released symmetrically with remove_actor")
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_RESULT: FAIL - %s" % status)
		get_tree().quit(1)


func _run() -> String:
	GameWorld.shutdown()

	var bare := GameWorld.create_instance(HexWorldGameplayInstance.new()) as HexWorldGameplayInstance
	if not bare.capture_world_snapshot().map_config.is_empty():
		return "unconfigured world must snapshot an empty map_config"
	GameWorld.destroy_instance(bare.id)

	var battle := HexWorldGameplayInstance.new()
	var configured: Array[GridMapConfig] = []
	battle.grid_configured.connect(func(config: GridMapConfig) -> void:
		configured.append(config))
	var grid_cfg := GridMapConfig.new()
	grid_cfg.grid_type = GridMapConfig.GridType.HEX
	grid_cfg.orientation = GridMapConfig.Orientation.FLAT
	grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	grid_cfg.radius = 3
	battle.configure_grid(grid_cfg)
	GameWorld.create_instance(battle)
	var grid := battle.grid
	if grid == null:
		return "configure_grid must populate the world's grid"
	if configured.size() != 1 or configured[0] != grid_cfg:
		return "configure_grid must emit grid_configured exactly once with the given config"
	if UGridMap.model != grid:
		return "hex world's grid must be the UGridMap autoload model"
	if battle.capture_world_snapshot().map_config != grid.to_config_dict():
		return "world snapshot map_config must come from the configured grid"

	var mover := _spawn_character(battle, HexCoord.new(1, 0), 0)
	var bystander := _spawn_character(battle, HexCoord.new(-1, 0), 1)
	# overlay: 站在 bystander 的格子上, 但 occupant 仍是 bystander (火焰地形的形状)。
	var overlay := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(overlay)
	overlay.hex_position = HexCoord.new(-1, 0)

	if not grid.reserve_tile(HexCoord.new(2, 0), mover.get_id()) \
			or not grid.reserve_tile(HexCoord.new(1, 1), mover.get_id()):
		return "test setup: reservations for mover failed"
	if not grid.reserve_tile(HexCoord.new(-2, 0), bystander.get_id()):
		return "test setup: reservation for bystander failed"

	if not battle.remove_actor(mover.get_id()):
		return "remove_actor must return true for a registered actor"
	if battle.get_actor(mover.get_id()) != null:
		return "removed actor must leave the registry"
	if grid.get_occupant(HexCoord.new(1, 0)) != null:
		return "removed actor must leave its tile"
	for coord in grid.get_all_coords():
		if grid.get_reservation(coord) == mover.get_id():
			return "removed actor must not keep its reservation at (%d, %d)" % [coord.q, coord.r]
	if grid.get_occupant(HexCoord.new(-1, 0)) != bystander:
		return "bystander occupant must be untouched by another actor's removal"
	if grid.get_reservation(HexCoord.new(-2, 0)) != bystander.get_id():
		return "bystander reservation must be untouched by another actor's removal"

	if not battle.remove_actor(overlay.get_id()):
		return "remove_actor must return true for the overlay actor"
	if grid.get_occupant(HexCoord.new(-1, 0)) != bystander:
		return "removing an overlay actor must not clear the tile's real occupant"

	if battle.remove_actor("hex_world:nobody"):
		return "remove_actor must return false for an unknown id"
	if grid.get_occupant(HexCoord.new(-1, 0)) != bystander \
			or grid.get_reservation(HexCoord.new(-2, 0)) != bystander.get_id():
		return "unknown-id remove_actor must not touch the grid"
	return ""


func _spawn_character(battle: HexWorldGameplayInstance, coord: HexCoord, team_id: int) -> CharacterActor:
	var actor := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(actor)
	actor.set_team_id(team_id)
	var placed := battle.grid.place_occupant(coord, actor)
	Log.assert_crash(placed, "SmokeGridFootprint", "test setup: place_occupant failed at (%d, %d)" % [coord.q, coord.r])
	actor.hex_position = coord.duplicate()
	return actor
