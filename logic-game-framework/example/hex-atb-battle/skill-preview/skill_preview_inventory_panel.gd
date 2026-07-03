class_name SkillPreviewInventoryPanel
extends RefCounted

## SkillPreviewInventoryPanel - SkillPreview 的 Inventory tab 子控制器
##
## 职责: Workspace drawer 的 Inventory tab (player bag + actor equipment 面板) 的
## UI 构建, 以及与 ItemSystem / HexPlayerInventory 的 model bridge (drop 处理、
## seed、刷新、快照)。从 skill_preview.gd 纯平移拆出, 函数体逻辑逐行不变, 仅把对
## 宿主状态/方法的引用改为 `_host.` 前缀。
##
## host 契约:
## - 宿主 (skill_preview.gd, extends Node) 持有本 panel: `_host._inventory_panel`。
##   本 panel 反向持宿主引用 `_host` (RefCounted 持 Node 无 refcount 环: Node 生命周期
##   手动管理, panel 随宿主 free 时释放)。
## - **共享 selection 留宿主**: `_selected_kind` / `_selected_actor_idx` /
##   `_selected_spt_actor_idx` / `_actors` / `_actor_ids` 是 timeline / character panel /
##   inventory 多方共读的头号共享态, 由宿主唯一持有; panel 经 `_host.` 只读它们来决定
##   当前 equipment 面板显示哪个 actor。若下沉到 panel 会产生多副本同步问题, 故不搬。
## - theme 助手 (`_clay_sb` / `_clay_font_bold`)、CLAY_* 常量、`_actor_timeline_label`
##   属宿主通用能力, panel 经 `_host.` 调用。
## - `_world` (resident WorldGI) 留宿主; reset-to-demo 时经 `_host._world` 重挂 inventory。
##
## BagCell / EquipmentSlot 的 owner 传本 panel (`self`): 它们的 `_drop_data` 只回调
## owner 的 `handle_drop`, owner 类型已放宽为 Object 以接受 RefCounted panel。


const HexItemDomainScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_item_domain.gd")
const HexItemCatalogScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_item_catalog.gd")
const HexPlayerInventoryScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_player_inventory.gd")
const BagCellScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/item-preview/bag_cell.gd")
const EquipmentSlotScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/item-preview/equipment_slot.gd")

const INVENTORY_BAG_COLS := HexPlayerInventory.DEFAULT_BAG_WIDTH
const INVENTORY_BAG_ROWS := HexPlayerInventory.DEFAULT_BAG_HEIGHT
const INVENTORY_BAG_CELL_SIZE := Vector2(58, 46)
const INVENTORY_BAG_CELL_GAP := 4
const INVENTORY_EQ_SLOT_SIZE := Vector2(92, 74)
const INVENTORY_EQ_SLOT_GAP := 8
const INVENTORY_SEED_ITEMS: Array[Dictionary] = [
	{"config_id": &"training_sword", "count": 1, "slot": 0},
	{"config_id": &"frost_orb", "count": 1, "slot": 1},
	{"config_id": &"minor_rune", "count": 5, "slot": 2},
	{"config_id": &"broken_stone", "count": 10, "slot": 3},
	# §Phase G: dev scene 自主验收 (/run-dev-scene skill-preview) 默认放装备物品,
	# DevAgent equip_item op 直接装备到 selected actor 触发 grant 链路。
	{"config_id": &"morbid_mask", "count": 1, "slot": 4},
	{"config_id": &"daedalus_charm", "count": 1, "slot": 5},
	{"config_id": &"training_sword", "count": 1, "slot": 10},
]


var _host: Node = null

var _inventory: HexPlayerInventory = null
var _inventory_bag_cells: Array[Control] = []
var _inventory_equipment_slots: Array[Control] = []
var _inventory_bag_grid_root: Control = null
var _inventory_equipment_panel_root: Control = null
var _inventory_actor_label: Label = null
var _inventory_status_label: Label = null
var _last_inventory_op_message: String = "ready"
var _last_inventory_op_success: bool = true
var _last_inventory_error: String = ""
var _inventory_seeded: bool = false
var _drawer_inventory_tab: VBoxContainer = null


func _init(host: Node) -> void:
	_host = host


