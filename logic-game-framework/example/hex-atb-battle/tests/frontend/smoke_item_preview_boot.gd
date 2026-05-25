## Smoke: item_preview.tscn 场景能 boot 并构建 UI 树
##
## 验证:
##   - scene 实例化无 SCRIPT ERROR
##   - bag 10x8 = 80 cells 创建到位
##   - 6 equipment slots 创建到位
##   - 种子 item 已写入 player bag (snapshot 检查)
##   - status label 默认存在
##
## 不做: 不模拟真实拖拽 (那归 Phase D + E DevAgent 流程)
extends Node


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: item_preview.tscn boot ===")

	var scene := load("res://addons/logic-game-framework/example/hex-atb-battle/item-preview/item_preview.tscn") as PackedScene
	if scene == null:
		_finish_fail("PackedScene 加载失败")
		return

	var inst := scene.instantiate() as Control
	if inst == null:
		_finish_fail("scene 实例化失败")
		return
	add_child(inst)

	# 等 2 帧让 Control layout pass 完成
	await get_tree().process_frame
	await get_tree().process_frame

	# bag cells
	var bag_cells := _find_children_by_prefix(inst, "BagCell_")
	if bag_cells.size() != 80:
		_finish_fail("bag cells 应 = 80, 实际 %d" % bag_cells.size())
		return

	# equipment slots
	var eq_slots := _find_children_by_prefix(inst, "EquipmentSlot_")
	if eq_slots.size() != 6:
		_finish_fail("equipment slots 应 = 6, 实际 %d" % eq_slots.size())
		return

	# actor selector
	if not _has_child_by_name(inst, "ActorSelector"):
		_finish_fail("ActorSelector 缺失")
		return

	# status label
	if not _has_child_by_name(inst, "StatusLabel"):
		_finish_fail("StatusLabel 缺失")
		return

	# inventory_state 应至少有 5 个 seed items
	var state: Dictionary = inst.get_inventory_state()
	var bag_items: Array = state.get("bag", [])
	if bag_items.size() < 5:
		_finish_fail("seed 应至少 5 个 item, 实际 %d" % bag_items.size())
		return
	var actors: Array = state.get("actors", [])
	if actors.size() != 3:
		_finish_fail("sandbox actors 应 = 3, 实际 %d" % actors.size())
		return
	for actor_state in actors:
		var actor_id := String((actor_state as Dictionary).get("actor_id", ""))
		if actor_id.begins_with("preview-actor-"):
			_finish_fail("actor_id 不应是旧 fake id: %s" % actor_id)
			return
		if not ActorId.is_valid(actor_id):
			_finish_fail("actor_id 应是 GameplayInstance 分配的 runtime id, got: %s" % actor_id)
			return

	# layout_state 含 bag_cells / equipment_slots rect
	var layout: Dictionary = inst.get_layout_state()
	if not layout.has("bag_cells") or (layout.get("bag_cells") as Array).size() != 80:
		_finish_fail("layout_state.bag_cells 缺失或大小错")
		return
	if not layout.has("equipment_slots") or (layout.get("equipment_slots") as Array).size() != 6:
		_finish_fail("layout_state.equipment_slots 缺失或大小错")
		return

	print("SMOKE_TEST_RESULT: PASS - item_preview.tscn boot OK (%d bag cells / %d eq slots / %d seed items)" % [
		bag_cells.size(), eq_slots.size(), bag_items.size()
	])
	get_tree().quit(0)


func _find_children_by_prefix(root: Node, prefix: String) -> Array:
	var matches: Array = []
	_collect_by_prefix_recursive(root, prefix, matches)
	return matches


func _collect_by_prefix_recursive(node: Node, prefix: String, matches: Array) -> void:
	for c in node.get_children():
		if c.name.begins_with(prefix):
			matches.append(c)
		_collect_by_prefix_recursive(c, prefix, matches)


func _has_child_by_name(root: Node, target_name: String) -> bool:
	for c in root.get_children():
		if c.name == target_name:
			return true
		if _has_child_by_name(c, target_name):
			return true
	return false


func _finish_fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
