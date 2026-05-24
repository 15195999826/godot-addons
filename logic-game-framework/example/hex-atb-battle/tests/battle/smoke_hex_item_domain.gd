## Smoke: HexItemDomain / HexPlayerInventory data-layer contract
##
## 不依赖 UI / 不动 WorldGI, 只验证 Phase B 的 data layer:
##  1. configure_domain(HexItemDomain, HexItemCatalog) 后 business create_item 成功
##  2. HexPlayerInventory.register_actor 创建装备容器, equipment_container_ids 同步
##  3. equipable item 可装备到空槽; non-equipable 被 domain reject
##  4. 装备到 occupied slot 被 BaseContainer can_add_item reject
##  5. unregister_actor: 装备 item 卸回 bag, container 销毁
##  6. reset_actor_equipment_keep_player: 装备卸回 bag, actor list 保留, 容器重建
##  7. dispose() + reset_session() 后 ItemSystem 不残留本轮 containers/items
extends Node


const HexItemDomainScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_item_domain.gd")
const HexItemCatalogScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_item_catalog.gd")
const HexPlayerInventoryScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_player_inventory.gd")
const HexActorEquipmentContainerScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/item/hex_actor_equipment_container.gd")

const ACTOR_A := "actor-A"
const ACTOR_B := "actor-B"


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: HexItemDomain data-layer contract ===")

	if not _phase_configure_and_create():
		return
	if not _phase_register_actor_creates_equipment_container():
		return
	if not _phase_equip_equipable_to_empty_slot():
		return
	if not _phase_reject_non_equipable():
		return
	if not _phase_reject_occupied_slot():
		return
	if not _phase_unregister_actor_unloads_equipment():
		return
	if not _phase_reset_actor_equipment_keep_player():
		return
	if not _phase_dispose_and_reset_session():
		return
	if not _phase_container_equipable_defense_in_depth():
		return
	if not _phase_merge_stack_contract():
		return
	if not _phase_snapshot_fields():
		return
	if not _phase_get_actor_id_for_container():
		return
	if not _phase_domain_reset_clears_equipment_ids():
		return

	print("SMOKE_TEST_RESULT: PASS - all HexItemDomain data-layer checks passed")
	get_tree().quit(0)


# ============================================================
# Phase 1: configure_domain + business create_item
# ============================================================

func _phase_configure_and_create() -> bool:
	ItemSystem.reset_session()
	ItemSystem.configure_domain(HexItemDomainScript.new(), HexItemCatalogScript.new())

	var inv := HexPlayerInventoryScript.new()
	inv.init_inventory()
	if inv.player_bag_id <= 0:
		return _fail("phase1: player_bag_id 应 > 0, got %d" % inv.player_bag_id)

	# 一个 sword + 5 个 rune (catalog 已知 config)
	var r1 := ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0)
	if not r1.success:
		return _fail("phase1: create training_sword 失败: %s" % r1.error_message)
	var r2 := ItemSystem.create_item(inv.player_bag_id, &"minor_rune", 5, 1)
	if not r2.success:
		return _fail("phase1: create minor_rune 失败: %s" % r2.error_message)

	# 未知 config 必须 fail
	var r3 := ItemSystem.create_item(inv.player_bag_id, &"nonexistent_thing", 1)
	if r3.success:
		return _fail("phase1: nonexistent config 应 fail, 实际 success")

	inv.dispose()
	ItemSystem.reset_session()
	print("  phase1 OK")
	return true


# ============================================================
# Phase 2: register_actor 创建装备容器 + domain.equipment_container_ids 同步
# ============================================================

func _phase_register_actor_creates_equipment_container() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	var domain: HexItemDomain = ctx.domain

	var eq_a := inv.register_actor(ACTOR_A)
	var eq_b := inv.register_actor(ACTOR_B)
	if eq_a <= 0 or eq_b <= 0 or eq_a == eq_b:
		return _fail("phase2: equipment container_id 应 > 0 且 A != B, got A=%d B=%d" % [eq_a, eq_b])

	# domain 必须同步 equipment container 记录
	if not domain.has_equipment_container(eq_a) or not domain.has_equipment_container(eq_b):
		return _fail("phase2: domain has_equipment_container 应同步 eq_a / eq_b")

	# 容器槽数 = 6
	var container_a := ItemSystem.get_container(eq_a) as HexActorEquipmentContainer
	if container_a == null:
		return _fail("phase2: container_a 应是 HexActorEquipmentContainer")
	if container_a.get_space_manager().get_total_slots() != 6:
		return _fail("phase2: equipment 槽数应 = 6, got %d" % container_a.get_space_manager().get_total_slots())
	if container_a.owner_actor_id != ACTOR_A:
		return _fail("phase2: owner_actor_id 错: %s vs %s" % [container_a.owner_actor_id, ACTOR_A])

	_teardown(ctx)
	print("  phase2 OK")
	return true


