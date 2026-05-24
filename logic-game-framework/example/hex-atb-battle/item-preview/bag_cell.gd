## BagCell - 一个 bag 格子的 UI Panel
##
## 负责: 显示 (item display_name + stackable badge), drag source, drop target。
## 不持有权威 item state — 由 ItemPreview._refresh_bag() 在 ItemSystem signal 时
## 用 ItemSystem.get_item_snapshot(item_id) 推过来 (set_item)。
extends Panel


var _owner_scene: Control
var _container_id: int = -1
var _slot_index: int = -1

var _current_item_id: int = 0
var _current_snapshot: Dictionary = {}

var _name_label: Label
var _count_label: Label


func _ready() -> void:
	_name_label = Label.new()
	_name_label.position = Vector2(4, 4)
	_name_label.size = size - Vector2(8, 24)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_name_label)

	_count_label = Label.new()
	_count_label.position = Vector2(size.x - 28, size.y - 20)
	_count_label.size = Vector2(24, 16)
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count_label)

	_apply_style(false)
	_refresh_visual()


## ItemPreview 在 _build_bag_grid 中调用 (一次性 slot_index 绑定)
func setup(owner_scene: Control, container_id: int, slot_index: int) -> void:
	_owner_scene = owner_scene
	_container_id = container_id
	_slot_index = slot_index
	set_meta("slot_index", slot_index)
	set_meta("container_id", container_id)


## reset_sandbox 后 ItemSystem 重建 player_bag (新 container_id), bag cell
## 需要 rebind 到新的 container_id, 否则 _drop_data 会去 move 到已死的旧 container。
## ItemPreview._refresh_bag 在每次 refresh 时调用。
##
## (bug 仅在 bag 作为 drop target 时触发: 卸装回 bag / bag 内重排。装备路径
##  bag→eq 用的是 target eq id, 不受 bag cache 影响。)
func set_target_container_id(container_id: int) -> void:
	_container_id = container_id
	set_meta("container_id", container_id)


## 由 ItemPreview._refresh_bag 推送
func set_item(item_id: int, snapshot: Dictionary) -> void:
	_current_item_id = item_id
	_current_snapshot = snapshot
	if is_inside_tree():
		_refresh_visual()


# ----- drag / drop -----------------------------------------------------------

func _get_drag_data(_pos: Vector2) -> Variant:
	if _current_item_id <= 0:
		return null

	# preview
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
		"source_kind": "bag",
	}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	# 实际允许 / 拒绝由 ItemSystem 决定;UI 总允许 drop, 失败再展示 error message。
	# 这样 DevAgent / 用户都能从 status label 拿到拒绝原因 — 而不是 drop 被静默吞掉。
	if not (data is Dictionary):
		return false
	return data.has("item_id")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if _owner_scene == null:
		return
	_owner_scene.handle_drop(data as Dictionary, _container_id, _slot_index)


# ----- visuals ---------------------------------------------------------------

func _refresh_visual() -> void:
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
	style.bg_color = Color(0.18, 0.22, 0.26) if has_item else Color(0.12, 0.14, 0.16)
	style.border_color = Color(0.48, 0.62, 0.72) if has_item else Color(0.25, 0.28, 0.32)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)
