## EquipmentSlot - 一个装备槽 UI Panel (1..6 label, 内部 slot_index 0..5)
##
## 与 BagCell 类似, 但 container_id 在切 actor 时通过 set_target_container_id 重设。
extends Panel


var _owner_scene: Object
var _container_id: int = -1
var _slot_index: int = -1  # 0..5

var _current_item_id: int = 0
var _current_snapshot: Dictionary = {}

var _slot_label: Label
var _name_label: Label
var _count_label: Label


func _ready() -> void:
	_slot_label = Label.new()
	_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_label.position = Vector2(6, 4)
	_slot_label.add_theme_font_size_override("font_size", 11)
	_slot_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	add_child(_slot_label)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.position = Vector2(8, 28)
	_name_label.size = size - Vector2(16, 48)
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_name_label)

	_count_label = Label.new()
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.position = Vector2(size.x - 36, size.y - 24)
	_count_label.size = Vector2(28, 20)
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count_label)

	_apply_style(false)
	_refresh_visual()


func setup(owner_scene: Object, slot_index: int) -> void:
	_owner_scene = owner_scene
	_slot_index = slot_index
	set_meta("slot_index", slot_index)


func set_target_container_id(container_id: int) -> void:
	_container_id = container_id
	set_meta("container_id", container_id)


func set_item(item_id: int, snapshot: Dictionary) -> void:
	_current_item_id = item_id
	_current_snapshot = snapshot
	if is_inside_tree():
		_refresh_visual()


# ----- drag / drop -----------------------------------------------------------

func _get_drag_data(_pos: Vector2) -> Variant:
	if _current_item_id <= 0:
		return null

	var preview := Panel.new()
	preview.size = size
	var lbl := Label.new()
	lbl.text = String(_current_snapshot.get("display_name", "Item %d" % _current_item_id))
	lbl.position = Vector2(4, 4)
	preview.add_child(lbl)
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
	set_drag_preview(preview)

	return {
		"item_id": _current_item_id,
		"source_container_id": _container_id,
		"source_slot_index": _slot_index,
		"source_kind": "equipment",
	}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return data.has("item_id")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if _owner_scene == null:
		return
	_owner_scene.handle_drop(data as Dictionary, _container_id, _slot_index)


# ----- visuals ---------------------------------------------------------------

func _refresh_visual() -> void:
	_slot_label.text = "Slot %d" % (_slot_index + 1)
	var has_item := _current_item_id > 0
	_apply_style(has_item)
	if has_item:
		_name_label.text = String(_current_snapshot.get("display_name", "Item %d" % _current_item_id))
		if bool(_current_snapshot.get("stackable", false)):
			var count := int(_current_snapshot.get("count", 1))
			_count_label.text = "x%d" % count
		else:
			_count_label.text = ""
	else:
		_name_label.text = ""
		_count_label.text = ""


func _apply_style(has_item: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.26, 0.32) if has_item else Color(0.14, 0.16, 0.18)
	style.border_color = Color(0.32, 0.72, 0.68) if has_item else Color(0.30, 0.34, 0.40)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", style)