# ============================================================
# Phase 3: equipable item 装备到空槽 — success path
# ============================================================

func _phase_equip_equipable_to_empty_slot() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)

	var sword_r := ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0)
	var sword_id: int = sword_r.created_item_ids[0]

	var m := ItemSystem.move_item(sword_id, eq_a, 0)
	if not m.success:
		return _fail("phase3: equipable item 应能装备到空槽, 实际 fail: %s" % m.error_message)

	var loc := ItemSystem.get_item_location(sword_id)
	if loc.container_id != eq_a or loc.slot_index != 0:
		return _fail("phase3: location 应是 eq_a:0, got %d:%d" % [loc.container_id, loc.slot_index])

	# get_item_snapshot 应有 equipable=true / display_name
	var snap := ItemSystem.get_item_snapshot(sword_id)
	if snap.get("equipable") != true:
		return _fail("phase3: snapshot equipable 应 true")
	if snap.get("display_name") != "Training Sword":
		return _fail("phase3: snapshot display_name 错: %s" % str(snap.get("display_name")))

	_teardown(ctx)
	print("  phase3 OK")
	return true


# ============================================================
# Phase 4: non-equipable 被 domain reject
# ============================================================

func _phase_reject_non_equipable() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)

	var stone_r := ItemSystem.create_item(inv.player_bag_id, &"broken_stone", 1, 0)
	var stone_id: int = stone_r.created_item_ids[0]

	var m := ItemSystem.move_item(stone_id, eq_a, 0)
	if m.success:
		return _fail("phase4: non-equipable 应 fail, 实际 success")
	if not "不可装备" in m.error_message:
		return _fail("phase4: error_message 应含 '不可装备', got: %s" % m.error_message)
	# stone 应留在 bag
	var loc := ItemSystem.get_item_location(stone_id)
	if loc.container_id != inv.player_bag_id:
		return _fail("phase4: stone 应保留 bag, 实际 container %d" % loc.container_id)

	_teardown(ctx)
	print("  phase4 OK")
	return true


# ============================================================
# Phase 5: occupied slot 被 reject (V1 不做 swap)
# ============================================================

func _phase_reject_occupied_slot() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)

	var sword_r := ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0)
	var sword_id: int = sword_r.created_item_ids[0]
	var orb_r := ItemSystem.create_item(inv.player_bag_id, &"frost_orb", 1, 1)
	var orb_id: int = orb_r.created_item_ids[0]

	# 第一个 equipable 上 slot 0
	var m1 := ItemSystem.move_item(sword_id, eq_a, 0)
	if not m1.success:
		return _fail("phase5: 第一个装备应成功")

	# 第二个 equipable 试图 slot 0 — 应被拒
	var m2 := ItemSystem.move_item(orb_id, eq_a, 0)
	if m2.success:
		return _fail("phase5: occupied slot 应被拒, 实际成功")
	# orb 应留在 bag
	if ItemSystem.get_item_location(orb_id).container_id != inv.player_bag_id:
		return _fail("phase5: orb 应保留 bag")

	_teardown(ctx)
	print("  phase5 OK")
	return true


# ============================================================
# Phase 6: unregister_actor 把装备卸回 bag, 容器销毁
# ============================================================

func _phase_unregister_actor_unloads_equipment() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	var domain: HexItemDomain = ctx.domain
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)

	var sword_r := ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0)
	var sword_id: int = sword_r.created_item_ids[0]
	ItemSystem.move_item(sword_id, eq_a, 0)
	if ItemSystem.get_item_location(sword_id).container_id != eq_a:
		return _fail("phase6 setup: sword 没装上")

	inv.unregister_actor(ACTOR_A)

	# 容器应被销毁
	if ItemSystem.get_container(eq_a) != null:
		return _fail("phase6: equipment container 应被销毁")
	if domain.has_equipment_container(eq_a):
		return _fail("phase6: domain 仍含 eq_a 的 equipment container 记录")
	# sword 应回到 bag
	var loc := ItemSystem.get_item_location(sword_id)
	if loc == null or loc.container_id != inv.player_bag_id:
		return _fail("phase6: sword 应回到 player bag, loc=%s" % str(loc))

	_teardown(ctx)
	print("  phase6 OK")
	return true


