## HexItemDomain - Hex 示例的 ItemDomain 实现
##
## 通过 `ItemSystem.configure_domain(HexItemDomain.new(), HexItemCatalog.new())`
## 注册项目规则。本类只处理 stack / equipable / snapshot,不持有 actor / container
## lifecycle (那些归 HexPlayerInventory + sandbox scene orchestration)。
##
## V1 规则:
## - 同 config 的 item 可以 stack (受 max_stack 限制)
## - merge_stack mutate existing_data.count, 返回未合并的 incoming count
## - can_move_item: 目标是 equipment container 时,要求 catalog config equipable
##   (具体 6-slot 校验和 occupied 检查归 HexActorEquipmentContainer.can_add_item)
## - snapshot 补充 equipable / item_tags / max_stack / display_name (大部分由
##   ItemSystem.get_item_snapshot 已经合并;这里给 domain-specific 字段留出口)
class_name HexItemDomain
extends ItemDomain


## 用于 can_move_item 决策: equipment container_id 集合;由
## HexPlayerInventory 在创建 / 销毁 actor equipment container 时维护。
## 不持有 container 引用,只记 id (避免 dangling reference)。
## 外部只读;mutate 走 register/unregister_equipment_container API。
var _equipment_container_ids: Dictionary = {}  # int -> bool (set语义)


## HexPlayerInventory 创建 actor 装备容器时调用
func register_equipment_container(container_id: int) -> void:
	_equipment_container_ids[container_id] = true


## HexPlayerInventory 销毁 actor 装备容器时调用
func unregister_equipment_container(container_id: int) -> void:
	_equipment_container_ids.erase(container_id)


## debug / smoke 用: 查询某 container_id 是否登记为 equipment container
func has_equipment_container(container_id: int) -> bool:
	return _equipment_container_ids.has(container_id)


## ItemSystem.reset_session() 调用时被调,清理本 domain 内的 stale state。
## 避免 "复用 domain 实例 + 重新 configure_domain" 场景下旧 equipment ids 残留。
func reset() -> void:
	_equipment_container_ids.clear()


func create_instance_data(config_id: StringName, count: int) -> ItemInstanceData:
	return HexItemInstanceData.new(config_id, count)


func can_stack(_existing_item_id: int, _config_id: StringName) -> bool:
	return true


## 严格遵守 ItemDomain.merge_stack 合约: mutate existing_data.count, 返回 leftover
func merge_stack(existing_data: ItemInstanceData, incoming_count: int, max_stack: int) -> int:
	var room: int = max(0, max_stack - existing_data.count)
	var to_merge: int = min(incoming_count, room)
	existing_data.count += to_merge
	return incoming_count - to_merge


func can_create_item(_config_id: StringName, _container_id: int, _slot_index: int, _count: int) -> ContainerResult:
	# V1 没有禁止创建的规则; equipable 之类的检查在 move_item 阶段
	return ContainerResult.ok(true)


## 目标 = equipment container 时, item 必须 equipable 且 granted_abilities 全部可解析。
##
## Phase G: granted_abilities[*].ability_config_id 必须由
## HexEquipmentAbilityResolver 全部解析为已注册 AbilityConfig, 否则 reject move
## (Plan §"callback 不能承担失败回滚": 进入 container callback 前必须预校验完毕,
## 防止 grant 一半失败后无法回滚)。
func can_move_item(item_id: int, target_container_id: int, _target_slot_index: int) -> ContainerResult:
	if not _equipment_container_ids.has(target_container_id):
		return ContainerResult.ok(true)

	# 走 equipment 路径: 必须 equipable
	var data := ItemSystem.get_item_data(item_id) as ItemInstanceData
	if data == null:
		return ContainerResult.fail("item %d 无 instance data,无法装备" % item_id)

	var cfg := ItemSystem.get_item_config(data.config_id)
	if not bool(cfg.get("equipable", false)):
		return ContainerResult.fail("item %s 不可装备" % str(data.config_id))

	# Phase G: granted_abilities 预校验 — 任一 ability_config_id 无法解析 → reject
	var granted: Variant = cfg.get("granted_abilities", null)
	if not HexEquipmentAbilityResolver.resolve_all_ok(granted):
		return ContainerResult.fail(
			"item %s granted_abilities 含未注册 ability_config_id, 无法装备" % str(data.config_id)
		)

	return ContainerResult.ok(true)


func build_item_snapshot(_item_id: int, _data: ItemInstanceData) -> Dictionary:
	# 大部分字段 ItemSystem.get_item_snapshot 已合并;这里留 domain-specific
	# 字段位 (本轮无附加字段)。返回 {} 不覆盖 base snapshot。
	return {}