## 宿主 _exit_tree 调用: 断信号 + 释放 inventory (原 _exit_tree 326-329 逻辑封装)。
func dispose() -> void:
	_disconnect_item_system_signals()
	if _inventory != null:
		_inventory.dispose()
		_inventory = null


func _init_inventory_session() -> void:
	ItemSystem.reset_session()
	_create_inventory_session()


func _create_inventory_session() -> void:
	ItemSystem.configure_domain(HexItemDomainScript.new(), HexItemCatalogScript.new())
	_inventory = HexPlayerInventoryScript.new()
	_inventory.init_inventory()
	_last_inventory_op_message = "inventory ready"
	_last_inventory_op_success = true
	_last_inventory_error = ""
	_inventory_seeded = false


func _reset_inventory_session_to_demo() -> void:
	_disconnect_item_system_signals()
	if _host._world != null:
		_host._world.set_player_inventory(null)
	if _inventory != null:
		_inventory.dispose()
		_inventory = null
	ItemSystem.reset_session()
	_create_inventory_session()
	if _host._world != null:
		_host._world.set_player_inventory(_inventory)
	_connect_item_system_signals()


func _build_drawer_inventory_tab() -> void:
	_drawer_inventory_tab = VBoxContainer.new()
	_drawer_inventory_tab.name = "Inventory"
	_drawer_inventory_tab.add_theme_constant_override("separation", 8)
	_drawer_inventory_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_inventory_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host._drawer_tabs.add_child(_drawer_inventory_tab)

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_override("font", _host._clay_font_bold())
	_drawer_inventory_tab.add_child(title)

	var shell := HBoxContainer.new()
	shell.name = "InventoryShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 12)
	_drawer_inventory_tab.add_child(shell)

	var bag_panel := PanelContainer.new()
	bag_panel.name = "InventoryBagPanel"
	bag_panel.custom_minimum_size = Vector2(
		INVENTORY_BAG_COLS * (INVENTORY_BAG_CELL_SIZE.x + INVENTORY_BAG_CELL_GAP) + 24,
		0
	)
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_panel.add_theme_stylebox_override("panel", _host._clay_sb(Color("111827"), 6, 10, 8, 1, 0))
	shell.add_child(bag_panel)
	_inventory_bag_grid_root = bag_panel

	var bag_box := VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", 6)
	bag_panel.add_child(bag_box)
	var bag_header := Label.new()
	bag_header.text = "Player Bag"
	bag_header.add_theme_font_override("font", _host._clay_font_bold())
	bag_header.add_theme_color_override("font_color", _host.CLAY_TEXT)
	bag_box.add_child(bag_header)

	var bag_scroll := ScrollContainer.new()
	bag_scroll.name = "InventoryBagScroll"
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bag_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_box.add_child(bag_scroll)

	var bag_grid := GridContainer.new()
	bag_grid.name = "InventoryBagGrid"
	bag_grid.columns = INVENTORY_BAG_COLS
	bag_grid.add_theme_constant_override("h_separation", INVENTORY_BAG_CELL_GAP)
	bag_grid.add_theme_constant_override("v_separation", INVENTORY_BAG_CELL_GAP)
	bag_scroll.add_child(bag_grid)

	_inventory_bag_cells.clear()
	for slot_index in range(INVENTORY_BAG_COLS * INVENTORY_BAG_ROWS):
		var cell := BagCellScript.new() as Control
		cell.name = "SkillPreviewBagCell_%d" % slot_index
		cell.custom_minimum_size = INVENTORY_BAG_CELL_SIZE
		cell.size = INVENTORY_BAG_CELL_SIZE
		cell.setup(self, _inventory.player_bag_id if _inventory != null else -1, slot_index)
		bag_grid.add_child(cell)
		_inventory_bag_cells.append(cell)

	var eq_panel := PanelContainer.new()
	eq_panel.name = "InventoryEquipmentPanel"
	eq_panel.custom_minimum_size = Vector2(380, 0)
	eq_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eq_panel.add_theme_stylebox_override("panel", _host._clay_sb(Color("111827"), 6, 10, 8, 1, 0))
	shell.add_child(eq_panel)
	_inventory_equipment_panel_root = eq_panel

	var eq_box := VBoxContainer.new()
	eq_box.add_theme_constant_override("separation", 8)
	eq_panel.add_child(eq_box)
	var eq_header := HBoxContainer.new()
	eq_header.add_theme_constant_override("separation", 8)
	eq_box.add_child(eq_header)
	var eq_title := Label.new()
	eq_title.text = "Actor Equipment"
	eq_title.add_theme_font_override("font", _host._clay_font_bold())
	eq_title.add_theme_color_override("font_color", _host.CLAY_TEXT)
	eq_header.add_child(eq_title)
	_inventory_actor_label = Label.new()
	_inventory_actor_label.text = "Actor: -"
	_inventory_actor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_actor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inventory_actor_label.add_theme_color_override("font_color", _host.CLAY_TEXT_SOFT)
	eq_header.add_child(_inventory_actor_label)

	var eq_grid := GridContainer.new()
	eq_grid.name = "InventoryEquipmentGrid"
	eq_grid.columns = 3
	eq_grid.add_theme_constant_override("h_separation", INVENTORY_EQ_SLOT_GAP)
	eq_grid.add_theme_constant_override("v_separation", INVENTORY_EQ_SLOT_GAP)
	eq_box.add_child(eq_grid)

	_inventory_equipment_slots.clear()
	for slot_index in range(6):
		var slot := EquipmentSlotScript.new() as Control
		slot.name = "SkillPreviewEquipmentSlot_%d" % slot_index
		slot.custom_minimum_size = INVENTORY_EQ_SLOT_SIZE
		slot.size = INVENTORY_EQ_SLOT_SIZE
		slot.setup(self, slot_index)
		eq_grid.add_child(slot)
		_inventory_equipment_slots.append(slot)

	_inventory_status_label = Label.new()
	_inventory_status_label.name = "InventoryStatusLabel"
	_inventory_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_status_label.add_theme_color_override("font_color", _host.CLAY_TEXT_SOFT)
	_inventory_status_label.add_theme_font_size_override("font_size", 12)
	eq_box.add_child(_inventory_status_label)