# ============================================================
# Phase 7: reset_actor_equipment_keep_player — 卸回 + 容器重建 + 保留 player bag
# ============================================================

func _phase_reset_actor_equipment_keep_player() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	inv.register_actor(ACTOR_B)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)
	var eq_b := inv.get_equipment_container_id(ACTOR_B)

	# 给两个 actor 都装一件
	var sword_id: int = ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0).created_item_ids[0]
	var orb_id: int = ItemSystem.create_item(inv.player_bag_id, &"frost_orb", 1, 1).created_item_ids[0]
	ItemSystem.move_item(sword_id, eq_a, 0)
	ItemSystem.move_item(orb_id, eq_b, 0)

	var bag_count_before := ItemSystem.get_items_in_container(inv.player_bag_id).size()

	inv.reset_actor_equipment_keep_player()

	# bag 应 +2 (sword + orb 都卸回);两个新 equipment container_id 不一定与旧相同
	var bag_count_after := ItemSystem.get_items_in_container(inv.player_bag_id).size()
	if bag_count_after != bag_count_before + 2:
		return _fail("phase7: bag 应 +2 (sword+orb 卸回), before=%d after=%d" % [bag_count_before, bag_count_after])

	# actor list 保留
	var actors := inv.get_registered_actor_ids()
	if actors.size() != 2:
		return _fail("phase7: actor list 应保留 2 个, got %d" % actors.size())

	# 新容器应是空的
	var new_eq_a := inv.get_equipment_container_id(ACTOR_A)
	var new_eq_b := inv.get_equipment_container_id(ACTOR_B)
	if ItemSystem.get_items_in_container(new_eq_a).size() != 0:
		return _fail("phase7: 新 eq_a 应空")
	if ItemSystem.get_items_in_container(new_eq_b).size() != 0:
		return _fail("phase7: 新 eq_b 应空")

	# player bag id 不变
	if inv.player_bag_id != ctx.bag_id_before:
		return _fail("phase7: player bag id 应保持不变")

	_teardown(ctx)
	print("  phase7 OK")
	return true


# ============================================================
# Phase 8: dispose() + reset_session() 完整 teardown
# ============================================================

func _phase_dispose_and_reset_session() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)
	var sword_id: int = ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0).created_item_ids[0]
	ItemSystem.move_item(sword_id, eq_a, 0)

	var bag_id := inv.player_bag_id

	inv.dispose()

	# dispose 后 player_bag_id = -1, container 已 unregister
	if inv.player_bag_id != -1:
		return _fail("phase8: dispose 后 player_bag_id 应 = -1")
	if ItemSystem.get_container(bag_id) != null:
		return _fail("phase8: player bag container 应已 unregister")
	if ItemSystem.get_container(eq_a) != null:
		return _fail("phase8: equipment container 应已 unregister")
	# items 也应被销毁 (unregister_container 会 destroy_item)
	if ItemSystem.item_exists(sword_id):
		return _fail("phase8: sword 应被销毁")

	# reset_session 后 domain 回到 default
	ItemSystem.reset_session()
	if not (ItemSystem.get_domain() is DefaultItemDomain):
		return _fail("phase8: reset_session 后 domain 应为 DefaultItemDomain")
	print("  phase8 OK")
	return true


# ============================================================
# Phase 9: container equipable defense-in-depth (review H2)
# 直接调 container.can_add_item, 绕过 ItemSystem.move_item / domain.can_move_item,
# 验证 HexActorEquipmentContainer 自己也能拦 non-equipable item。
# ============================================================

func _phase_container_equipable_defense_in_depth() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)
	var container := ItemSystem.get_container(eq_a) as HexActorEquipmentContainer

	# 创建 non-equipable item (broken_stone)
	var stone_r := ItemSystem.create_item(inv.player_bag_id, &"broken_stone", 1, 0)
	var stone_id: int = stone_r.created_item_ids[0]

	# 直接走 container.can_add_item, 绕过 ItemSystem.move_item: 必须拦
	var direct_check := container.can_add_item(stone_id, 0)
	if direct_check.success:
		return _fail("phase9: container.can_add_item 应拦 non-equipable item (defense-in-depth)")
	if not "不可装备" in direct_check.error_message:
		return _fail("phase9: error_message 应含 '不可装备', got: %s" % direct_check.error_message)

	# 同样的 container, equipable item 应允许
	var sword_r := ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 1)
	var sword_id: int = sword_r.created_item_ids[0]
	var allow_check := container.can_add_item(sword_id, 0)
	if not allow_check.success:
		return _fail("phase9: equipable item 应被 container 允许 (defense-in-depth 不应误伤)")

	_teardown(ctx)
	print("  phase9 OK")
	return true


