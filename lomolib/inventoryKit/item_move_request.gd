## InventoryKit - 物品移动请求
##
## 描述物品移动操作的详细信息
class_name ItemMoveRequest
extends RefCounted

## 物品ID
var item_id: int = -1

## 目标容器ID
var target_container_id: int = -1

## 目标槽位索引
var target_slot_index: int = -1


func _init(iid: int = -1, target_cid: int = -1, target_idx: int = -1) -> void:
	item_id = iid
	target_container_id = target_cid
	target_slot_index = target_idx


## 转换为字符串表示
func to_string() -> String:
	return "ItemMoveRequest(ItemID=%d, TargetContainer=%d, TargetSlot=%d)" % [
		item_id, target_container_id, target_slot_index
	]