# ========== Inventory UI / model bridge ==========

func _seed_inventory_items_once() -> void:
	if _inventory == null or _inventory_seeded:
		return
	var failed_seeds: Array = []
	for seed in INVENTORY_SEED_ITEMS:
		var config_id: StringName = seed.get("config_id", &"") as StringName
		var count := int(seed.get("count", 1))
		var slot_index := int(seed.get("slot", -1))
		var result := ItemSystem.create_item(_inventory.player_bag_id, config_id, count, slot_index)
		if not result.success:
			failed_seeds.append({"config_id": str(config_id), "error": result.error_message})
	_inventory_seeded = true
	if failed_seeds.is_empty():
		_set_inventory_op_result(true, "inventory seeded", "")
	else:
		_set_inventory_op_result(false, "inventory seed failed", JSON.stringify(failed_seeds))


func handle_drop(payload: Dictionary, target_container_id: int, target_slot_index: int) -> void:
	var item_id := int(payload.get("item_id", -1))
	if item_id <= 0:
		_set_inventory_op_result(false, "drop ignored: invalid payload", "invalid_drop_payload")
		return
	var result := ItemSystem.move_item(item_id, target_container_id, target_slot_index)
	if result.success:
		_set_inventory_op_result(true, "moved item %d to container %d slot %d" % [
			item_id, target_container_id, target_slot_index,
		], "")
	else:
		_set_inventory_op_result(false, "move FAILED: %s" % result.error_message, result.error_message)
	_refresh_inventory_all()


func _set_inventory_op_result(success: bool, message: String, error_text: String) -> void:
	_last_inventory_op_success = success
	_last_inventory_op_message = message
	_last_inventory_error = error_text
	if _inventory_status_label != null:
		_inventory_status_label.text = message


func _refresh_inventory_all() -> void:
	_refresh_inventory_bag()
	_refresh_inventory_equipment_panel()
	if _inventory_status_label != null:
		_inventory_status_label.text = _last_inventory_op_message


func _refresh_inventory_bag() -> void:
	if _inventory == null:
		return
	for cell in _inventory_bag_cells:
		cell.set_target_container_id(_inventory.player_bag_id)
		cell.set_item(0, {})
	for item_id in ItemSystem.get_items_in_container(_inventory.player_bag_id):
		var loc := ItemSystem.get_item_location(item_id)
		if loc == null or loc.slot_index < 0 or loc.slot_index >= _inventory_bag_cells.size():
			continue
		_inventory_bag_cells[loc.slot_index].set_item(item_id, ItemSystem.get_item_snapshot(item_id))


