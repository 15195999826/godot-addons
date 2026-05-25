## ItemPreview - Hex Item System Sandbox 主场景
##
## Goal: 验证 ItemSystem + HexItemDomain + HexPlayerInventory 的 UI 端到端,
## 不接 SkillPreview / 不跑战斗 / 不动 hex frontend。
##
## 布局:
##   Left  Panel: PlayerBag (10x8 grid)
##   Right Panel: ActorSelector + 6 EquipmentSlot
##   Bottom: StatusLabel (展示最近一次 op 结果 / 错误)
##
## Drag/drop:
##   _get_drag_data → bag cell / equipment slot 持有 item 时返回 item_id
##   _can_drop_data → 总返回 true (实际允许 / 拒绝由 ItemSystem 决定;失败显示 error)
##   _drop_data → 调 ItemSystem.move_item(item_id, target_container_id, target_slot_index)
##                展示 ItemMoveResult.error_message 到 status label
##
## 数据流: UI 只通过 ItemSystem 业务 API 读写;监听 item_created / item_moved /
##   item_destroyed signal 触发 _refresh_*。不维护第二份 item 权威状态。
extends Control


const HexItemDomainScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_item_domain.gd")
const HexItemCatalogScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_item_catalog.gd")
const HexPlayerInventoryScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_player_inventory.gd")
const BagCellScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/item-preview/bag_cell.gd")
const EquipmentSlotScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/item-preview/equipment_slot.gd")
const ItemPreviewAgentOpsScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/item-preview/item_preview_agent_ops.gd")
const DevAgentBridgeScript := preload("res://addons/lomolib/dev_agent/dev_agent_bridge.gd")

const BAG_COLS := 10
const BAG_ROWS := 8
const BAG_CELL_SIZE := Vector2(64, 64)
const BAG_CELL_GAP := 4
const EQ_SLOT_SIZE := Vector2(96, 96)
const EQ_SLOT_GAP := 12
const SANDBOX_WINDOW_SIZE := Vector2i(1280, 800)

# 三个 sandbox actor 使用真实 CharacterActor, 并通过 GameplayInstance.add_actor()
# 分配 runtime actor_id。DevAgent / 测试只能用 selected_actor_idx 或 display_name
# 做匹配, 不要硬编 runtime id。
const SANDBOX_ACTOR_CLASSES: Array[HexBattleClassConfig.CharacterClass] = [
	HexBattleClassConfig.CharacterClass.WARRIOR,
	HexBattleClassConfig.CharacterClass.MAGE,
	HexBattleClassConfig.CharacterClass.ARCHER,
]


# ----- State -----------------------------------------------------------------

var _inventory: HexPlayerInventory
var _sandbox_world: GameplayInstance
var _sandbox_actors: Array[CharacterActor] = []
var _sandbox_actor_ids: Array[String] = []
var _sandbox_actor_names: Array[String] = []
var _selected_actor_idx: int = 0
var _bag_cells: Array[Control] = []  # bag_slot_index -> BagCell Panel
var _equipment_slots: Array[Control] = []  # 0..5 → EquipmentSlot Panel
var _last_op_message: String = ""
var _last_op_success: bool = true
var _last_error: String = ""

# UI nodes
var _bag_grid_root: Control
var _equipment_panel_root: Control
var _actor_selector: OptionButton
var _status_label: Label
var _dev_agent_bridge: Node = null


# ----- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	name = "ItemPreview"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# 在 headless 下 viewport 默认 64×64, Control 落 viewport 外, 拖拽用不了。
	# 显式 resize 到 sandbox 期望尺寸 — 编辑器下 window 已大,headless 才生效。
	var window := get_window()
	if window != null and window.size.x < SANDBOX_WINDOW_SIZE.x:
		window.size = SANDBOX_WINDOW_SIZE

	_setup_session()
	_build_ui()
	_seed_initial_items()
	_connect_item_system_signals()
	_refresh_all()
	_install_dev_agent()


