class_name TinySwordsCatalog


const TEAM_RED: int = 0
const TEAM_BLUE: int = 1

const KIND_WORKER: String = "worker"
const KIND_MELEE: String = "melee"
const KIND_RANGED: String = "ranged"

const BUILDING_CASTLE: String = "castle"
const BUILDING_HOUSE: String = "house"
const BUILDING_TOWER: String = "tower"

const RESOURCE_GOLD_MINE: String = "gold_mine"
const RESOURCE_TREE: String = "tree"
const RESOURCE_GOLD: String = "gold_resource"
const RESOURCE_WOOD: String = "wood_resource"

const DECOR_01: String = "deco_01"
const DECOR_02: String = "deco_02"
const DECOR_03: String = "deco_03"
const DECOR_04: String = "deco_04"

const EFFECT_ARROW: String = "arrow"
const EFFECT_EXPLOSION: String = "explosion"
const EFFECT_FIRE: String = "fire"

const _ROOT: String = "res://addons/logic-game-framework/example/assets/tiny_swords"
const _UNIT_FRAME_SIZE: Vector2i = Vector2i(192, 192)

const _UNIT_PATHS: Dictionary = {
	KIND_WORKER: {
		TEAM_RED: _ROOT + "/units/knights/pawn/Pawn_Red.png",
		TEAM_BLUE: _ROOT + "/units/knights/pawn/Pawn_Blue.png",
	},
	KIND_MELEE: {
		TEAM_RED: _ROOT + "/units/knights/warrior/Warrior_Red.png",
		TEAM_BLUE: _ROOT + "/units/knights/warrior/Warrior_Blue.png",
	},
	KIND_RANGED: {
		TEAM_RED: _ROOT + "/units/knights/archer/Archer_Red.png",
		TEAM_BLUE: _ROOT + "/units/knights/archer/Archer_Blue.png",
	},
}

const _UNIT_ANIMATIONS: Dictionary = {
	KIND_WORKER: {
		"idle": {"row": 0, "count": 6, "fps": 7.0, "loop": true},
		"run": {"row": 1, "count": 6, "fps": 10.0, "loop": true},
		"attack": {"row": 2, "count": 6, "fps": 10.0, "loop": false},
	},
	KIND_MELEE: {
		"idle": {"row": 0, "count": 6, "fps": 7.0, "loop": true},
		"run": {"row": 1, "count": 6, "fps": 10.0, "loop": true},
		"attack": {"row": 2, "count": 6, "fps": 10.0, "loop": false},
	},
	KIND_RANGED: {
		"idle": {"row": 0, "count": 6, "fps": 7.0, "loop": true},
		"run": {"row": 1, "count": 6, "fps": 10.0, "loop": true},
		"attack": {"row": 2, "count": 8, "fps": 10.0, "loop": false},
	},
}

const _BUILDING_PATHS: Dictionary = {
	BUILDING_CASTLE: {
		TEAM_RED: _ROOT + "/scene_objects/buildings/knights/castle/Castle_Red.png",
		TEAM_BLUE: _ROOT + "/scene_objects/buildings/knights/castle/Castle_Blue.png",
	},
	BUILDING_HOUSE: {
		TEAM_RED: _ROOT + "/scene_objects/buildings/knights/house/House_Red.png",
		TEAM_BLUE: _ROOT + "/scene_objects/buildings/knights/house/House_Blue.png",
	},
	BUILDING_TOWER: {
		TEAM_RED: _ROOT + "/scene_objects/buildings/knights/tower/Tower_Red.png",
		TEAM_BLUE: _ROOT + "/scene_objects/buildings/knights/tower/Tower_Blue.png",
	},
}

const _RESOURCE_PATHS: Dictionary = {
	RESOURCE_GOLD_MINE: _ROOT + "/scene_objects/resources/gold/mine/GoldMine_Active.png",
	RESOURCE_TREE: _ROOT + "/scene_objects/resources/wood/trees/Tree.png",
	RESOURCE_GOLD: _ROOT + "/scene_objects/resources/gold/pickup/Gold_Resource.png",
	RESOURCE_WOOD: _ROOT + "/scene_objects/resources/wood/pickup/Wood_Resource.png",
}

const _DECOR_PATHS: Dictionary = {
	DECOR_01: _ROOT + "/decor/grassland_set/01.png",
	DECOR_02: _ROOT + "/decor/grassland_set/02.png",
	DECOR_03: _ROOT + "/decor/grassland_set/03.png",
	DECOR_04: _ROOT + "/decor/grassland_set/04.png",
}

