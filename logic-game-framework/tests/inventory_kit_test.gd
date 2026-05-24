extends Node

## InventoryKit business / domain / catalog contract tests.
## 覆盖: create_item / move_item / destroy_item / register_item_instance /
## same-container move callback / item_moved_in target_slot_index / reset_session /
## DefaultItemDomain + EmptyItemCatalog fail-fast / domain hook 顺序。
##
## 这些 test 跑前都先 reset_session(), 跑后也 reset_session(), 避免与其他 test
## 套件共享 ItemSystem autoload 状态。

const ITEM_SWORD := &"test_sword"
const ITEM_RUNE := &"test_rune"
const ITEM_STONE := &"test_stone"


class TestCatalog extends ItemCatalog:
	var _configs: Dictionary = {}

	func _init() -> void:
		_configs[ITEM_SWORD] = {
			"id": ITEM_SWORD,
			"display_name": "Test Sword",
			"max_stack": 1,
			"equipable": true,
			"item_tags": [&"equipment"],
		}
		_configs[ITEM_RUNE] = {
			"id": ITEM_RUNE,
			"display_name": "Test Rune",
			"max_stack": 9,
			"equipable": true,
			"item_tags": [&"equipment", &"rune"],
		}
		_configs[ITEM_STONE] = {
			"id": ITEM_STONE,
			"display_name": "Test Stone",
			"max_stack": 99,
			"equipable": false,
			"item_tags": [&"material"],
		}

	func has_config(config_id: StringName) -> bool:
		return _configs.has(config_id)

	func get_config(config_id: StringName) -> Dictionary:
		return _configs.get(config_id, {}).duplicate()

	func list_config_ids() -> Array[StringName]:
		var arr: Array[StringName] = []
		for k in _configs.keys():
			arr.append(k)
		return arr


class TestDomain extends ItemDomain:
	var on_created_calls: Array[int] = []
	var on_moved_calls: Array[Dictionary] = []
	var on_destroyed_calls: Array[int] = []
	var can_create_block_ids: Array[StringName] = []
	var can_move_block_pairs: Array = []  # [item_id, target_container_id]

	func can_stack(_existing_item_id: int, _config_id: StringName) -> bool:
		return true

	func merge_stack(existing_data: ItemInstanceData, incoming_count: int, max_stack: int) -> int:
		var room := max(0, max_stack - existing_data.count)
		var to_merge := min(incoming_count, room)
		existing_data.count += to_merge
		return incoming_count - to_merge

	func can_create_item(config_id: StringName, _container_id: int, _slot_index: int, _count: int) -> ContainerResult:
		if can_create_block_ids.has(config_id):
			return ContainerResult.fail("blocked by test: %s" % str(config_id))
		return ContainerResult.ok(true)

	func can_move_item(item_id: int, target_container_id: int, _target_slot_index: int) -> ContainerResult:
		for pair in can_move_block_pairs:
			if pair[0] == item_id and pair[1] == target_container_id:
				return ContainerResult.fail("blocked move by test")
		return ContainerResult.ok(true)

	func on_item_created(item_id: int, _data: ItemInstanceData) -> void:
		on_created_calls.append(item_id)

	func on_item_moved(item_id: int, old_location: ItemLocation, new_location: ItemLocation) -> void:
		on_moved_calls.append({
			"item_id": item_id,
			"old_container": old_location.container_id,
			"old_slot": old_location.slot_index,
			"new_container": new_location.container_id,
			"new_slot": new_location.slot_index,
		})

	func on_item_destroyed(item_id: int, _data: ItemInstanceData) -> void:
		on_destroyed_calls.append(item_id)


