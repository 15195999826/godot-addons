## RtsMainMenu - 屏幕居中预设选择菜单 (M2.3 Phase C 起 demo F6 入口).
##
## F6 打开 main_menu.tscn → 看到 N 个 Button (RtsMatchPreset.all_presets()) → 点 Button →
## 实例化 demo_rts_frontend → apply_preset(选中) → demo 替换 main_menu (queue_free self).
##
## demo_rts_frontend.tscn 仍能 F6 直接跑 (走 _preset = null fallback hardcode 保 smoke 不破).
class_name RtsMainMenu
extends Control


const _DEMO_SCENE := preload("res://addons/logic-game-framework/example/rts-auto-battle/frontend/demo_rts_frontend.tscn")
const _BUTTON_MIN_SIZE: Vector2 = Vector2(360.0, 56.0)


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Buttons"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -200.0
	vbox.offset_right = 200.0
	vbox.offset_top = -180.0
	vbox.offset_bottom = 180.0
	add_child(vbox)

	var title := Label.new()
	title.text = "Inkmon RTS — Skirmish Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	vbox.add_child(spacer)

	for preset in RtsMatchPreset.all_presets():
		vbox.add_child(_make_preset_button(preset))


func _make_preset_button(preset: RtsMatchPreset) -> Button:
	var btn := Button.new()
	btn.name = "Btn_%s" % preset.name.replace(" ", "_")
	btn.text = "  %s\n  %s" % [preset.name, preset.description]
	btn.tooltip_text = preset.description
	btn.custom_minimum_size = _BUTTON_MIN_SIZE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void: _start_match(preset))
	return btn


## 加载 demo + 注入 preset + 切到 demo (main_menu 从父节点摘除).
## 父节点接管 demo (Godot 4 root tree 必有父; main_menu.tscn 作为 root scene 时父 = SceneTree.root).
func _start_match(preset: RtsMatchPreset) -> void:
	var parent: Node = get_parent()
	if parent == null:
		push_error("[RtsMainMenu] no parent — cannot swap to demo")
		return
	var demo: Node = _DEMO_SCENE.instantiate()
	if demo.has_method("apply_preset"):
		demo.call("apply_preset", preset)
	parent.add_child(demo)
	queue_free()