## ItemPreview 自身作为 root Control 提供 _can_drop_data / _drop_data 兜底,
## 避免 drop 到 panel 之间空白区被 Godot drag/drop 静默 abort — DevAgent
## 测试时能看到明确的 "ignored" status, 而不是 drag 像没发生。
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("item_id")


func _drop_data(_pos: Vector2, _data: Variant) -> void:
	_set_op_result(false, "drop ignored: dropped on empty area (not a slot/cell)", "drop_on_empty_area")


func _exit_tree() -> void:
	_disconnect_item_system_signals()
	if _inventory != null:
		_inventory.dispose()
		_inventory = null
	_clear_sandbox_world()
	# _exit_tree 不 reset_session — dispose() 已清完本场景所有 containers/items。
	# ItemSystem autoload 的 _next_*_id counter 不会回滚,但数据层是干净的。
	# 其他场景 (Phase F 接入的 SkillPreview) 需要时自己 configure_domain 重置。


# ----- Public API (DevAgent adapter consumes) --------------------------------

func reset_sandbox() -> void:
	_disconnect_item_system_signals()
	if _inventory != null:
		_inventory.dispose()
		_inventory = null
	_clear_sandbox_world()
	ItemSystem.reset_session()
	_last_op_message = "reset_sandbox"
	_last_op_success = true
	_last_error = ""
	_selected_actor_idx = 0
	_setup_session()
	# Sanity: player_bag + actor 0 装备容器必须注册成功,否则后续 drag 会因
	# container_id<=0 静默失败 (move_item 报 "目标容器不存在")。
	Log.assert_crash(_inventory.player_bag_id > 0, "ItemPreview",
		"player_bag 未正确初始化 — sandbox lifecycle bug")
	Log.assert_crash(not _sandbox_actor_ids.is_empty(), "ItemPreview",
		"sandbox actors 未正确创建 — sandbox lifecycle bug")
	Log.assert_crash(_inventory.get_equipment_container_id(_sandbox_actor_ids[0]) > 0,
		"ItemPreview", "actor 0 equipment container 未正确注册 — sandbox lifecycle bug")
	_seed_initial_items()
	_connect_item_system_signals()
	if _actor_selector != null:
		_actor_selector.selected = 0
	_refresh_all()


func seed_items() -> void:
	# 即 reset 也清场, 一并重置 — DevAgent 使用 seed_items 当 "reset 到已知状态"。
	reset_sandbox()


func select_actor_by_idx(idx: int) -> bool:
	if idx < 0 or idx >= _sandbox_actor_ids.size():
		_set_op_result(false, "select_actor failed: invalid idx %d (valid 0..%d)" % [idx, _sandbox_actor_ids.size() - 1], "invalid_actor_idx")
		return false
	_selected_actor_idx = idx
	if _actor_selector != null:
		_actor_selector.selected = idx
	_refresh_equipment_panel()
	_set_op_result(true, "selected actor: %s" % _sandbox_actor_names[idx], "")
	return true


func get_inventory_state() -> Dictionary:
	if _inventory == null:
		return {
			"bag": [],
			"actors": [],
			"selected_actor_idx": -1,
			"last_op_message": _last_op_message,
			"last_op_success": _last_op_success,
			"last_error": _last_error,
		}

	var bag_items: Array = []
	for item_id in ItemSystem.get_items_in_container(_inventory.player_bag_id):
		bag_items.append(_snapshot_item(item_id))

	var actors_state: Array = []
	for i in range(_sandbox_actor_ids.size()):
		var actor_id: String = _sandbox_actor_ids[i]
		var eq_id := _inventory.get_equipment_container_id(actor_id)
		var slots: Array = []
		for slot_idx in range(6):
			slots.append(_snapshot_slot(eq_id, slot_idx))
		actors_state.append({
			"actor_id": actor_id,
			"display_name": _sandbox_actor_names[i],
			"equipment_container_id": eq_id,
			"slots": slots,
		})

	return {
		"player_bag_id": _inventory.player_bag_id,
		"bag": bag_items,
		"actors": actors_state,
		"selected_actor_idx": _selected_actor_idx,
		"selected_actor_id": _sandbox_actor_ids[_selected_actor_idx] if _selected_actor_idx < _sandbox_actor_ids.size() else "",
		"last_op_message": _last_op_message,
		"last_op_success": _last_op_success,
		"last_error": _last_error,
	}


