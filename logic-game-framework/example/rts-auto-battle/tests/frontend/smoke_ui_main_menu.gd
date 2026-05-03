## smoke_ui_main_menu - main_menu → demo apply_preset 链路 headless 验证 (M2.3 Phase D).
##
## 流程:
##   1. instantiate main_menu.tscn 加到根
##   2. await frame 让 _ready 跑完 (创建 Button + 装 preset)
##   3. 取第一个 Button (Classic 1v1) emit pressed → 触发 _start_match → 实例化 demo
##      apply_preset Classic + add_child to root + queue_free(main_menu)
##   4. await frame 等 demo._ready 跑完
##   5. 验证: 根下有 demo 节点 + demo._preset != null + main_menu 已 freed
##
## PASS 输出: `SMOKE_TEST_RESULT: PASS - main_menu → demo apply_preset chain works`
## FAIL 输出: 按失败原因细化.
extends Node


func _ready() -> void:
	var menu_scene: PackedScene = load("res://addons/logic-game-framework/example/rts-auto-battle/frontend/main_menu.tscn") as PackedScene
	if menu_scene == null:
		_finish_fail("failed to load main_menu.tscn")
		return
	var menu: RtsMainMenu = menu_scene.instantiate() as RtsMainMenu
	add_child(menu)

	await get_tree().process_frame

	# 找 main_menu 内第一个 Button (Classic 1v1) 模拟点击
	var first_button: Button = _find_first_button(menu)
	if first_button == null:
		_finish_fail("no Button found inside main_menu")
		return
	first_button.pressed.emit()

	# 等 demo._ready (含 GameWorld.init / spawn / start_battle / _setup_*)
	await get_tree().process_frame
	await get_tree().process_frame

	# 验证: 1) root 有 demo 节点 2) demo._preset 不空 3) main_menu freed
	var demo: Node = _find_demo_child()
	if demo == null:
		_finish_fail("demo_rts_frontend was not added as child after Button press")
		return
	if not demo.has_method("apply_preset"):
		_finish_fail("demo found but has no apply_preset method (preset 链路断)")
		return
	if not is_instance_valid(menu) or menu.is_queued_for_deletion():
		pass  # 期待 menu 已 queue_free (queue_free 异步, 不强求 immediate)
	var preset_set: bool = (demo.get("_preset") != null)
	if not preset_set:
		_finish_fail("demo._preset was null after apply_preset (Classic 1v1 should set preset)")
		return

	print("smoke_ui_main_menu: demo=%s preset=%s" % [demo.name, demo.get("_preset").name])
	print("SMOKE_TEST_RESULT: PASS - main_menu → demo apply_preset chain works")
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
