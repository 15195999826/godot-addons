## Smoke: SkillPreview Phase F inventory integration
##
## 覆盖:
## - skill_preview.tscn boot 后配置 Hex item domain/catalog + preview-local bag
## - 每个 SkillPreview scene actor 使用真实 runtime actor_id 绑定 equipment container
## - bag -> equipment / occupied reject / non-equipable reject / equipment -> bag
## - add/remove actor 同步创建/清理 equipment container, remove 会卸回 bag
## - reset_world_to_model 保留 player bag + items, 清旧 actor containers, 重建新 actor containers
## - start/reset battle 后 inventory state 仍一致
extends Node


const SKILL_PREVIEW_SCENE := preload("res://addons/logic-game-framework/example/hex-atb-battle/skill-preview/skill_preview.tscn")


var _preview: Node = null


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: SkillPreview inventory integration ===")

	_preview = SKILL_PREVIEW_SCENE.instantiate()
	if _preview == null:
		_fail("skill_preview.tscn instantiate failed")
		return
	add_child(_preview)
	await get_tree().process_frame
	await get_tree().process_frame

	if not _phase_boot_contract():
		return
	var drag_drop_ok := await _phase_drag_drop_contract()
	if not drag_drop_ok:
		return
	var add_remove_ok := await _phase_add_remove_actor_lifecycle()
	if not add_remove_ok:
		return
	var reset_ok := await _phase_reset_keeps_player_bag()
	if not reset_ok:
		return
	var start_reset_ok := await _phase_start_reset_consistency()
	if not start_reset_ok:
		return

	_pass("SkillPreview inventory lifecycle + UI contract OK")


func _phase_boot_contract() -> bool:
	if not (ItemSystem.get_domain() is HexItemDomain):
		return _fail("ItemSystem domain should be HexItemDomain")
	if not (ItemSystem.get_catalog() is HexItemCatalog):
		return _fail("ItemSystem catalog should be HexItemCatalog")

	var state: Dictionary = _preview.dev_agent_inventory_state()
	var bag: Array = state.get("bag", []) as Array
	if bag.size() < 5:
		return _fail("boot seed bag should contain >=5 items, got %d" % bag.size())
	var actors: Array = state.get("actors", []) as Array
	if actors.size() < 2:
		return _fail("boot should expose at least caster + target actor, got %d" % actors.size())
	for actor_state_v in actors:
		var actor_state := actor_state_v as Dictionary
		var actor_id := str(actor_state.get("actor_id", ""))
		if not ActorId.is_valid(actor_id):
			return _fail("actor_id should be runtime ActorId, got %s" % actor_id)
		var eq_id := int(actor_state.get("equipment_container_id", -1))
		if eq_id <= 0 or ItemSystem.get_container(eq_id) == null:
			return _fail("actor %s missing equipment container: %d" % [actor_id, eq_id])
		var slots: Array = actor_state.get("slots", []) as Array
		if slots.size() != 6:
			return _fail("actor %s equipment slots should be 6, got %d" % [actor_id, slots.size()])

	var layout: Dictionary = _preview.dev_agent_inventory_layout_state()
	if (layout.get("bag_cells", []) as Array).size() != 80:
		return _fail("inventory_layout_state.bag_cells should be 80")
	if (layout.get("equipment_slots", []) as Array).size() != 6:
		return _fail("inventory_layout_state.equipment_slots should be 6")
	return true