## Phase D adapter 转发: 当前 selected actor 的 6 slot 状态。Phase E "切 actor
## 验证装备隔离" step 直接读这个字段更稳, 不必每次解全 inventory_state.actors[i]。
## 同时携带 last_op_* 字段, 让 success-path 的 select_actor 响应也能直接断言
## last_op_success (不必跟一个额外 inventory_state op)。
func get_selected_actor_state() -> Dictionary:
	var common := {
		"last_op_message": _last_op_message,
		"last_op_success": _last_op_success,
		"last_error": _last_error,
	}
	if _inventory == null:
		return common
	if _selected_actor_idx < 0 or _selected_actor_idx >= _sandbox_actor_ids.size():
		return common
	var aid: String = _sandbox_actor_ids[_selected_actor_idx]
	var eq_id := _inventory.get_equipment_container_id(aid)
	var slots: Array = []
	for slot_idx in range(6):
		slots.append(_snapshot_slot(eq_id, slot_idx))
	return {
		"actor_id": aid,
		"display_name": _sandbox_actor_names[_selected_actor_idx],
		"equipment_container_id": eq_id,
		"slots": slots,
		"selected_actor_idx": _selected_actor_idx,
		"last_op_message": _last_op_message,
		"last_op_success": _last_op_success,
		"last_error": _last_error,
	}


func get_layout_state() -> Dictionary:
	var data: Dictionary = {}
	data["window_size"] = {"x": int(get_window().size.x), "y": int(get_window().size.y)} if get_window() != null else {}

	if _bag_grid_root != null:
		data["bag_grid_rect"] = _rect_to_dict(_bag_grid_root.get_global_rect())
		var bag_cells: Array = []
		for cell in _bag_cells:
			bag_cells.append({
				"slot_index": int(cell.get_meta("slot_index", -1)),
				"rect": _rect_to_dict(cell.get_global_rect()),
			})
		data["bag_cells"] = bag_cells

	if _equipment_panel_root != null:
		data["equipment_panel_rect"] = _rect_to_dict(_equipment_panel_root.get_global_rect())
		var eq_slots: Array = []
		for slot in _equipment_slots:
			eq_slots.append({
				"slot_index": int(slot.get_meta("slot_index", -1)),
				"slot_label_1_based": int(slot.get_meta("slot_index", -1)) + 1,
				"rect": _rect_to_dict(slot.get_global_rect()),
			})
		data["equipment_slots"] = eq_slots

	if _actor_selector != null:
		data["actor_selector_rect"] = _rect_to_dict(_actor_selector.get_global_rect())
	if _status_label != null:
		data["status_label_rect"] = _rect_to_dict(_status_label.get_global_rect())

	return data


## 由 BagCell / EquipmentSlot 在 _drop_data 中调用。
## payload = {"item_id": int, "source_container_id": int, "source_slot_index": int}
## target_container_id / target_slot_index 来自 drop target。
func handle_drop(payload: Dictionary, target_container_id: int, target_slot_index: int) -> void:
	var item_id := int(payload.get("item_id", -1))
	if item_id < 0:
		_set_op_result(false, "drop ignored: invalid payload", "invalid_drop_payload")
		return

	var result := ItemSystem.move_item(item_id, target_container_id, target_slot_index)
	if result.success:
		_set_op_result(true, "moved item %d to container %d slot %d" % [item_id, target_container_id, target_slot_index], "")
	else:
		_set_op_result(false, "move FAILED: %s" % result.error_message, result.error_message)


# ----- Internals -------------------------------------------------------------

