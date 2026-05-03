## smoke_ui_main_menu - main_menu → demo apply_preset 链路 headless 验证 (M2.3 Phase D).
##
## 输入路径: 真模拟玩家鼠标点击 (InputHelper.click_control → Viewport.push_input),
## 不是 emit("pressed") 信号捷径 — 走完整 BaseButton.gui_input 派发链路.
##
## 流程:
##   1. ensure_window_size 撑大 headless window (默认 64×64 会让 Control 落到 viewport 外)
##   2. instantiate main_menu.tscn 加到根, await 2 frame 让 layout 算出
##   3. InputHelper.click_control 模拟点 Btn_Classic_1v1 → _start_match → demo apply_preset
##   4. 验证: self 子节点有 demo + demo._preset != null
##
## PASS 输出: `SMOKE_TEST_RESULT: PASS - main_menu → demo apply_preset chain works (real mouse input)`
extends Node


const InputHelper := preload("res://addons/logic-game-framework/example/rts-auto-battle/tests/ui/input_helper.gd")


func _ready() -> void:
	InputHelper.ensure_window_size(self)

	var menu_scene: PackedScene = load("res://addons/logic-game-framework/example/rts-auto-battle/frontend/main_menu.tscn") as PackedScene
	if menu_scene == null:
		_finish_fail("failed to load main_menu.tscn")
		return
	var menu: RtsMainMenu = menu_scene.instantiate() as RtsMainMenu
	add_child(menu)

	# 2 帧让 main_menu._ready 跑完 + Control layout pass 算出 Button.global_rect
	await get_tree().process_frame
	await get_tree().process_frame

	var first_button: Button = _find_first_button(menu)
	if first_button == null:
		_finish_fail("no Button found inside main_menu")
		return

	# 缓存元数据 — main_menu queue_free 后 Button 立即 invalid, 后面 print 不能访问 .name
	var btn_name: String = first_button.name
	var rect: Rect2 = first_button.get_global_rect()
	print("[debug] viewport=%s | button=%s rect=%s" % [
		get_viewport().get_visible_rect().size, btn_name, rect,
	])

	InputHelper.click_control(self, first_button)

	# 等 demo._ready (含 GameWorld.init / spawn / start_battle / _setup_*)
	await get_tree().process_frame
	await get_tree().process_frame

	var demo: Node = _find_demo_child()
	if demo == null:
		_finish_fail("demo_rts_frontend was not added as child after simulated mouse click")
		return
	if not demo.has_method("apply_preset"):
		_finish_fail("demo found but has no apply_preset method (preset 链路断)")
		return
	var preset_set: bool = (demo.get("_preset") != null)
	if not preset_set:
		_finish_fail("demo._preset was null after apply_preset (Classic 1v1 should set preset)")
		return

	print("smoke_ui_main_menu: clicked=%s demo=%s preset=%s" % [
		btn_name, demo.name, demo.get("_preset").name,
	])
	print("SMOKE_TEST_RESULT: PASS - main_menu → demo apply_preset chain works (real mouse input)")
	get_tree().quit(0)


func _finish_fail(reason: String) -> void:
	push_error("smoke_ui_main_menu FAIL: " + reason)
	print("SMOKE_TEST_RESULT: FAIL - " + reason)
	get_tree().quit(1)


func _find_first_button(node: Node) -> Button:
	if node is Button:
		return node as Button
	for child in node.get_children():
		var found := _find_first_button(child)
		if found != null:
			return found
	return null


func _find_demo_child() -> Node:
	for child in get_children():
		if child.has_method("apply_preset"):
			return child
	return null
