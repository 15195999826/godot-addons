## InventoryKit - 物品 catalog 扩展点
##
## 项目侧实现 config_id -> item config Dictionary 的查询。
## 框架不规定字段; plan 推荐最小集 = id / display_name / icon_key / max_stack /
## item_tags / equipable。
class_name ItemCatalog
extends RefCounted


## 是否含有指定 config_id
func has_config(_config_id: StringName) -> bool:
	return false


## 返回 config Dictionary 副本; 未找到返回空 Dictionary
func get_config(_config_id: StringName) -> Dictionary:
	return {}


## 列出所有已知 config_id (debug / DevAgent 用)
func list_config_ids() -> Array[StringName]:
	var empty: Array[StringName] = []
	return empty