func _setup_session() -> void:
	ItemSystem.reset_session()
	_clear_sandbox_world()
	ItemSystem.configure_domain(HexItemDomainScript.new(), HexItemCatalogScript.new())
	_inventory = HexPlayerInventoryScript.new()
	_inventory.init_inventory()
	_sandbox_world = GameplayInstance.new(IdGenerator.generate("item_preview_sandbox"))
	for i in range(SANDBOX_ACTOR_CLASSES.size()):
		var char_class: HexBattleClassConfig.CharacterClass = SANDBOX_ACTOR_CLASSES[i]
		var actor := CharacterActor.new(char_class)
		actor.set_team_id(0)
		var added := _sandbox_world.add_actor(actor) as CharacterActor
		Log.assert_crash(added != null and ActorId.is_valid(added.get_id()), "ItemPreview",
			"sandbox CharacterActor add_actor failed")
		var display_name := "Actor %d (%s)" % [i + 1, HexBattleClassConfig.class_to_string(char_class)]
		_sandbox_actors.append(added)
		_sandbox_actor_ids.append(added.get_id())
		_sandbox_actor_names.append(display_name)
		_inventory.register_actor(added.get_id())


func _clear_sandbox_world() -> void:
	_sandbox_world = null
	_sandbox_actors.clear()
	_sandbox_actor_ids.clear()
	_sandbox_actor_names.clear()


func _seed_initial_items() -> void:
	# 给 bag 灌一些样例 item, 覆盖 equipable / non-equipable / stackable
	# (Plan §"Item Catalog" 最小样例);ItemCreateResult 失败时输出日志但继续。
	var seeds: Array = [
		{"config_id": &"training_sword", "count": 1, "slot": 0},
		{"config_id": &"frost_orb", "count": 1, "slot": 1},
		{"config_id": &"minor_rune", "count": 5, "slot": 2},
		{"config_id": &"broken_stone", "count": 10, "slot": 3},
		{"config_id": &"training_sword", "count": 1, "slot": 10},  # 第二行
	]
	var failed_seeds: Array = []
	for s in seeds:
		var r := ItemSystem.create_item(_inventory.player_bag_id, s.config_id, s.count, s.slot)
		if not r.success:
			Log.warning("ItemPreview", "seed 失败 %s: %s" % [str(s.config_id), r.error_message])
			failed_seeds.append({"config": str(s.config_id), "error": r.error_message})

	if not failed_seeds.is_empty():
		_set_op_result(false, "seed: %d/%d items failed (see last_error)" % [failed_seeds.size(), seeds.size()],
			"seed_failures: %s" % JSON.stringify(failed_seeds))


# ----- UI construction -------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.09, 0.10)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Hex Item Preview Sandbox"
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	add_child(title)

	_build_bag_grid()
	_build_equipment_panel()
	_build_status_label()


func _build_bag_grid() -> void:
	var bag_root := Panel.new()
	bag_root.name = "BagPanel"
	bag_root.position = Vector2(24, 60)
	bag_root.size = Vector2(
		BAG_COLS * BAG_CELL_SIZE.x + (BAG_COLS - 1) * BAG_CELL_GAP + 24,
		BAG_ROWS * BAG_CELL_SIZE.y + (BAG_ROWS - 1) * BAG_CELL_GAP + 60
	)
	add_child(bag_root)
	_bag_grid_root = bag_root

	var bag_header := Label.new()
	bag_header.name = "BagHeader"
	bag_header.text = "Player Bag"
	bag_header.position = Vector2(12, 8)
	bag_header.add_theme_font_size_override("font_size", 16)
	bag_root.add_child(bag_header)

	_bag_cells.clear()
	for row in range(BAG_ROWS):
		for col in range(BAG_COLS):
			var slot_index := row * BAG_COLS + col
			var cell := BagCellScript.new() as Control
			cell.name = "BagCell_%d" % slot_index
			cell.position = Vector2(
				12 + col * (BAG_CELL_SIZE.x + BAG_CELL_GAP),
				40 + row * (BAG_CELL_SIZE.y + BAG_CELL_GAP)
			)
			cell.size = BAG_CELL_SIZE
			cell.setup(self, _inventory.player_bag_id, slot_index)
			bag_root.add_child(cell)
			_bag_cells.append(cell)