func _refresh_inventory_equipment_panel() -> void:
	if _inventory == null:
		return
	var actor_idx := _inventory_selected_actor_idx()
	if _inventory_actor_label != null:
		_inventory_actor_label.text = "Actor: %s" % (_host._actor_timeline_label(actor_idx) if actor_idx >= 0 else "-")
	var eq_id := _inventory_equipment_container_id_for_idx(actor_idx)
	for slot in _inventory_equipment_slots:
		slot.set_target_container_id(eq_id)
		slot.set_item(0, {})
	if eq_id <= 0:
		return
	for item_id in ItemSystem.get_items_in_container(eq_id):
		var loc := ItemSystem.get_item_location(item_id)
		if loc == null or loc.slot_index < 0 or loc.slot_index >= _inventory_equipment_slots.size():
			continue
		_inventory_equipment_slots[loc.slot_index].set_item(item_id, ItemSystem.get_item_snapshot(item_id))


func _inventory_selected_actor_idx() -> int:
	if _host._selected_kind == _host.SELECT_ACTOR and _host._selected_actor_idx >= 0 and _host._selected_actor_idx < _host._actors.size():
		return _host._selected_actor_idx
	if _host._selected_kind == _host.SELECT_KEYFRAME and _host._selected_spt_actor_idx >= 0 and _host._selected_spt_actor_idx < _host._actors.size():
		return _host._selected_spt_actor_idx
	if _host._selected_actor_idx >= 0 and _host._selected_actor_idx < _host._actors.size():
		return _host._selected_actor_idx
	return 0 if not _host._actors.is_empty() else -1


func _inventory_actor_id_for_idx(actor_idx: int) -> String:
	if actor_idx < 0 or actor_idx >= _host._actor_ids.size():
		return ""
	return _host._actor_ids[actor_idx]


func _inventory_equipment_container_id_for_idx(actor_idx: int) -> int:
	if _inventory == null:
		return -1
	var actor_id := _inventory_actor_id_for_idx(actor_idx)
	if actor_id == "":
		return -1
	return _inventory.get_equipment_container_id(actor_id)


func _snapshot_inventory_item(item_id: int) -> Dictionary:
	return ItemSystem.get_item_snapshot(item_id)


func _snapshot_inventory_slot(container_id: int, slot_index: int) -> Dictionary:
	var snap: Dictionary = {
		"slot_index": slot_index,
		"slot_label_1_based": slot_index + 1,
		"item_id": 0,
		"item_snapshot": {},
	}
	if container_id <= 0:
		return snap
	for item_id in ItemSystem.get_items_in_container(container_id):
		var loc := ItemSystem.get_item_location(item_id)
		if loc != null and loc.slot_index == slot_index:
			snap["item_id"] = item_id
			snap["item_snapshot"] = ItemSystem.get_item_snapshot(item_id)
			break
	return snap


func _rect_to_inventory_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
	}


func _connect_item_system_signals() -> void:
	if not ItemSystem.item_created.is_connected(_on_inventory_item_created):
		ItemSystem.item_created.connect(_on_inventory_item_created)
	if not ItemSystem.item_moved.is_connected(_on_inventory_item_moved):
		ItemSystem.item_moved.connect(_on_inventory_item_moved)
	if not ItemSystem.item_destroyed.is_connected(_on_inventory_item_destroyed):
		ItemSystem.item_destroyed.connect(_on_inventory_item_destroyed)


func _disconnect_item_system_signals() -> void:
	if ItemSystem.item_created.is_connected(_on_inventory_item_created):
		ItemSystem.item_created.disconnect(_on_inventory_item_created)
	if ItemSystem.item_moved.is_connected(_on_inventory_item_moved):
		ItemSystem.item_moved.disconnect(_on_inventory_item_moved)
	if ItemSystem.item_destroyed.is_connected(_on_inventory_item_destroyed):
		ItemSystem.item_destroyed.disconnect(_on_inventory_item_destroyed)


func _on_inventory_item_created(_item_id: int, _location: ItemLocation) -> void:
	_refresh_inventory_all()


func _on_inventory_item_moved(_item_id: int, _old_location: ItemLocation, _new_location: ItemLocation) -> void:
	_refresh_inventory_all()


func _on_inventory_item_destroyed(_item_id: int) -> void:
	_refresh_inventory_all()
