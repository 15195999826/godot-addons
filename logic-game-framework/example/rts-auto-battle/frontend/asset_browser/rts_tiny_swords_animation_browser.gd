extends Control


const Catalog := preload("res://addons/logic-game-framework/example/rts-auto-battle/frontend/assets/rts_tiny_swords_animation_catalog.gd")

const _MIN_SIZE: Vector2 = Vector2(1120.0, 700.0)
const _DIRECTIONS: Array[String] = [
	"south",
	"south_east",
	"east",
	"north_east",
	"north",
	"north_west",
	"west",
	"south_west",
]
const _DIRECTION_LABELS: Dictionary = {
	"south": "S",
	"south_east": "SE",
	"east": "E",
	"north_east": "NE",
	"north": "N",
	"north_west": "NW",
	"west": "W",
	"south_west": "SW",
}

var _catalog: Dictionary = {}
var _asset_names: Array[String] = []
var _filtered_asset_names: Array[String] = []
var _asset_list: ItemList
var _sequence_list: ItemList
var _direction_label: Label
var _direction_grid: GridContainer
var _direction_buttons: Dictionary = {}
var _filter_edit: LineEdit
var _status_option: OptionButton
var _status_filter: String = "accepted"
var _sprite: AnimatedSprite2D
var _preview_area: Control
var _title_label: Label
var _detail_label: Label
var _current_asset_name: String = ""
var _current_sequences: Array[Dictionary] = []
var _visible_sequences: Array[Dictionary] = []
var _selected_direction: String = "south"


func _ready() -> void:
	name = "RtsTinySwordsAnimationBrowser"
	custom_minimum_size = _MIN_SIZE
	_catalog = Catalog.scan()
	_asset_names = Catalog.get_asset_names(_catalog)
	_build_ui()
	_apply_filter("")


func _process(_delta: float) -> void:
	if _sprite == null or _preview_area == null:
		return
	var center := _preview_area.size * 0.5
	_sprite.position = center


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.name = "BrowserLayout"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var asset_panel := _make_panel("AssetPanel", Vector2(330.0, 0.0))
	root.add_child(asset_panel)

	var asset_box := VBoxContainer.new()
	asset_box.name = "AssetBox"
	asset_box.add_theme_constant_override("separation", 6)
	asset_panel.add_child(asset_box)

	var asset_label := Label.new()
	asset_label.text = "Assets"
	asset_box.add_child(asset_label)

	_filter_edit = LineEdit.new()
	_filter_edit.name = "AssetFilter"
	_filter_edit.placeholder_text = "Filter"
	_filter_edit.text_changed.connect(_on_filter_changed)
	asset_box.add_child(_filter_edit)

	_status_option = OptionButton.new()
	_status_option.name = "StatusFilter"
	_status_option.add_item("Accepted")
	_status_option.add_item("Pending")
	_status_option.add_item("All")
	_status_option.item_selected.connect(_on_status_selected)
	asset_box.add_child(_status_option)

	_asset_list = ItemList.new()
	_asset_list.name = "AssetList"
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.item_selected.connect(_on_asset_selected)
	asset_box.add_child(_asset_list)

	_preview_area = _make_panel("PreviewPanel", Vector2(470.0, 0.0))
	_preview_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_preview_area)

	var preview_box := VBoxContainer.new()
	preview_box.name = "PreviewBox"
	preview_box.add_theme_constant_override("separation", 6)
	_preview_area.add_child(preview_box)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_box.add_child(_title_label)

	var sprite_holder := Panel.new()
	sprite_holder.name = "SpriteHolder"
	sprite_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sprite_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_box.add_child(sprite_holder)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "PreviewSprite"
	_sprite.centered = true
	sprite_holder.add_child(_sprite)
	_preview_area = sprite_holder

	_detail_label = Label.new()
	_detail_label.name = "Details"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_box.add_child(_detail_label)

	var sequence_panel := _make_panel("SequencePanel", Vector2(280.0, 0.0))
	root.add_child(sequence_panel)

	var sequence_box := VBoxContainer.new()
	sequence_box.name = "SequenceBox"
	sequence_box.add_theme_constant_override("separation", 6)
	sequence_panel.add_child(sequence_box)

	var sequence_label := Label.new()
	sequence_label.text = "Sequences"
	sequence_box.add_child(sequence_label)

	_direction_label = Label.new()
	_direction_label.name = "DirectionLabel"
	_direction_label.text = "Directions"
	sequence_box.add_child(_direction_label)

	_direction_grid = GridContainer.new()
	_direction_grid.name = "DirectionGrid"
	_direction_grid.columns = 4
	_direction_grid.add_theme_constant_override("h_separation", 4)
	_direction_grid.add_theme_constant_override("v_separation", 4)
	sequence_box.add_child(_direction_grid)

	for direction in _DIRECTIONS:
		var direction_button := Button.new()
		direction_button.name = "Direction_%s" % direction
		direction_button.text = _DIRECTION_LABELS.get(direction, direction) as String
		direction_button.toggle_mode = true
		direction_button.custom_minimum_size = Vector2(48.0, 30.0)
		direction_button.pressed.connect(_on_direction_pressed.bind(direction))
		_direction_grid.add_child(direction_button)
		_direction_buttons[direction] = direction_button

	_sequence_list = ItemList.new()
	_sequence_list.name = "SequenceList"
	_sequence_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sequence_list.item_selected.connect(_on_sequence_selected)
	sequence_box.add_child(_sequence_list)
	_refresh_direction_grid()