func _phase_drag_drop_contract() -> bool:
	var state: Dictionary = _preview.dev_agent_inventory_state()
	var bag_id := int(state.get("player_bag_id", -1))
	var actor0: Dictionary = (state.get("actors", []) as Array)[0] as Dictionary
	var eq0 := int(actor0.get("equipment_container_id", -1))

	var sword_id := _find_bag_item(state, &"training_sword", 0)
	var orb_id := _find_bag_item(state, &"frost_orb", 1)
	var stone_id := _find_bag_item(state, &"broken_stone", 3)
	if sword_id <= 0 or orb_id <= 0 or stone_id <= 0:
		return _fail("missing expected seed items sword=%d orb=%d stone=%d" % [sword_id, orb_id, stone_id])

	_preview.handle_drop({"item_id": sword_id}, eq0, 0)
	await get_tree().process_frame
	state = _preview.dev_agent_inventory_state()
	if not bool(state.get("last_op_success", false)):
		return _fail("equip sword should succeed: %s" % str(state.get("last_error", "")))
	if int(_slot_at(state, 0, 0).get("item_id", 0)) != sword_id:
		return _fail("slot 1 should contain sword after equip")

	_preview.handle_drop({"item_id": orb_id}, eq0, 0)
	await get_tree().process_frame
	state = _preview.dev_agent_inventory_state()
	if bool(state.get("last_op_success", true)):
		return _fail("occupied equipment slot should reject orb")
	if ItemSystem.get_item_location(orb_id).container_id != bag_id:
		return _fail("occupied reject should keep orb in bag")

	_preview.handle_drop({"item_id": stone_id}, eq0, 1)
	await get_tree().process_frame
	state = _preview.dev_agent_inventory_state()
	if bool(state.get("last_op_success", true)):
		return _fail("non-equipable stone should be rejected")
	if ItemSystem.get_item_location(stone_id).container_id != bag_id:
		return _fail("non-equipable reject should keep stone in bag")

	var selected: Dictionary = _preview.dev_agent_select_actor(1)
	if not bool(selected.get("ok", false)):
		return _fail("select actor 1 failed: %s" % str(selected.get("message", "")))
	var selected_state: Dictionary = _preview.dev_agent_selected_actor_equipment_state()
	for slot_v in selected_state.get("slots", []) as Array:
		if int((slot_v as Dictionary).get("item_id", 0)) != 0:
			return _fail("actor 1 should have empty equipment before equip")

	_preview.dev_agent_select_actor(0)
	_preview.handle_drop({"item_id": sword_id}, bag_id, 4)
	await get_tree().process_frame
	state = _preview.dev_agent_inventory_state()
	if not bool(state.get("last_op_success", false)):
		return _fail("equipment -> bag should succeed: %s" % str(state.get("last_error", "")))
	var sword_loc := ItemSystem.get_item_location(sword_id)
	if sword_loc.container_id != bag_id:
		return _fail("sword should be back in player bag, loc=%s" % str(sword_loc))
	return true


func _phase_add_remove_actor_lifecycle() -> bool:
	var before: Dictionary = _preview.dev_agent_inventory_state()
	var before_count := (before.get("actors", []) as Array).size()
	var add_res: Dictionary = _preview.dev_agent_add_actor_team("B")
	if not bool(add_res.get("ok", false)):
		return _fail("add actor failed: %s" % str(add_res.get("message", "")))
	var after_add: Dictionary = _preview.dev_agent_inventory_state()
	var actors: Array = after_add.get("actors", []) as Array
	if actors.size() != before_count + 1:
		return _fail("add actor should add one inventory actor, before=%d after=%d" % [before_count, actors.size()])

	var new_actor: Dictionary = actors[actors.size() - 1] as Dictionary
	var new_eq_id := int(new_actor.get("equipment_container_id", -1))
	if new_eq_id <= 0 or ItemSystem.get_container(new_eq_id) == null:
		return _fail("new actor equipment container missing")

	var sword_id := _find_bag_item(after_add, &"training_sword", 4)
	if sword_id <= 0:
		return _fail("no sword left in bag for add/remove lifecycle")
	_preview.handle_drop({"item_id": sword_id}, new_eq_id, 0)
	await get_tree().process_frame
	if ItemSystem.get_item_location(sword_id).container_id != new_eq_id:
		return _fail("sword should be equipped on newly added actor")

	var remove_idx := actors.size() - 1
	var remove_res: Dictionary = _preview.dev_agent_remove_actor(remove_idx)
	if not bool(remove_res.get("ok", false)):
		return _fail("remove actor failed: %s" % str(remove_res.get("message", "")))
	var after_remove: Dictionary = _preview.dev_agent_inventory_state()
	if (after_remove.get("actors", []) as Array).size() != before_count:
		return _fail("remove actor should restore actor count to %d" % before_count)
	if ItemSystem.get_container(new_eq_id) != null:
		return _fail("removed actor equipment container should be unregistered")
	var loc := ItemSystem.get_item_location(sword_id)
	if loc == null or loc.container_id != int(after_remove.get("player_bag_id", -1)):
		return _fail("removed actor equipment item should be unloaded to bag, loc=%s" % str(loc))
	return true