func _init() -> void:
	TestFramework.register_test("ItemSystem reset_session clears containers and data", _test_reset_session)
	TestFramework.register_test("register_item_instance bypasses domain/catalog", _test_register_item_instance_low_level)
	TestFramework.register_test("create_item fails when catalog missing config", _test_create_item_catalog_missing)
	TestFramework.register_test("create_item fails when domain rejects", _test_create_item_domain_reject)
	TestFramework.register_test("create_item single non-stackable success", _test_create_item_single)
	TestFramework.register_test("create_item stack merge respects max_stack", _test_create_item_stack_merge)
	TestFramework.register_test("create_item callback / signal order", _test_create_item_callback_order)
	TestFramework.register_test("move_item across containers updates location", _test_move_item_across)
	TestFramework.register_test("move_item to occupied fixed slot fails", _test_move_item_occupied_slot)
	TestFramework.register_test("move_item rejected by domain returns error", _test_move_item_domain_reject)
	TestFramework.register_test("move_item within container fires on_item_moved", _test_move_item_within)
	TestFramework.register_test("item_moved_in signal carries target_slot_index", _test_item_moved_in_signal)
	TestFramework.register_test("destroy_item clears data + container state", _test_destroy_item)
	TestFramework.register_test("get_item_snapshot merges catalog + domain", _test_get_item_snapshot)
	TestFramework.register_test("unregister_container destroys contained items", _test_unregister_container_destroys_items)


# ----- helpers ---------------------------------------------------------------

func _setup() -> Dictionary:
	ItemSystem.reset_session()
	var catalog := TestCatalog.new()
	var domain := TestDomain.new()
	ItemSystem.configure_domain(domain, catalog)

	var bag := BaseContainer.create_grid(&"TestBag", 4, 4)
	var bag_id := ItemSystem.register_container(bag)

	var equip := BaseContainer.create_fixed(&"TestEquip", [&"slot1", &"slot2", &"slot3", &"slot4"])
	var equip_id := ItemSystem.register_container(equip)

	return {
		"catalog": catalog,
		"domain": domain,
		"bag": bag,
		"bag_id": bag_id,
		"equip": equip,
		"equip_id": equip_id,
	}


func _teardown() -> void:
	ItemSystem.reset_session()


# ----- tests -----------------------------------------------------------------

func _test_reset_session() -> void:
	var ctx := _setup()
	var bag_id: int = ctx.bag_id

	var r := ItemSystem.create_item(bag_id, ITEM_SWORD, 1)
	TestFramework.assert_true(r.success, "create_item should succeed")
	TestFramework.assert_equal(1, r.created_item_ids.size())
	var item_id: int = r.created_item_ids[0]
	TestFramework.assert_true(ItemSystem.item_exists(item_id))

	ItemSystem.reset_session()

	TestFramework.assert_false(ItemSystem.item_exists(item_id), "item should be gone after reset_session")
	TestFramework.assert_equal(null, ItemSystem.get_item_data(item_id))
	TestFramework.assert_equal(null, ItemSystem.get_container(bag_id))
	# Default domain restored
	TestFramework.assert_true(ItemSystem.get_domain() is DefaultItemDomain)
	TestFramework.assert_true(ItemSystem.get_catalog() is EmptyItemCatalog)
	_teardown()


func _test_register_item_instance_low_level() -> void:
	ItemSystem.reset_session()
	var bag := BaseContainer.create_grid(&"LowBag", 2, 2)
	var bag_id := ItemSystem.register_container(bag)

	# 默认 DefaultItemDomain + EmptyItemCatalog: business create_item 必失败
	var biz_result := ItemSystem.create_item(bag_id, &"unknown", 1)
	TestFramework.assert_false(biz_result.success, "create_item must fail when catalog empty")
	TestFramework.assert_true("config_id" in biz_result.error_message)

	# 但底层 register_item_instance 仍可用
	var item_id := ItemSystem.register_item_instance(bag_id, -1, &"raw_type")
	TestFramework.assert_true(item_id > 0, "register_item_instance should succeed")
	TestFramework.assert_true(ItemSystem.item_exists(item_id))
	# data map 不应被底层 API 写入
	TestFramework.assert_equal(null, ItemSystem.get_item_data(item_id))
	_teardown()


func _test_create_item_catalog_missing() -> void:
	var ctx := _setup()
	var r := ItemSystem.create_item(ctx.bag_id, &"nonexistent_config", 1)
	TestFramework.assert_false(r.success)
	TestFramework.assert_true("config_id" in r.error_message or "nonexistent_config" in r.error_message)
	TestFramework.assert_equal(1, r.remaining_count)
	_teardown()


