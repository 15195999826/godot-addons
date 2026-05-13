class_name DevAgentDemo
extends Control

const DemoSceneAgentOpsScript := preload("res://addons/lomolib/dev_agent/example/demo_scene_agent_ops.gd")
const DevAgentBridgeScript := preload("res://addons/lomolib/dev_agent/dev_agent_bridge.gd")

var _status_label: Label
var _event_label: Label
var _object_panel: Panel
var _object_name_label: Label
var _click_count := 0
var _escape_count := 0
var _selected_object_id := ""
var _events: Array[String] = []
var _bridge = null


func _ready() -> void:
	name = "DevAgentDemo"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	_build_ui()
	_install_dev_agent()
	_add_event("demo ready")
	_update_status()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_escape_count += 1
			_add_event("Escape tapped through real input")
			_update_status()


func select_demo_object(object_id: String) -> Dictionary:
	if object_id != "alpha":
		return {
			"ok": false,
			"message": "unknown demo object: %s" % object_id,
			"data": get_dev_agent_state(),
		}

	_selected_object_id = object_id
	_style_object(true)
	_add_event("scene op selected object: %s" % object_id)
	_update_status()
	return {
		"ok": true,
		"message": "selected demo object: %s" % object_id,
		"data": get_dev_agent_state(),
	}


func get_dev_agent_state() -> Dictionary:
	return {
		"click_count": _click_count,
		"escape_count": _escape_count,
		"selected_object_id": _selected_object_id,
		"events": _events.duplicate(),
	}


func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.08, 0.09, 0.10)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "DevAgent Debug Mode Demo"
	title.position = Vector2(24, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	add_child(title)

	var increment_button := Button.new()
	increment_button.name = "IncrementButton"
	increment_button.text = "Increment via real click"
	increment_button.position = Vector2(24, 78)
	increment_button.size = Vector2(240, 44)
	increment_button.pressed.connect(_on_increment_pressed)
	add_child(increment_button)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "Reset"
	reset_button.position = Vector2(280, 78)
	reset_button.size = Vector2(120, 44)
	reset_button.pressed.connect(_on_reset_pressed)
	add_child(reset_button)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.position = Vector2(24, 146)
	_status_label.size = Vector2(420, 120)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.92))
	add_child(_status_label)

	_object_panel = Panel.new()
	_object_panel.name = "DemoObjectAlpha"
	_object_panel.position = Vector2(520, 118)
	_object_panel.size = Vector2(220, 150)
	_object_panel.gui_input.connect(_on_object_gui_input)
	add_child(_object_panel)

	_object_name_label = Label.new()
	_object_name_label.name = "ObjectNameLabel"
	_object_name_label.text = "Object alpha"
	_object_name_label.position = Vector2(24, 26)
	_object_name_label.add_theme_font_size_override("font_size", 20)
	_object_name_label.add_theme_color_override("font_color", Color(0.08, 0.10, 0.12))
	_object_panel.add_child(_object_name_label)
	_style_object(false)

	_event_label = Label.new()
	_event_label.name = "EventLogLabel"
	_event_label.position = Vector2(24, 300)
	_event_label.size = Vector2(720, 260)
	_event_label.add_theme_font_size_override("font_size", 16)
	_event_label.add_theme_color_override("font_color", Color(0.74, 0.78, 0.82))
	add_child(_event_label)


func _install_dev_agent() -> void:
	var ops := DemoSceneAgentOpsScript.new() as Node
	ops.name = "DemoSceneAgentOps"
	add_child(ops)

	_bridge = DevAgentBridgeScript.new()
	_bridge.name = "DevAgentBridge"
	_bridge.enabled = true
	_bridge.scene_ops_path = NodePath("../DemoSceneAgentOps")
	add_child(_bridge)
	call_deferred("_print_dev_agent_paths")


func _print_dev_agent_paths() -> void:
	if _bridge == null:
		return
	var info: Dictionary = _bridge.get_session_info() as Dictionary
	print("[DevAgentDemo] inbox: %s" % str(info.get("inbox_global", "")))
	print("[DevAgentDemo] outbox: %s" % str(info.get("outbox_global", "")))
	print("[DevAgentDemo] session_dir: %s" % str(info.get("session_dir_global", "")))


func _on_increment_pressed() -> void:
	_click_count += 1
	_add_event("IncrementButton pressed through UI")
	_update_status()


func _on_reset_pressed() -> void:
	_click_count = 0
	_escape_count = 0
	_selected_object_id = ""
	_events.clear()
	_style_object(false)
	_add_event("ResetButton pressed")
	_update_status()


func _on_object_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_selected_object_id = "alpha"
			_style_object(true)
			_add_event("DemoObjectAlpha clicked through real input")
			_update_status()


func _add_event(message: String) -> void:
	_events.append(message)
	while _events.size() > 8:
		_events.pop_front()
	_update_event_log()


func _update_status() -> void:
	_status_label.text = "click_count: %d\nescape_count: %d\nselected_object_id: %s" % [
		_click_count,
		_escape_count,
		_selected_object_id if not _selected_object_id.is_empty() else "(none)",
	]


func _update_event_log() -> void:
	if _event_label == null:
		return

	var text := "Events\n"
	for event_text in _events:
		text += "- %s\n" % event_text
	_event_label.text = text


func _style_object(selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.32, 0.72, 0.68) if selected else Color(0.62, 0.68, 0.74)
	style.border_color = Color(0.95, 0.88, 0.36) if selected else Color(0.18, 0.22, 0.26)
	style.set_border_width_all(4 if selected else 2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_object_panel.add_theme_stylebox_override("panel", style)
