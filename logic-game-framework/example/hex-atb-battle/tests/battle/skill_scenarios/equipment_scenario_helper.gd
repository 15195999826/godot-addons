## EquipmentScenarioHelper - Phase G 装备 scenarios 共享 setup utility
##
## 目的: 把"reset ItemSystem + configure HexItemDomain/Catalog + 创建 player bag +
## 注册 caster equipment container + 创建/移动 item 进 equipment container"这套
## 装备 grant 链路设置代码集中到一处, 避免 5 个 equipment_*_scenario.gd 各自复制。
##
## 用法:
##   var ctx := EquipmentScenarioHelper.setup(caster_id, setup_errors)
##   if ctx == null:
##       return false
##   var equip_result := EquipmentScenarioHelper.equip(ctx, item_config_id, setup_errors)
##   ...
##
## scenario 在 setup_battle hook 内调用; setup_errors 由 SkillScenario.setup_battle 传入,
## helper 在失败时 append 错误信息, scenario assert_replay 通过 ctx.setup_errors 读取。
class_name EquipmentScenarioHelper


## setup() 返回值的结构: 一份 inventory + 容器 id 视图。
class SetupContext extends RefCounted:
	var inv: HexPlayerInventory
	var bag_id: int = -1
	var equipment_container_id: int = -1
	var caster_id: String = ""

	func get_equipment_container() -> HexActorEquipmentContainer:
		if equipment_container_id < 0:
			return null
		return ItemSystem.get_container(equipment_container_id) as HexActorEquipmentContainer


## reset ItemSystem session + configure domain + create player bag + register caster's
## equipment container。失败时 setup_errors append + 返回 null。
static func setup(caster_id: String, setup_errors: Array) -> SetupContext:
	if caster_id.is_empty():
		setup_errors.append("EquipmentScenarioHelper.setup: caster_id 为空")
		return null
	ItemSystem.reset_session()
	ItemSystem.configure_domain(HexItemDomain.new(), HexItemCatalog.new())

	var inv := HexPlayerInventory.new()
	inv.init_inventory()
	if inv.player_bag_id <= 0:
		setup_errors.append("EquipmentScenarioHelper.setup: init_inventory 后 player_bag_id 非法 (%d)" % inv.player_bag_id)
		return null
	var cid := inv.register_actor(caster_id)
	if cid < 0:
		setup_errors.append("EquipmentScenarioHelper.setup: register_actor(%s) 失败 (cid=%d)" % [caster_id, cid])
		return null

	var ctx := SetupContext.new()
	ctx.inv = inv
	ctx.bag_id = inv.player_bag_id
	ctx.equipment_container_id = cid
	ctx.caster_id = caster_id
	return ctx


## 在 bag 内创建一个 item, 然后 move 到 equipment container。返回 item_id (失败时 -1)。
##
## 失败原因写到 setup_errors; 失败时 item 仍可能留在 bag (caller 不需要单独清理 ——
## 整个 ItemSystem 在下一次 setup() 时 reset_session)。
static func equip(ctx: SetupContext, item_config_id: StringName, setup_errors: Array) -> int:
	if ctx == null:
		setup_errors.append("equip: ctx 为空")
		return -1
	var create_r := ItemSystem.create_item(ctx.bag_id, item_config_id, 1, -1)
	if not create_r.success:
		setup_errors.append("equip(%s): create_item 失败 — %s" % [str(item_config_id), create_r.error_message])
		return -1
	if create_r.created_item_ids.is_empty():
		setup_errors.append("equip(%s): create_item 成功但 created_item_ids 为空" % str(item_config_id))
		return -1
	var item_id: int = create_r.created_item_ids[0]
	var move_r := ItemSystem.move_item(item_id, ctx.equipment_container_id, 0)
	if not move_r.success:
		setup_errors.append("equip(%s): move_item to equipment 失败 — %s" % [str(item_config_id), move_r.error_message])
		return item_id
	return item_id


## 把 equipment container 内某 item 卸下到 bag (slot=0)。返回 ok 标志, 失败原因写
## setup_errors。用于 lifecycle scenarios 在 setup 阶段先装备 / 跑测后卸下。
static func unequip(ctx: SetupContext, item_id: int, setup_errors: Array) -> bool:
	if ctx == null:
		setup_errors.append("unequip: ctx 为空")
		return false
	var move_r := ItemSystem.move_item(item_id, ctx.bag_id, -1)
	if not move_r.success:
		setup_errors.append("unequip(item=%d): move_item to bag 失败 — %s" % [item_id, move_r.error_message])
		return false
	return true