func _test_create_item_domain_reject() -> void:
	var ctx := _setup()
	var domain: TestDomain = ctx.domain
	domain.can_create_block_ids.append(ITEM_SWORD)
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1)
	TestFramework.assert_false(r.success)
	TestFramework.assert_true("blocked by test" in r.error_message)
	_teardown()


func _test_create_item_single() -> void:
	var ctx := _setup()
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	TestFramework.assert_true(r.success)
	TestFramework.assert_equal(1, r.created_item_ids.size())
	TestFramework.assert_equal(0, r.updated_item_ids.size())
	TestFramework.assert_equal(0, r.remaining_count)

	var item_id: int = r.created_item_ids[0]
	var data := ItemSystem.get_item_data(item_id)
	TestFramework.assert_true(data != null)
	TestFramework.assert_equal(ITEM_SWORD, data.config_id)
	TestFramework.assert_equal(1, data.count)

	var loc := ItemSystem.get_item_location(item_id)
	TestFramework.assert_equal(ctx.bag_id, loc.container_id)
	TestFramework.assert_equal(0, loc.slot_index)
	_teardown()


func _test_create_item_stack_merge() -> void:
	var ctx := _setup()
	# 先放 5 个 rune (max_stack=9, slot=0)
	var r1 := ItemSystem.create_item(ctx.bag_id, ITEM_RUNE, 5, 0)
	TestFramework.assert_true(r1.success)
	TestFramework.assert_equal(1, r1.created_item_ids.size())
	var first_id: int = r1.created_item_ids[0]

	# 再放 3 个: 应该 merge 进同一 stack (5+3=8), 不新建
	var r2 := ItemSystem.create_item(ctx.bag_id, ITEM_RUNE, 3)
	TestFramework.assert_true(r2.success)
	TestFramework.assert_true(r2.created_item_ids.is_empty(), "should not create new stack")
	TestFramework.assert_equal(1, r2.updated_item_ids.size())
	TestFramework.assert_equal(first_id, r2.updated_item_ids[0])

	var data := ItemSystem.get_item_data(first_id)
	TestFramework.assert_equal(8, data.count)

	# 再放 5 个: max_stack=9, 只能 merge 1; 剩余 4 应新建 stack
	var r3 := ItemSystem.create_item(ctx.bag_id, ITEM_RUNE, 5, 1)
	TestFramework.assert_true(r3.success)
	TestFramework.assert_equal(1, r3.updated_item_ids.size())
	TestFramework.assert_equal(1, r3.created_item_ids.size())
	var second_id: int = r3.created_item_ids[0]
	TestFramework.assert_equal(9, ItemSystem.get_item_data(first_id).count)
	TestFramework.assert_equal(4, ItemSystem.get_item_data(second_id).count)
	_teardown()


func _test_create_item_callback_order() -> void:
	var ctx := _setup()
	var domain: TestDomain = ctx.domain

	# 监听 item_created signal: signal handler 必须能在 emit 时读到 _item_data_by_id
	var captured_data: Array[ItemInstanceData] = []
	var signal_handler := func(item_id: int, _loc: ItemLocation) -> void:
		captured_data.append(ItemSystem.get_item_data(item_id))
	ItemSystem.item_created.connect(signal_handler)

	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	TestFramework.assert_true(r.success)
	var item_id: int = r.created_item_ids[0]

	# domain.on_item_created 应被调用
	TestFramework.assert_equal(1, domain.on_created_calls.size())
	TestFramework.assert_equal(item_id, domain.on_created_calls[0])

	# signal 触发时 data 必须已写入
	TestFramework.assert_equal(1, captured_data.size())
	TestFramework.assert_true(captured_data[0] != null, "item_data must be available at item_created signal")
	TestFramework.assert_equal(ITEM_SWORD, captured_data[0].config_id)

	ItemSystem.item_created.disconnect(signal_handler)
	_teardown()


