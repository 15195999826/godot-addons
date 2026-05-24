## HexPlayerInventory - preview-local player + actor equipment 容器编排
##
## Plan §"Player Inventory" + §"Actor Equipment Containers" 职责:
## - 创建 + 维护 player bag container (grid)
## - actor_id -> equipment_container_id 映射
## - actor 注册/注销时管理 equipment container lifecycle
## - reset_actor_equipment_keep_player(): 装备 item 卸回 bag, 重建 actor 装备容器
## - exit 时 dispose() 清理本轮 containers/items (走 ItemSystem.unregister_container)
##
## 不负责:
## - 不维护 item_id -> ItemInstanceData (归 ItemSystem)
## - 不解释 stack / equipable 规则 (归 HexItemDomain)
## - 不持 UI 节点引用
class_name HexPlayerInventory
extends RefCounted


## Player bag 默认 grid 尺寸 (Plan §"Player Bag")
const DEFAULT_BAG_WIDTH := 10
const DEFAULT_BAG_HEIGHT := 8


## player bag container_id (init() 后有效)
var player_bag_id: int = -1

## actor_id -> equipment_container_id
var _actor_equipment: Dictionary = {}  # String -> int

## reference to HexItemDomain so register/unregister equipment container 能通知
var _domain: HexItemDomain


## init: 创建 player bag + 保留 domain 引用 (从 ItemSystem 拿)
## 调用者负责事先 ItemSystem.configure_domain(HexItemDomain.new(), HexItemCatalog.new())
func init_inventory(bag_width: int = DEFAULT_BAG_WIDTH, bag_height: int = DEFAULT_BAG_HEIGHT) -> void:
	_domain = ItemSystem.get_domain() as HexItemDomain
	Log.assert_crash(_domain != null, "HexPlayerInventory",
		"ItemSystem must be configured with HexItemDomain before HexPlayerInventory.init_inventory()")

	var bag := BaseContainer.create_grid(&"PlayerBag", bag_width, bag_height)
	player_bag_id = ItemSystem.register_container(bag)
	Log.info("HexPlayerInventory", "player bag 已创建 (id=%d, %dx%d)" % [player_bag_id, bag_width, bag_height])


## 为 actor 创建 equipment container
## [param actor_id] HexBattleActor.get_id() 返回的 String
## [return] 新 container_id
func register_actor(actor_id: String) -> int:
	if _actor_equipment.has(actor_id):
		Log.warning("HexPlayerInventory", "actor %s 已注册 equipment container,跳过" % actor_id)
		return _actor_equipment[actor_id]

	var container := HexActorEquipmentContainer.create_for_actor(actor_id)
	var cid := ItemSystem.register_container(container)
	_actor_equipment[actor_id] = cid
	_domain.register_equipment_container(cid)
	Log.info("HexPlayerInventory", "actor %s equipment container 已创建 (id=%d)" % [actor_id, cid])
	return cid


## actor 删除时清理 equipment container — 先把装备卸回 bag, 再 unregister
func unregister_actor(actor_id: String) -> void:
	if not _actor_equipment.has(actor_id):
		return
	var cid: int = _actor_equipment[actor_id]
	_unload_equipment_to_bag(cid)
	_domain.unregister_equipment_container(cid)
	ItemSystem.unregister_container(cid)
	_actor_equipment.erase(actor_id)
	Log.info("HexPlayerInventory", "actor %s equipment container 已销毁" % actor_id)


## actor 的 equipment container_id (未注册返回 -1)
func get_equipment_container_id(actor_id: String) -> int:
	return _actor_equipment.get(actor_id, -1)


## 已注册的 actor 列表 (按注册顺序)
func get_registered_actor_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _actor_equipment.keys():
		ids.append(k)
	return ids


## 保留 player bag + items, 只把所有 actor equipment container 销毁后重建。
## 用于未来 SkillPreviewWorldGI.reset() — sandbox reset 走 dispose() + 重新 init。
func reset_actor_equipment_keep_player() -> void:
	var actor_ids: Array[String] = []
	for k in _actor_equipment.keys():
		actor_ids.append(k)

	for actor_id in actor_ids:
		var cid: int = _actor_equipment[actor_id]
		_unload_equipment_to_bag(cid)
		_domain.unregister_equipment_container(cid)
		ItemSystem.unregister_container(cid)

	# 重建空容器
	_actor_equipment.clear()
	for actor_id in actor_ids:
		register_actor(actor_id)

	Log.info("HexPlayerInventory", "reset_actor_equipment_keep_player: %d actors 重建" % actor_ids.size())


## 整个 inventory 释放: 销毁所有 equipment container + player bag,
## 留 ItemSystem 自身 (sandbox exit 通常另调 ItemSystem.reset_session)。
func dispose() -> void:
	for actor_id in _actor_equipment.keys():
		var cid: int = _actor_equipment[actor_id]
		_domain.unregister_equipment_container(cid)
		ItemSystem.unregister_container(cid)
	_actor_equipment.clear()

	if player_bag_id > 0:
		ItemSystem.unregister_container(player_bag_id)
		player_bag_id = -1
	Log.info("HexPlayerInventory", "已 dispose")


## 把某个 equipment container 内的所有 item 移回 player bag。
## 卸不下 (bag full) = lifecycle bug, log error 但继续 — Plan §"Actor
## Equipment Containers": "bag 容量足够大;如果卸回失败,视为 lifecycle bug,
## 记录错误并阻断静默丢 item"。本实现选择不 destroy,而是 log error 让人发现。
func _unload_equipment_to_bag(equipment_container_id: int) -> void:
	if player_bag_id <= 0:
		return
	var items := ItemSystem.get_items_in_container(equipment_container_id)
	for item_id in items:
		var move_result := ItemSystem.move_item(item_id, player_bag_id, -1)
		if not move_result.success:
			Log.error("HexPlayerInventory",
				"卸装失败 (item %d eq=%d -> bag %d): %s — 视为 lifecycle bug, item 仍在 equipment container" % [
					item_id, equipment_container_id, player_bag_id, move_result.error_message
				])
