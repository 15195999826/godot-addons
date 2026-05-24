## InventoryKit - 项目层物品实例数据基类
##
## 由 ItemDomain.create_instance_data 创建; ItemSystem 持有 item_id -> ItemInstanceData 映射。
## 项目侧继承本类扩展 game-specific 字段 (config_id / count / charges 等)。
class_name ItemInstanceData
extends RefCounted


## config 标识 (catalog key)
var config_id: StringName = &""

## 堆叠数量 (1 表示单实例)
var count: int = 1


func _init(p_config_id: StringName = &"", p_count: int = 1) -> void:
	config_id = p_config_id
	count = p_count
