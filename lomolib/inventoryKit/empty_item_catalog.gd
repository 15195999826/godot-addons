## InventoryKit - 空 catalog (ItemSystem 未配置时的默认)
##
## 所有查询返回空; business create_item 在未配置 catalog 时会失败。
## register_item_instance 底层 API 不受 catalog 限制,可用于底层 InventoryKit 测试。
class_name EmptyItemCatalog
extends ItemCatalog


func has_config(_config_id: StringName) -> bool:
	return false


func get_config(_config_id: StringName) -> Dictionary:
	return {}


func list_config_ids() -> Array[StringName]:
	var empty: Array[StringName] = []
	return empty