func _phase_reset_keeps_player_bag() -> bool:
	var before: Dictionary = _preview.dev_agent_inventory_state()
	var bag_id := int(before.get("player_bag_id", -1))
	var sword_id := _find_bag_item(before, &"training_sword", 0)
	var actor0: Dictionary = (before.get("actors", []) as Array)[0] as Dictionary
	var old_actor_id := str(actor0.get("actor_id", ""))
	var old_eq_id := int(actor0.get("equipment_container_id", -1))
	_preview.handle_drop({"item_id": sword_id}, old_eq_id, 0)
	await get_tree().process_frame
	if ItemSystem.get_item_location(sword_id).container_id != old_eq_id:
		return _fail("setup for reset: sword should be equipped before reset")

	var reset_res: Dictionary = _preview.dev_agent_reset_world_to_model()
	if not bool(reset_res.get("ok", false)):
		return _fail("reset_world_to_model failed: %s" % str(reset_res.get("message", "")))
	await get_tree().process_frame
	var after: Dictionary = _preview.dev_agent_inventory_state()
	if int(after.get("player_bag_id", -1)) != bag_id:
		return _fail("reset should keep same player bag id")
	if ItemSystem.get_item_location(sword_id).container_id != bag_id:
		return _fail("reset should unload equipped sword back to player bag")
	if ItemSystem.get_container(old_eq_id) != null:
		return _fail("reset should unregister old equipment container")
	var new_actor0: Dictionary = (after.get("actors", []) as Array)[0] as Dictionary
	var new_actor_id := str(new_actor0.get("actor_id", ""))
	if not ActorId.is_valid(new_actor_id):
		return _fail("reset actor id should be runtime ActorId")
	if new_actor_id == old_actor_id:
		return _fail("reset should rebuild scene actors with new runtime ids")
	var new_eq_id := int(new_actor0.get("equipment_container_id", -1))
	if new_eq_id <= 0 or new_eq_id == old_eq_id or ItemSystem.get_container(new_eq_id) == null:
		return _fail("reset should create a new actor equipment container")
	return true


func _phase_start_reset_consistency() -> bool:
	var start_res: Dictionary = _preview.dev_agent_start_battle()
	if not bool(start_res.get("ok", false)):
		return _fail("start_battle failed: %s" % str(start_res.get("message", "")))
	var waited := 0
	while waited < 240 and _preview.dev_agent_is_playing():
		await get_tree().process_frame
		waited += 1
	if _preview.dev_agent_is_playing():
		return _fail("battle playback did not become idle after %d frames" % waited)
	var reset_res: Dictionary = _preview.dev_agent_reset_battle()
	if not bool(reset_res.get("ok", false)):
		return _fail("reset_battle failed: %s" % str(reset_res.get("message", "")))
	await get_tree().process_frame
	var after: Dictionary = _preview.dev_agent_inventory_state()
	if (after.get("bag", []) as Array).size() < 5:
		return _fail("after start/reset, player bag should still contain seeded items")
	for actor_state_v in after.get("actors", []) as Array:
		var actor_state := actor_state_v as Dictionary
		var eq_id := int(actor_state.get("equipment_container_id", -1))
		if eq_id <= 0 or ItemSystem.get_container(eq_id) == null:
			return _fail("after start/reset, actor equipment container missing")
	return true


func _find_bag_item(state: Dictionary, config_id: StringName, slot_index: int) -> int:
	for item_v in state.get("bag", []) as Array:
		var item := item_v as Dictionary
		if StringName(item.get("config_id", &"")) == config_id \
				and int(item.get("slot_index", -1)) == slot_index:
			return int(item.get("item_id", 0))
	return 0


func _slot_at(state: Dictionary, actor_idx: int, slot_idx: int) -> Dictionary:
	var actors: Array = state.get("actors", []) as Array
	if actor_idx < 0 or actor_idx >= actors.size():
		return {}
	var actor := actors[actor_idx] as Dictionary
	var slots: Array = actor.get("slots", []) as Array
	if slot_idx < 0 or slot_idx >= slots.size():
		return {}
	return slots[slot_idx] as Dictionary


func _pass(reason: String) -> void:
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> bool:
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
	return false