# ============================================================
# Phase 10: HexItemDomain.merge_stack 专项 (review H3)
# 验证 mutate-existing-count + leftover 合约
# ============================================================

func _phase_merge_stack_contract() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv

	# 先放 5 个 minor_rune (max_stack=9, slot 0)
	var r1 := ItemSystem.create_item(inv.player_bag_id, &"minor_rune", 5, 0)
	if not r1.success or r1.created_item_ids.size() != 1:
		return _fail("phase10 setup: 第一批 minor_rune 应创建成功")
	var first_id: int = r1.created_item_ids[0]
	if ItemSystem.get_item_data(first_id).count != 5:
		return _fail("phase10 setup: 第一批 count 应 = 5")

	# 再放 3 个: 应该 merge (5+3=8), 0 新建
	var r2 := ItemSystem.create_item(inv.player_bag_id, &"minor_rune", 3)
	if not r2.success:
		return _fail("phase10: 第二批 merge 应成功")
	if r2.created_item_ids.size() != 0:
		return _fail("phase10: 第二批应 merge 而非新建, created=%d" % r2.created_item_ids.size())
	if r2.updated_item_ids.size() != 1 or r2.updated_item_ids[0] != first_id:
		return _fail("phase10: updated_item_ids 应 = [first_id]")
	if ItemSystem.get_item_data(first_id).count != 8:
		return _fail("phase10: merge 后 count 应 = 8, got %d" % ItemSystem.get_item_data(first_id).count)

	# 再放 6 个: max_stack=9, 只能 merge 1 (count -> 9); 剩 5 新建
	var r3 := ItemSystem.create_item(inv.player_bag_id, &"minor_rune", 6, 1)
	if not r3.success:
		return _fail("phase10: 第三批 partial merge + new stack 应成功")
	if r3.updated_item_ids.size() != 1:
		return _fail("phase10: 第三批 updated 应 = 1 个 (撑爆第一 stack)")
	if r3.created_item_ids.size() != 1:
		return _fail("phase10: 第三批 created 应 = 1 (剩余新建)")
	if ItemSystem.get_item_data(first_id).count != 9:
		return _fail("phase10: 第一 stack 应被撑到 9, got %d" % ItemSystem.get_item_data(first_id).count)
	var second_id: int = r3.created_item_ids[0]
	if ItemSystem.get_item_data(second_id).count != 5:
		return _fail("phase10: 新 stack 应 = 5, got %d" % ItemSystem.get_item_data(second_id).count)

	_teardown(ctx)
	print("  phase10 OK")
	return true


# ============================================================
# Phase 11: snapshot 全字段 (review L5)
# ============================================================

func _phase_snapshot_fields() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv

	# non-stackable equipable
	var sword_r := ItemSystem.create_item(inv.player_bag_id, &"training_sword", 1, 0)
	var sword_id: int = sword_r.created_item_ids[0]
	var ssnap := ItemSystem.get_item_snapshot(sword_id)
	if ssnap.get("config_id") != "training_sword":
		return _fail("phase11: sword config_id 错")
	if ssnap.get("display_name") != "Training Sword":
		return _fail("phase11: sword display_name 错")
	if ssnap.get("icon_key") != "sword":
		return _fail("phase11: sword icon_key 错")
	if int(ssnap.get("max_stack", 0)) != 1:
		return _fail("phase11: sword max_stack 应 = 1")
	if ssnap.get("stackable") != false:
		return _fail("phase11: sword stackable 应 false")
	if ssnap.get("equipable") != true:
		return _fail("phase11: sword equipable 应 true")
	var stags: Array = ssnap.get("item_tags", [])
	if not &"equipment" in stags:
		return _fail("phase11: sword item_tags 应含 equipment")
	if int(ssnap.get("count", 0)) != 1:
		return _fail("phase11: sword count 应 = 1")

	# stackable item (minor_rune)
	var rune_r := ItemSystem.create_item(inv.player_bag_id, &"minor_rune", 7, 1)
	var rune_id: int = rune_r.created_item_ids[0]
	var rsnap := ItemSystem.get_item_snapshot(rune_id)
	if int(rsnap.get("max_stack", 0)) != 9:
		return _fail("phase11: rune max_stack 应 = 9")
	if rsnap.get("stackable") != true:
		return _fail("phase11: rune stackable 应 true")
	if int(rsnap.get("count", 0)) != 7:
		return _fail("phase11: rune count 应 = 7")
	var rtags: Array = rsnap.get("item_tags", [])
	if not &"rune" in rtags:
		return _fail("phase11: rune item_tags 应含 rune")

	# non-equipable
	var stone_r := ItemSystem.create_item(inv.player_bag_id, &"broken_stone", 1, 2)
	var stone_id: int = stone_r.created_item_ids[0]
	var nsnap := ItemSystem.get_item_snapshot(stone_id)
	if nsnap.get("equipable") != false:
		return _fail("phase11: stone equipable 应 false")

	_teardown(ctx)
	print("  phase11 OK")
	return true