func _test_move_item_across() -> void:
	var ctx := _setup()
	var bag_id: int = ctx.bag_id
	var equip_id: int = ctx.equip_id
	var domain: TestDomain = ctx.domain

	var r := ItemSystem.create_item(bag_id, ITEM_SWORD, 1, 0)
	var item_id: int = r.created_item_ids[0]

	domain.on_moved_calls.clear()
	var m := ItemSystem.move_item(item_id, equip_id, 1)
	TestFramework.assert_true(m.success)
	TestFramework.assert_equal(bag_id, m.source_location.container_id)
	TestFramework.assert_equal(0, m.source_location.slot_index)
	TestFramework.assert_equal(equip_id, m.target_location.container_id)
	TestFramework.assert_equal(1, m.target_location.slot_index)

	var loc := ItemSystem.get_item_location(item_id)
	TestFramework.assert_equal(equip_id, loc.container_id)
	TestFramework.assert_equal(1, loc.slot_index)

	# domain.on_item_moved 被调用 + 参数正确
	TestFramework.assert_equal(1, domain.on_moved_calls.size())
	var call_data: Dictionary = domain.on_moved_calls[0]
	TestFramework.assert_equal(bag_id, call_data["old_container"])
	TestFramework.assert_equal(equip_id, call_data["new_container"])
	_teardown()


func _test_move_item_occupied_slot() -> void:
	var ctx := _setup()
	# 先把 sword 放到 equip slot 1
	var r1 := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	var sword_id: int = r1.created_item_ids[0]
	var m1 := ItemSystem.move_item(sword_id, ctx.equip_id, 1)
	TestFramework.assert_true(m1.success)

	# 再创建 second sword, 尝试也放 slot 1 → 应失败
	var r2 := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 1)
	var sword2_id: int = r2.created_item_ids[0]
	var m2 := ItemSystem.move_item(sword2_id, ctx.equip_id, 1)
	TestFramework.assert_false(m2.success, "should fail when slot occupied")
	TestFramework.assert_true(m2.error_message.length() > 0)
	# target_location 应记录 attempted target
	TestFramework.assert_equal(ctx.equip_id, m2.target_location.container_id)
	TestFramework.assert_equal(1, m2.target_location.slot_index)
	# source_location 应是 sword2 的当前位置
	TestFramework.assert_equal(ctx.bag_id, m2.source_location.container_id)
	# sword2 应还在 bag
	var loc := ItemSystem.get_item_location(sword2_id)
	TestFramework.assert_equal(ctx.bag_id, loc.container_id)
	_teardown()


func _test_move_item_domain_reject() -> void:
	var ctx := _setup()
	var domain: TestDomain = ctx.domain
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	var sword_id: int = r.created_item_ids[0]

	domain.can_move_block_pairs.append([sword_id, ctx.equip_id])
	var m := ItemSystem.move_item(sword_id, ctx.equip_id, 1)
	TestFramework.assert_false(m.success)
	TestFramework.assert_true("blocked move" in m.error_message)
	# sword 应保留在 bag
	TestFramework.assert_equal(ctx.bag_id, ItemSystem.get_item_location(sword_id).container_id)
	_teardown()


func _test_move_item_within() -> void:
	var ctx := _setup()
	var domain: TestDomain = ctx.domain
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	var sword_id: int = r.created_item_ids[0]

	# 监听 container.item_moved_within signal
	var emitted_args: Array = []
	var handler := func(iid: int, old_s: int, new_s: int) -> void:
		emitted_args.append([iid, old_s, new_s])
	ctx.bag.item_moved_within.connect(handler)

	domain.on_moved_calls.clear()
	var m := ItemSystem.move_item(sword_id, ctx.bag_id, 5)
	TestFramework.assert_true(m.success)
	TestFramework.assert_equal(ctx.bag_id, m.source_location.container_id)
	TestFramework.assert_equal(0, m.source_location.slot_index)
	TestFramework.assert_equal(ctx.bag_id, m.target_location.container_id)
	TestFramework.assert_equal(5, m.target_location.slot_index)

	# signal 被触发
	TestFramework.assert_equal(1, emitted_args.size())
	TestFramework.assert_equal(sword_id, emitted_args[0][0])
	TestFramework.assert_equal(0, emitted_args[0][1])
	TestFramework.assert_equal(5, emitted_args[0][2])

	# 旧槽应被释放,新槽应被占用
	TestFramework.assert_true(ctx.bag.get_space_manager().is_slot_available(0))
	TestFramework.assert_false(ctx.bag.get_space_manager().is_slot_available(5))

	# domain.on_item_moved 也应被调用
	TestFramework.assert_equal(1, domain.on_moved_calls.size())

	ctx.bag.item_moved_within.disconnect(handler)
	_teardown()


