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


## init: 创建 player bag。
## 调用者负责事先 ItemSystem.configure_domain(HexItemDomain.new(), HexItemCatalog.new())。
## (domain 不在 init 时 snapshot — 每个 register/unregister 调用都即时 fetch
##  确保 ItemSystem.reset_session() 后 inv 仍然 active 时不会用到 stale 引用)
func init_inventory(bag_width: int = DEFAULT_BAG_WIDTH, bag_height: int = DEFAULT_BAG_HEIGHT) -> void:
	var domain := _get_domain_strict()
	# domain 仅用于 assert; init 阶段不实际改 domain 状态
	Log.assert_crash(domain != null, "HexPlayerInventory",
		"ItemSystem must be configured with HexItemDomain before HexPlayerInventory.init_inventory()")

	var bag := BaseContainer.create_grid(&"PlayerBag", bag_width, bag_height)
	player_bag_id = ItemSystem.register_container(bag)
	Log.info("HexPlayerInventory", "player bag 已创建 (id=%d, %dx%d)" % [player_bag_id, bag_width, bag_height])


## 即时 fetch 当前 ItemSystem domain;不存或类型不对 = lifecycle bug (caller 应已
## 配置 HexItemDomain),走 assert 防御后续静默失败。
func _get_domain_strict() -> HexItemDomain:
	var d := ItemSystem.get_domain() as HexItemDomain
	Log.assert_crash(d != null, "HexPlayerInventory",
		"ItemSystem.get_domain() 不是 HexItemDomain — 是否在 reset_session 后忘了重新 configure_domain?")
	return d


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
	_get_domain_strict().register_equipment_container(cid)
	Log.info("HexPlayerInventory", "actor %s equipment container 已创建 (id=%d)" % [actor_id, cid])
	return cid


## actor 删除时清理 equipment container — 先把装备卸回 bag, 再 unregister。
## 卸回失败时保留 equipment container 和映射, 避免 unregister_container 销毁装备。
func unregister_actor(actor_id: String) -> bool:
	if not _actor_equipment.has(actor_id):
		return true
	var cid: int = _actor_equipment[actor_id]
	if not _unload_equipment_to_bag(cid):
		Log.error("HexPlayerInventory", "actor %s equipment container 卸装失败, 已保留 container %d" % [actor_id, cid])
		return false
	_get_domain_strict().unregister_equipment_container(cid)
	ItemSystem.unregister_container(cid)
	_actor_equipment.erase(actor_id)
	Log.info("HexPlayerInventory", "actor %s equipment container 已销毁" % actor_id)
	return true


## actor 的 equipment container_id (未注册返回 -1)
func get_equipment_container_id(actor_id: String) -> int:
	return _actor_equipment.get(actor_id, -1)


## 反向查询: container_id -> actor_id (UI 收到 item_moved signal 需要)。
## 通过 container.owner_actor_id 实现,不维护反向 dict;未找到返回 ""。
func get_actor_id_for_container(container_id: int) -> String:
	var container := ItemSystem.get_container(container_id) as HexActorEquipmentContainer
	if container == null:
		return ""
	return container.owner_actor_id


## 已注册的 actor 列表 (按注册顺序)
func get_registered_actor_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _actor_equipment.keys():
		ids.append(k)
	return ids


## 保留 player bag + items, 只把所有 actor equipment container 销毁后重建。
## 用于未来 SkillPreviewWorldGI.reset() — sandbox reset 走 dispose() + 重新 init。
## 任一装备卸回失败时返回 false, 保留所有 equipment containers, 避免静默丢 item。
func reset_actor_equipment_keep_player() -> bool:
	var actor_ids: Array[String] = []
	for k in _actor_equipment.keys():
		actor_ids.append(k)

	var domain := _get_domain_strict()
	for actor_id in actor_ids:
		var cid: int = _actor_equipment[actor_id]
		if not _unload_equipment_to_bag(cid):
			Log.error("HexPlayerInventory", "reset_actor_equipment_keep_player 卸装失败, 已保留所有 equipment containers")
			return false

	for actor_id in actor_ids:
		var cid: int = _actor_equipment[actor_id]
		domain.unregister_equipment_container(cid)
		ItemSystem.unregister_container(cid)

	# 重建空容器
	_actor_equipment.clear()
	for actor_id in actor_ids:
		register_actor(actor_id)

	Log.info("HexPlayerInventory", "reset_actor_equipment_keep_player: %d actors 重建" % actor_ids.size())
	return true


## 整个 inventory 释放: 销毁所有 equipment container + player bag。
## 留 ItemSystem 自身 (sandbox exit 通常另调 ItemSystem.reset_session)。
##
## **注意**: dispose 会销毁所有 items (包括装备到 actor 上的)。需要保留 player bag
## 但清空 actor 装备的场景请用 reset_actor_equipment_keep_player。dispose 仅用于
## sandbox exit / scene 销毁。
func dispose() -> void:
	var domain := ItemSystem.get_domain() as HexItemDomain  # dispose 容忍 domain 已被替换
	for actor_id in _actor_equipment.keys():
		var cid: int = _actor_equipment[actor_id]
		if domain != null:
			domain.unregister_equipment_container(cid)
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
func _unload_equipment_to_bag(equipment_container_id: int) -> bool:
	if player_bag_id <= 0:
		return false
	var ok := true
	var items := ItemSystem.get_items_in_container(equipment_container_id)
	for item_id in items:
		var move_result := ItemSystem.move_item(item_id, player_bag_id, -1)
		if not move_result.success:
			ok = false
			Log.error("HexPlayerInventory",
				"卸装失败 (item %d eq=%d -> bag %d): %s — 视为 lifecycle bug, item 仍在 equipment container" % [
					item_id, equipment_container_id, player_bag_id, move_result.error_message
				])
	return ok
