## InventoryKit - 默认 domain (ItemSystem 未配置时使用)
##
## 不能堆叠、不允许 business create_item; 但底层 register_item_instance 仍可用。
class_name DefaultItemDomain
extends ItemDomain


func create_instance_data(config_id: StringName, count: int) -> ItemInstanceData:
	return ItemInstanceData.new(config_id, count)


func can_stack(_existing_item_id: int, _config_id: StringName) -> bool:
	return false


func merge_stack(_existing_data: ItemInstanceData, incoming_count: int, _max_stack: int) -> int:
	return incoming_count


func can_create_item(_config_id: StringName, _container_id: int, _slot_index: int, _count: int) -> ContainerResult:
	return ContainerResult.ok(true)


func can_move_item(_item_id: int, _target_container_id: int, _target_slot_index: int) -> ContainerResult:
	return ContainerResult.ok(true)


func build_item_snapshot(item_id: int, data: ItemInstanceData) -> Dictionary:
	return {
		"item_id": item_id,
		"config_id": data.config_id,
		"count": data.count,
	}