func _test_item_moved_in_signal() -> void:
	var ctx := _setup()
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	var sword_id: int = r.created_item_ids[0]

	# 监听 equip container 的 item_moved_in signal (新 4 参版)
	var emitted: Array = []
	var handler := func(iid: int, src_c: int, src_s: int, tgt_s: int) -> void:
		emitted.append([iid, src_c, src_s, tgt_s])
	ctx.equip.item_moved_in.connect(handler)

	var m := ItemSystem.move_item(sword_id, ctx.equip_id, 2)
	TestFramework.assert_true(m.success)
	TestFramework.assert_equal(1, emitted.size())
	TestFramework.assert_equal(sword_id, emitted[0][0])
	TestFramework.assert_equal(ctx.bag_id, emitted[0][1])
	TestFramework.assert_equal(0, emitted[0][2])
	TestFramework.assert_true(emitted[0][3] == 2, "target_slot_index must be in signal arg 4")
	ctx.equip.item_moved_in.disconnect(handler)
	_teardown()


func _test_destroy_item() -> void:
	var ctx := _setup()
	var domain: TestDomain = ctx.domain
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	var sword_id: int = r.created_item_ids[0]

	var ok := ItemSystem.destroy_item(sword_id)
	TestFramework.assert_true(ok)
	TestFramework.assert_false(ItemSystem.item_exists(sword_id))
	TestFramework.assert_equal(null, ItemSystem.get_item_data(sword_id))
	TestFramework.assert_equal(0, ctx.bag.get_item_count())
	# domain.on_item_destroyed 被调用
	TestFramework.assert_equal(1, domain.on_destroyed_calls.size())
	TestFramework.assert_equal(sword_id, domain.on_destroyed_calls[0])
	_teardown()


func _test_get_item_snapshot() -> void:
	var ctx := _setup()
	var r := ItemSystem.create_item(ctx.bag_id, ITEM_RUNE, 3, 2)
	var rune_id: int = r.created_item_ids[0]

	var snap := ItemSystem.get_item_snapshot(rune_id)
	TestFramework.assert_equal(rune_id, snap.get("item_id"))
	TestFramework.assert_equal(ctx.bag_id, snap.get("container_id"))
	TestFramework.assert_equal(2, snap.get("slot_index"))
	TestFramework.assert_equal("test_rune", snap.get("config_id"))
	TestFramework.assert_equal(3, snap.get("count"))
	TestFramework.assert_equal("Test Rune", snap.get("display_name"))
	TestFramework.assert_equal(9, snap.get("max_stack"))
	TestFramework.assert_true(snap.get("stackable") == true)
	TestFramework.assert_true(snap.get("equipable") == true)
	_teardown()


func _test_unregister_container_destroys_items() -> void:
	var ctx := _setup()
	var domain: TestDomain = ctx.domain
	var r1 := ItemSystem.create_item(ctx.bag_id, ITEM_SWORD, 1, 0)
	var r2 := ItemSystem.create_item(ctx.bag_id, ITEM_RUNE, 5, 1)
	var sword_id: int = r1.created_item_ids[0]
	var rune_id: int = r2.created_item_ids[0]

	var ok := ItemSystem.unregister_container(ctx.bag_id)
	TestFramework.assert_true(ok)
	TestFramework.assert_false(ItemSystem.item_exists(sword_id))
	TestFramework.assert_false(ItemSystem.item_exists(rune_id))
	TestFramework.assert_equal(2, domain.on_destroyed_calls.size())
	TestFramework.assert_equal(null, ItemSystem.get_container(ctx.bag_id))
	_teardown()
