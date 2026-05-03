extends Node2D


const Catalog := preload("res://addons/logic-game-framework/example/rts-auto-battle/frontend/assets/rts_tiny_swords_catalog.gd")

const _VIEW_SIZE: Vector2 = Vector2(1280.0, 720.0)
const _GRASS_COLOR := Color(0.32, 0.66, 0.38, 1.0)
const _GRASS_DARK := Color(0.23, 0.52, 0.31, 1.0)
const _WATER_COLOR := Color(0.20, 0.67, 0.72, 1.0)
const _CLIFF_COLOR := Color(0.34, 0.47, 0.44, 1.0)
const _PATH_COLOR := Color(0.70, 0.59, 0.43, 1.0)


func _ready() -> void:
	name = "RtsTinySwordsShowcase"
	_build_scene()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _VIEW_SIZE), _GRASS_COLOR, true)
	draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(250.0, 360.0)), _WATER_COLOR, true)
	draw_rect(Rect2(Vector2(92.0, 60.0), Vector2(310.0, 46.0)), _PATH_COLOR, true)
	draw_rect(Rect2(Vector2(250.0, 85.0), Vector2(340.0, 42.0)), _CLIFF_COLOR, true)
	draw_rect(Rect2(Vector2(930.0, 160.0), Vector2(260.0, 210.0)), _GRASS_DARK, true)
	draw_rect(Rect2(Vector2(930.0, 350.0), Vector2(155.0, 42.0)), _CLIFF_COLOR, true)
	draw_rect(Rect2(Vector2(420.0, 600.0), Vector2(180.0, 120.0)), _WATER_COLOR, true)
	draw_rect(Rect2(Vector2(770.0, 640.0), Vector2(125.0, 80.0)), _WATER_COLOR, true)


func _build_scene() -> void:
	var terrain := Node2D.new()
	terrain.name = "TerrainProps"
	add_child(terrain)

	var buildings := Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)

	var resources := Node2D.new()
	resources.name = "Resources"
	add_child(resources)

	var units := Node2D.new()
	units.name = "Units"
	add_child(units)

	_add_static_sprite(buildings, "BlueCastle", Catalog.load_building_texture(Catalog.BUILDING_CASTLE, Catalog.TEAM_BLUE), Vector2(175.0, 175.0), 0.62)
	_add_static_sprite(buildings, "RedHouse", Catalog.load_building_texture(Catalog.BUILDING_HOUSE, Catalog.TEAM_RED), Vector2(1050.0, 250.0), 0.68)
	_add_static_sprite(buildings, "BlueTower", Catalog.load_building_texture(Catalog.BUILDING_TOWER, Catalog.TEAM_BLUE), Vector2(1120.0, 525.0), 0.60)

	_add_static_sprite(resources, "GoldMine", Catalog.load_resource_texture(Catalog.RESOURCE_GOLD_MINE), Vector2(315.0, 500.0), 0.70)
	_add_static_sprite(resources, "TreeResource", Catalog.load_resource_texture(Catalog.RESOURCE_TREE), Vector2(455.0, 360.0), 0.55)
	_add_static_sprite(resources, "GoldResource", Catalog.load_resource_texture(Catalog.RESOURCE_GOLD), Vector2(795.0, 470.0), 0.48)
	_add_static_sprite(resources, "WoodResource", Catalog.load_resource_texture(Catalog.RESOURCE_WOOD), Vector2(1015.0, 150.0), 0.45)

	_add_static_sprite(terrain, "Deco01", Catalog.load_decor_texture(Catalog.DECOR_01), Vector2(515.0, 250.0), 0.65)
	_add_static_sprite(terrain, "Deco02", Catalog.load_decor_texture(Catalog.DECOR_02), Vector2(940.0, 450.0), 0.65)
	_add_static_sprite(terrain, "Deco03", Catalog.load_decor_texture(Catalog.DECOR_03), Vector2(370.0, 410.0), 0.75)
	_add_static_sprite(terrain, "Deco04", Catalog.load_decor_texture(Catalog.DECOR_04), Vector2(1030.0, 385.0), 0.75)

	_add_unit(units, "BlueWorker", Catalog.KIND_WORKER, Catalog.TEAM_BLUE, "run", Vector2(610.0, 365.0), false)
	_add_unit(units, "RedMelee", Catalog.KIND_MELEE, Catalog.TEAM_RED, "idle", Vector2(665.0, 335.0), false)
	_add_unit(units, "BlueMeleeAttack", Catalog.KIND_MELEE, Catalog.TEAM_BLUE, "attack", Vector2(720.0, 355.0), false)
	_add_unit(units, "RedArcher", Catalog.KIND_RANGED, Catalog.TEAM_RED, "attack", Vector2(970.0, 110.0), true)
	_add_unit(units, "BlueArcher", Catalog.KIND_RANGED, Catalog.TEAM_BLUE, "idle", Vector2(235.0, 530.0), false)

	_add_static_sprite(units, "ArrowPreview", Catalog.load_effect_texture(Catalog.EFFECT_ARROW, Catalog.TEAM_BLUE), Vector2(785.0, 330.0), 1.0)
	_add_static_sprite(units, "ExplosionPreview", Catalog.load_effect_texture(Catalog.EFFECT_EXPLOSION), Vector2(600.0, 420.0), 0.65)
	_add_static_sprite(units, "FirePreview", Catalog.load_effect_texture(Catalog.EFFECT_FIRE), Vector2(1075.0, 335.0), 0.65)


func _add_unit(
	parent: Node,
	node_name: String,
	unit_kind: String,
	team_id: int,
	animation_name: String,
	pos: Vector2,
	flip_h: bool,
) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = Catalog.create_unit_sprite(unit_kind, team_id, animation_name)
	sprite.name = node_name
	sprite.position = pos
	sprite.scale = Vector2(0.62, 0.62)
	sprite.flip_h = flip_h
	parent.add_child(sprite)
	return sprite


func _add_static_sprite(
	parent: Node,
	node_name: String,
	texture: Texture2D,
	pos: Vector2,
	scale_value: float,
	frame_index: int = 0,
) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.position = pos
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.centered = true
	if frame_index > 0:
		var frame_size := Vector2(texture.get_height(), texture.get_height())
		sprite.region_enabled = true
		sprite.region_rect = Rect2(frame_index * frame_size.x, 0.0, frame_size.x, frame_size.y)
	parent.add_child(sprite)
	return sprite