func _build_equipment_panel() -> void:
	var eq_root := Panel.new()
	eq_root.name = "EquipmentPanel"
	eq_root.position = Vector2(_bag_grid_root.position.x + _bag_grid_root.size.x + 32, 60)
	eq_root.size = Vector2(
		3 * EQ_SLOT_SIZE.x + 2 * EQ_SLOT_GAP + 24,
		2 * EQ_SLOT_SIZE.y + EQ_SLOT_GAP + 100
	)
	add_child(eq_root)
	_equipment_panel_root = eq_root

	var eq_header := Label.new()
	eq_header.name = "EquipmentHeader"
	eq_header.text = "Actor Equipment"
	eq_header.position = Vector2(12, 8)
	eq_header.add_theme_font_size_override("font_size", 16)
	eq_root.add_child(eq_header)

	# Actor selector
	_actor_selector = OptionButton.new()
	_actor_selector.name = "ActorSelector"
	_actor_selector.position = Vector2(12, 36)
	_actor_selector.size = Vector2(eq_root.size.x - 24, 36)
	for i in range(_sandbox_actor_ids.size()):
		_actor_selector.add_item(_sandbox_actor_names[i], i)
	_actor_selector.selected = 0
	_actor_selector.item_selected.connect(_on_actor_selector_changed)
	eq_root.add_child(_actor_selector)

	# 6 fixed equipment slots, 2 rows × 3 cols, label 1..6
	_equipment_slots.clear()
	for i in range(6):
		var row := i / 3
		var col := i % 3
		var slot := EquipmentSlotScript.new() as Control
		slot.name = "EquipmentSlot_%d" % i
		slot.position = Vector2(
			12 + col * (EQ_SLOT_SIZE.x + EQ_SLOT_GAP),
			84 + row * (EQ_SLOT_SIZE.y + EQ_SLOT_GAP)
		)
		slot.size = EQ_SLOT_SIZE
		slot.setup(self, i)  # container_id 在 select_actor 时 set
		eq_root.add_child(slot)
		_equipment_slots.append(slot)


func _build_status_label() -> void:
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	var bag_bottom: float = _bag_grid_root.position.y + _bag_grid_root.size.y
	var eq_bottom: float = _equipment_panel_root.position.y + _equipment_panel_root.size.y
	_status_label.position = Vector2(24, max(bag_bottom, eq_bottom) + 16)
	_status_label.size = Vector2(get_viewport_rect().size.x - 48, 60)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.92))
	_status_label.text = "ready"
	add_child(_status_label)


# ----- Refresh / signals -----------------------------------------------------

func _connect_item_system_signals() -> void:
	ItemSystem.item_created.connect(_on_any_item_change)
	ItemSystem.item_moved.connect(_on_any_item_change_2)
	ItemSystem.item_destroyed.connect(_on_item_destroyed)


func _disconnect_item_system_signals() -> void:
	if ItemSystem.item_created.is_connected(_on_any_item_change):
		ItemSystem.item_created.disconnect(_on_any_item_change)
	if ItemSystem.item_moved.is_connected(_on_any_item_change_2):
		ItemSystem.item_moved.disconnect(_on_any_item_change_2)
	if ItemSystem.item_destroyed.is_connected(_on_item_destroyed):
		ItemSystem.item_destroyed.disconnect(_on_item_destroyed)


func _on_any_item_change(_item_id: int, _loc: ItemLocation) -> void:
	_refresh_all()


func _on_any_item_change_2(_item_id: int, _old: ItemLocation, _new: ItemLocation) -> void:
	_refresh_all()


func _on_item_destroyed(_item_id: int) -> void:
	_refresh_all()


func _refresh_all() -> void:
	_refresh_bag()
	_refresh_equipment_panel()