const _EFFECT_PATHS: Dictionary = {
	EFFECT_ARROW: _ROOT + "/effects/projectiles/arrow/Arrow.png",
	EFFECT_EXPLOSION: _ROOT + "/effects/combat/explosion/Explosions.png",
	EFFECT_FIRE: _ROOT + "/effects/environment/fire/Fire.png",
}


static func create_unit_sprite(unit_kind: String, team_id: int, default_animation: String = "idle") -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = create_unit_frames(unit_kind, team_id)
	sprite.animation = default_animation
	sprite.centered = true
	sprite.play()
	return sprite


static func create_unit_frames(unit_kind: String, team_id: int) -> SpriteFrames:
	Log.assert_crash(_UNIT_PATHS.has(unit_kind), "TinySwordsCatalog", "Unknown unit kind: %s" % unit_kind)
	var by_team: Dictionary = _UNIT_PATHS[unit_kind] as Dictionary
	Log.assert_crash(by_team.has(team_id), "TinySwordsCatalog", "Unknown team id: %d" % team_id)

	var frames := SpriteFrames.new()
	_remove_default_animation(frames)

	var sheet_path: String = by_team[team_id] as String
	var animations: Dictionary = _UNIT_ANIMATIONS[unit_kind] as Dictionary
	for animation_name in animations.keys():
		var anim_name := str(animation_name)
		var spec: Dictionary = animations[anim_name] as Dictionary
		var row: int = spec["row"] as int
		var count: int = spec["count"] as int
		var fps: float = spec["fps"] as float
		var should_loop: bool = spec["loop"] as bool
		_add_sheet_animation(frames, anim_name, sheet_path, _UNIT_FRAME_SIZE, row, count, fps, should_loop)
	return frames


static func load_building_texture(building_kind: String, team_id: int) -> Texture2D:
	Log.assert_crash(_BUILDING_PATHS.has(building_kind), "TinySwordsCatalog", "Unknown building kind: %s" % building_kind)
	var by_team: Dictionary = _BUILDING_PATHS[building_kind] as Dictionary
	Log.assert_crash(by_team.has(team_id), "TinySwordsCatalog", "Unknown team id: %d" % team_id)
	return _load_texture(by_team[team_id] as String)


static func load_resource_texture(resource_kind: String) -> Texture2D:
	Log.assert_crash(_RESOURCE_PATHS.has(resource_kind), "TinySwordsCatalog", "Unknown resource kind: %s" % resource_kind)
	return _load_texture(_RESOURCE_PATHS[resource_kind] as String)


static func load_decor_texture(decor_kind: String) -> Texture2D:
	Log.assert_crash(_DECOR_PATHS.has(decor_kind), "TinySwordsCatalog", "Unknown decor kind: %s" % decor_kind)
	return _load_texture(_DECOR_PATHS[decor_kind] as String)


static func load_effect_texture(effect_kind: String, team_id: int = TEAM_BLUE) -> Texture2D:
	team_id = team_id
	Log.assert_crash(_EFFECT_PATHS.has(effect_kind), "TinySwordsCatalog", "Unknown effect kind: %s" % effect_kind)
	return _load_texture(_EFFECT_PATHS[effect_kind] as String)


static func _add_sheet_animation(
	frames: SpriteFrames,
	animation_name: String,
	path: String,
	frame_size: Vector2i,
	row: int,
	frame_count: int,
	fps: float,
	should_loop: bool,
) -> void:
	var texture := _load_texture(path)
	var column_count: int = int(texture.get_width()) / frame_size.x
	var row_count: int = int(texture.get_height()) / frame_size.y
	Log.assert_crash(column_count >= frame_count, "TinySwordsCatalog", "Not enough frames in sheet row: %s" % path)
	Log.assert_crash(row_count > row, "TinySwordsCatalog", "Missing sheet row: %s" % path)

	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, should_loop)
	for i in range(frame_count):
		var frame_texture := AtlasTexture.new()
		frame_texture.atlas = texture
		frame_texture.region = Rect2(i * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
		frames.add_frame(animation_name, frame_texture)


static func _load_texture(path: String) -> Texture2D:
	var texture: Texture2D = load(path) as Texture2D
	Log.assert_crash(texture != null, "TinySwordsCatalog", "Failed to load texture: %s" % path)
	return texture


static func _remove_default_animation(frames: SpriteFrames) -> void:
	if frames.has_animation("default"):
		frames.remove_animation("default")