# ============================================================
# Phase 12: get_actor_id_for_container 反向查询 (review M2)
# ============================================================

func _phase_get_actor_id_for_container() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	inv.register_actor(ACTOR_A)
	inv.register_actor(ACTOR_B)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)
	var eq_b := inv.get_equipment_container_id(ACTOR_B)

	if inv.get_actor_id_for_container(eq_a) != ACTOR_A:
		return _fail("phase12: eq_a -> %s, expected %s" % [inv.get_actor_id_for_container(eq_a), ACTOR_A])
	if inv.get_actor_id_for_container(eq_b) != ACTOR_B:
		return _fail("phase12: eq_b -> %s, expected %s" % [inv.get_actor_id_for_container(eq_b), ACTOR_B])
	# 不存在的 container 应返回 ""
	if inv.get_actor_id_for_container(99999) != "":
		return _fail("phase12: 不存在 container 应返回 empty string")
	# player bag 不是 actor 装备容器, 也返回 ""
	if inv.get_actor_id_for_container(inv.player_bag_id) != "":
		return _fail("phase12: player bag 不是 actor 装备容器, 应返回 empty string")

	_teardown(ctx)
	print("  phase12 OK")
	return true


# ============================================================
# Phase 13: domain.reset() 清理 _equipment_container_ids (review H1)
# ============================================================

func _phase_domain_reset_clears_equipment_ids() -> bool:
	var ctx := _setup()
	var inv: HexPlayerInventory = ctx.inv
	var domain: HexItemDomain = ctx.domain
	inv.register_actor(ACTOR_A)
	var eq_a := inv.get_equipment_container_id(ACTOR_A)
	if not domain.has_equipment_container(eq_a):
		return _fail("phase13 setup: domain 应记录 eq_a")

	# 单独调 domain.reset() 不通过 ItemSystem.reset_session(), 验证 reset() 自身清理
	domain.reset()
	if domain.has_equipment_container(eq_a):
		return _fail("phase13: domain.reset() 后 _equipment_container_ids 应被清空")

	# 模拟 ItemSystem.reset_session 的完整路径: 也要 OK
	_teardown(ctx)
	# teardown 内部已经 reset_session, 此时 domain 已被 ItemSystem 替换;ctx.domain
	# (旧实例) 内部的 _equipment_container_ids 也应被它自己的 reset() 清空
	# (reset_session 会先调 _domain.reset(), 然后才替换)
	if domain.has_equipment_container(eq_a):
		return _fail("phase13: reset_session 后旧 domain 实例 _equipment_container_ids 也应清空")
	print("  phase13 OK")
	return true


# ============================================================
# helpers
# ============================================================

func _setup() -> Dictionary:
	ItemSystem.reset_session()
	var domain := HexItemDomainScript.new()
	var catalog := HexItemCatalogScript.new()
	ItemSystem.configure_domain(domain, catalog)
	var inv := HexPlayerInventoryScript.new()
	inv.init_inventory()
	return {
		"inv": inv,
		"domain": domain,
		"catalog": catalog,
		"bag_id_before": inv.player_bag_id,
	}


func _teardown(ctx: Dictionary) -> void:
	(ctx.inv as HexPlayerInventory).dispose()
	ItemSystem.reset_session()


func _fail(msg: String) -> bool:
	print("SMOKE_TEST_RESULT: FAIL - %s" % msg)
	get_tree().quit(1)
	return false