func _refresh_bag() -> void:
	if _inventory == null:
		return
	var bag_id := _inventory.player_bag_id
	# 先清空全部 cell + rebind 到当前 player_bag_id (reset_sandbox 会换 container)
	for cell in _bag_cells:
		cell.set_target_container_id(bag_id)
		cell.set_item(0, {})
	# 再把当前 bag 中的 item 填进去
	for item_id in ItemSystem.get_items_in_container(bag_id):
		var loc := ItemSystem.get_item_location(item_id)
		if loc == null or loc.slot_index < 0 or loc.slot_index >= _bag_cells.size():
			continue
		_bag_cells[loc.slot_index].set_item(item_id, ItemSystem.get_item_snapshot(item_id))


func _refresh_equipment_panel() -> void:
	if _inventory == null:
		return
	if _selected_actor_idx < 0 or _selected_actor_idx >= _sandbox_actor_ids.size():
		# defensive: 越界时把所有 slot 清空, 避免 IndexError
		for slot in _equipment_slots:
			slot.set_target_container_id(-1)
			slot.set_item(0, {})
		return
	var actor_id: String = _sandbox_actor_ids[_selected_actor_idx]
	var eq_id := _inventory.get_equipment_container_id(actor_id)
	# 设置每个 slot 的 target container_id, 清空 item, 再填充
	for i in range(_equipment_slots.size()):
		var slot: Control = _equipment_slots[i]
		slot.set_target_container_id(eq_id)
		slot.set_item(0, {})
	for item_id in ItemSystem.get_items_in_container(eq_id):
		var loc := ItemSystem.get_item_location(item_id)
		if loc == null or loc.slot_index < 0 or loc.slot_index >= _equipment_slots.size():
			continue
		_equipment_slots[loc.slot_index].set_item(item_id, ItemSystem.get_item_snapshot(item_id))


func _on_actor_selector_changed(idx: int) -> void:
	if idx < 0 or idx >= _sandbox_actor_ids.size():
		_set_op_result(false, "actor selector got invalid idx %d" % idx, "invalid_actor_idx")
		return
	_selected_actor_idx = idx
	_refresh_equipment_panel()
	_set_op_result(true, "selected actor: %s" % _sandbox_actor_names[idx], "")


## DevAgent 接入: 仅在 `--dev-agent` cmdline arg 时启用 (bridge 自检)。
## adapter (ItemPreviewAgentOps) 作为本 Control 的 child, bridge 通过 scene_ops_path
## 指向它。
func _install_dev_agent() -> void:
	var ops := ItemPreviewAgentOpsScript.new() as Node
	ops.name = "ItemPreviewAgentOps"
	add_child(ops)

	_dev_agent_bridge = DevAgentBridgeScript.new()
	_dev_agent_bridge.name = "DevAgentBridge"
	_dev_agent_bridge.scene_ops_path = NodePath("../ItemPreviewAgentOps")
	add_child(_dev_agent_bridge)
	call_deferred("_print_dev_agent_paths")


func _print_dev_agent_paths() -> void:
	if _dev_agent_bridge == null:
		return
	var info: Dictionary = _dev_agent_bridge.get_session_info() as Dictionary
	if String(info.get("session_id", "")).is_empty():
		# DevAgent not enabled
		return
	print("[ItemPreview] inbox: %s" % str(info.get("inbox_global", "")))
	print("[ItemPreview] outbox: %s" % str(info.get("outbox_global", "")))
	print("[ItemPreview] session_dir: %s" % str(info.get("session_dir_global", "")))


## 统一记 status + last_op_success + last_error。
## error_text 为空表示成功;非空表示失败。
func _set_op_result(success: bool, msg: String, error_text: String) -> void:
	_last_op_message = msg
	_last_op_success = success
	_last_error = error_text
	if _status_label != null:
		_status_label.text = msg


## 仅更新 status label 文案 (informational, 不影响 last_op_success)
func _set_status(msg: String) -> void:
	_last_op_message = msg
	if _status_label != null:
		_status_label.text = msg


# ----- Helpers ---------------------------------------------------------------

func _snapshot_item(item_id: int) -> Dictionary:
	return ItemSystem.get_item_snapshot(item_id)


func _snapshot_slot(container_id: int, slot_index: int) -> Dictionary:
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


func _rect_to_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
	}
