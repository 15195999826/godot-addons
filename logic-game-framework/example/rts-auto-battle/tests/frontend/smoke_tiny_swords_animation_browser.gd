extends Node


const Catalog := preload("res://addons/logic-game-framework/example/rts-auto-battle/frontend/assets/rts_tiny_swords_animation_catalog.gd")
const BROWSER_SCENE_PATH: String = "res://addons/logic-game-framework/example/rts-auto-battle/frontend/asset_browser/rts_tiny_swords_animation_browser.tscn"


func _ready() -> void:
	var scene: PackedScene = load(BROWSER_SCENE_PATH) as PackedScene
	if scene == null:
		_fail("browser scene failed to load")
		return

	var browser := scene.instantiate()
	add_child(browser)
	await get_tree().process_frame
	await get_tree().process_frame

	var asset_list := browser.get_node_or_null("BrowserLayout/AssetPanel/AssetBox/AssetList") as ItemList
	if asset_list == null:
		_fail("asset list missing")
		return
	if asset_list.item_count <= 0:
		_fail("no animated assets found")
		return

	var sequence_list := browser.get_node_or_null("BrowserLayout/SequencePanel/SequenceBox/SequenceList") as ItemList
	if sequence_list == null:
		_fail("sequence list missing")
		return
	if sequence_list.item_count <= 0:
		_fail("no animation sequences found")
		return

	var direction_grid := browser.get_node_or_null("BrowserLayout/SequencePanel/SequenceBox/DirectionGrid") as GridContainer
	if direction_grid == null:
		_fail("direction grid missing")
		return

	var status_filter := browser.get_node_or_null("BrowserLayout/AssetPanel/AssetBox/StatusFilter") as OptionButton
	if status_filter == null:
		_fail("status filter missing")
		return

	var sprite := browser.get_node_or_null("BrowserLayout/PreviewPanel/PreviewBox/SpriteHolder/PreviewSprite") as AnimatedSprite2D
	if sprite == null:
		_fail("preview sprite missing")
		return
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("preview"):
		_fail("preview animation missing")
		return
	if sprite.sprite_frames.get_frame_count("preview") <= 0:
		_fail("preview animation has too few frames")
		return

	browser.call("_apply_filter", "unit/lancer/red")
	await get_tree().process_frame
	if not direction_grid.visible:
		_fail("direction grid hidden for directional unit")
		return
	if sequence_list.item_count <= 0:
		_fail("unit state list missing")
		return
	for index in range(sequence_list.item_count):
		if sequence_list.get_item_text(index).contains("/"):
			_fail("unit sequence list should show animation state only")
			return

	var catalog := Catalog.scan()
	if not Catalog.get_sequences(catalog, "resource/sheep").is_empty():
		_fail("legacy mixed sheep asset should not exist")
		return
	if Catalog.get_sequences(catalog, "resource/sheep_free_pack").is_empty():
		_fail("free pack sheep asset missing")
		return
	if Catalog.get_sequences(catalog, "resource/happy_sheep").is_empty():
		_fail("happy sheep asset missing")
		return
	if not _has_sequence_with_frame_count(catalog, "building/goblins/wood_tower", "blue", 2):
		_fail("wood tower blue should be animated")
		return
	if not _has_direction_state(catalog, "unit/lancer/red", "south", "attack"):
		_fail("lancer south attack state missing")
		return
	if _has_direction_state(catalog, "unit/lancer/red", "south", "defense"):
		_fail("lancer defense should not be accepted")
		return
	if not _has_direction_state(catalog, "unit/warrior/red", "east", "attack_1"):
		_fail("warrior east attack_1 state missing")
		return
	if not _has_direction_state(catalog, "unit/warrior/red", "east", "attack_2"):
		_fail("warrior east attack_2 state missing")
		return
	if not _has_direction_state(catalog, "unit/pawn/blue", "west", "idle"):
		_fail("pawn west idle state missing")
		return
	if not _has_direction_state_flip(catalog, "unit/pawn/blue", "west", "idle", true):
		_fail("pawn west idle should be horizontally flipped")
		return
	if not _has_direction_state_flip(catalog, "unit/pawn/blue", "east", "idle", false):
		_fail("pawn east idle should not be horizontally flipped")
		return

	var accepted_assets := 0
	var pending_assets := 0
	var accepted_sequences := 0
	for asset_name in Catalog.get_asset_names(catalog):
		var status := Catalog.get_asset_status(catalog, asset_name)
		if status == "accepted":
			accepted_assets += 1
			for sequence in Catalog.get_sequences(catalog, asset_name):
				var path: String = sequence[Catalog.KEY_PATH] as String
				if not FileAccess.file_exists(path):
					_fail("accepted sequence path missing: %s" % path)
					return
				accepted_sequences += 1
		elif status == "pending":
			pending_assets += 1
	if accepted_assets < 30:
		_fail("too few accepted animation assets: %d" % accepted_assets)
		return
	if pending_assets <= 0:
		_fail("pending animation assets missing")
		return

	print("SMOKE_TEST_RESULT: PASS - tiny swords animation browser loaded %d accepted assets, %d accepted sequences, %d pending assets" % [
		accepted_assets,
		accepted_sequences,
		pending_assets,
	])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)


func _has_sequence_with_frame_count(catalog: Dictionary, asset_id: String, sequence_name: String, min_count: int) -> bool:
	for sequence in Catalog.get_sequences(catalog, asset_id):
		if (sequence[Catalog.KEY_SEQUENCE] as String) == sequence_name and (sequence[Catalog.KEY_COUNT] as int) >= min_count:
			return true
	return false


func _has_direction_state(catalog: Dictionary, asset_id: String, direction: String, animation: String) -> bool:
	for sequence in Catalog.get_sequences(catalog, asset_id):
		if (sequence.get(Catalog.KEY_DIRECTION, "") as String) == direction and (sequence.get(Catalog.KEY_ANIMATION, "") as String) == animation:
			return true
	return false


func _has_direction_state_flip(catalog: Dictionary, asset_id: String, direction: String, animation: String, flip_h: bool) -> bool:
	for sequence in Catalog.get_sequences(catalog, asset_id):
		var same_direction := (sequence.get(Catalog.KEY_DIRECTION, "") as String) == direction
		var same_animation := (sequence.get(Catalog.KEY_ANIMATION, "") as String) == animation
		if same_direction and same_animation and (sequence.get(Catalog.KEY_FLIP_H, false) as bool) == flip_h:
			return true
	return false