func _make_panel(node_name: String, min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.custom_minimum_size = min_size
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _apply_filter(text: String) -> void:
	_filtered_asset_names.clear()
	var lower_filter := text.to_lower()
	for asset_name in _asset_names:
		if not _asset_matches_status(asset_name):
			continue
		if lower_filter.is_empty() or asset_name.to_lower().contains(lower_filter):
			_filtered_asset_names.append(asset_name)

	_asset_list.clear()
	for asset_name in _filtered_asset_names:
		_asset_list.add_item(asset_name)
	if not _filtered_asset_names.is_empty():
		_asset_list.select(0)
		_select_asset(_filtered_asset_names[0])
	else:
		_clear_selection()


func _select_asset(asset_name: String) -> void:
	_current_asset_name = asset_name
	_current_sequences = Catalog.get_sequences(_catalog, asset_name)
	if _current_sequences.is_empty():
		_visible_sequences.clear()
		_sequence_list.clear()
		_sprite.sprite_frames = null
		_title_label.text = asset_name
		_detail_label.text = "No sequences"
		_refresh_direction_grid()
		return
	_selected_direction = _first_available_direction(_current_sequences)
	_refresh_direction_grid()
	_populate_sequence_list()
	if _visible_sequences.is_empty():
		_sprite.sprite_frames = null
		_title_label.text = asset_name
		_detail_label.text = "No visible sequences"
		return
	_sequence_list.select(0)
	_select_visible_sequence(0)


func _select_visible_sequence(sequence_index: int) -> void:
	if sequence_index < 0 or sequence_index >= _visible_sequences.size():
		return
	var sequence: Dictionary = _visible_sequences[sequence_index]
	_sprite.sprite_frames = Catalog.create_frames(sequence)
	_sprite.animation = "preview"
	_sprite.play()
	_scale_sprite(sequence)
	_title_label.text = "%s / %s" % [_current_asset_name, sequence[Catalog.KEY_SEQUENCE] as String]
	_detail_label.text = "%s frames, %sx%s, %s" % [
		sequence[Catalog.KEY_COUNT] as int,
		_resolved_frame_size(sequence).x,
		_resolved_frame_size(sequence).y,
		sequence[Catalog.KEY_PATH] as String,
	]
	var status: String = sequence.get(Catalog.KEY_STATUS, "pending") as String
	var category: String = sequence.get(Catalog.KEY_CATEGORY, "") as String
	var direction: String = sequence.get(Catalog.KEY_DIRECTION, "") as String
	var animation: String = sequence.get(Catalog.KEY_ANIMATION, "") as String
	if not direction.is_empty() or not animation.is_empty() or not category.is_empty():
		_detail_label.text += "\n%s / %s / %s / %s" % [status, category, direction, animation]
	_sprite.flip_h = sequence.get(Catalog.KEY_FLIP_H, false) as bool


func _clear_selection() -> void:
	_current_asset_name = ""
	_current_sequences.clear()
	_visible_sequences.clear()
	_sequence_list.clear()
	_sprite.sprite_frames = null
	_title_label.text = ""
	_detail_label.text = ""
	_refresh_direction_grid()


func _populate_sequence_list() -> void:
	_sequence_list.clear()
	_visible_sequences.clear()
	var directional := _asset_has_directional_sequences(_current_sequences)
	var used_labels: Dictionary = {}
	for sequence in _current_sequences:
		if directional and (sequence.get(Catalog.KEY_DIRECTION, "") as String) != _selected_direction:
			continue
		var label := _sequence_display_label(sequence, directional)
		if directional and used_labels.has(label):
			continue
		used_labels[label] = true
		_visible_sequences.append(sequence)
		_sequence_list.add_item(label)


func _sequence_display_label(sequence: Dictionary, directional: bool) -> String:
	if directional:
		var animation: String = sequence.get(Catalog.KEY_ANIMATION, "") as String
		if not animation.is_empty():
			return animation
	return sequence[Catalog.KEY_SEQUENCE] as String


func _asset_has_directional_sequences(sequences: Array[Dictionary]) -> bool:
	for sequence in sequences:
		if not (sequence.get(Catalog.KEY_DIRECTION, "") as String).is_empty():
			return true
	return false


func _first_available_direction(sequences: Array[Dictionary]) -> String:
	if not _asset_has_directional_sequences(sequences):
		return ""
	for direction in _DIRECTIONS:
		for sequence in sequences:
			if (sequence.get(Catalog.KEY_DIRECTION, "") as String) == direction:
				return direction
	return "south"


func _direction_has_sequence(direction: String) -> bool:
	for sequence in _current_sequences:
		if (sequence.get(Catalog.KEY_DIRECTION, "") as String) == direction:
			return true
	return false


func _refresh_direction_grid() -> void:
	if _direction_grid == null:
		return
	var directional := _asset_has_directional_sequences(_current_sequences)
	if _direction_label != null:
		_direction_label.visible = directional
	_direction_grid.visible = directional
	for direction in _DIRECTIONS:
		var direction_button := _direction_buttons.get(direction) as Button
		if direction_button == null:
			continue
		var has_sequence := directional and _direction_has_sequence(direction)
		direction_button.disabled = not has_sequence
		direction_button.button_pressed = has_sequence and direction == _selected_direction


func _scale_sprite(sequence: Dictionary) -> void:
	var frame_size := _resolved_frame_size(sequence)
	var max_width := 360.0
	var max_height := 360.0
	var scale_value: float = min(max_width / float(frame_size.x), max_height / float(frame_size.y))
	scale_value = clamp(scale_value, 0.35, 3.0)
	_sprite.scale = Vector2(scale_value, scale_value)


func _resolved_frame_size(sequence: Dictionary) -> Vector2i:
	var frame_size: Vector2i = sequence[Catalog.KEY_FRAME_SIZE] as Vector2i
	if frame_size.x > 0 and frame_size.y > 0:
		return frame_size
	if _sprite.sprite_frames != null and _sprite.sprite_frames.get_frame_count("preview") > 0:
		var texture := _sprite.sprite_frames.get_frame_texture("preview", 0)
		if texture != null:
			return Vector2i(int(texture.get_width()), int(texture.get_height()))
	return Vector2i(64, 64)


func _asset_matches_status(asset_name: String) -> bool:
	if _status_filter == "all":
		return true
	return Catalog.get_asset_status(_catalog, asset_name) == _status_filter


func _on_filter_changed(new_text: String) -> void:
	_apply_filter(new_text)


func _on_status_selected(index: int) -> void:
	match index:
		0:
			_status_filter = "accepted"
		1:
			_status_filter = "pending"
		_:
			_status_filter = "all"
	_apply_filter(_filter_edit.text)


func _on_asset_selected(index: int) -> void:
	if index < 0 or index >= _filtered_asset_names.size():
		return
	_select_asset(_filtered_asset_names[index])


func _on_sequence_selected(index: int) -> void:
	_select_visible_sequence(index)


func _on_direction_pressed(direction: String) -> void:
	if not _direction_has_sequence(direction):
		return
	_selected_direction = direction
	_refresh_direction_grid()
	_populate_sequence_list()
	if _visible_sequences.is_empty():
		return
	_sequence_list.select(0)
	_select_visible_sequence(0)
