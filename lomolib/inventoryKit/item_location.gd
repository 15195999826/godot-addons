## InventoryKit - 物品位置结构
##
## 描述物品在库存系统中的位置
class_name ItemLocation
extends RefCounted

## 容器ID
var container_id: int = -1

## 槽位索引（-1 表示无特定槽位）
var slot_index: int = -1


func _init(cid: int = -1, idx: int = -1) -> void:
	container_id = cid
	slot_index = idx


## 是否为有效位置
func is_valid() -> bool:
	return container_id >= 0


## 转换为字符串表示
func to_string() -> String:
	return "ItemLocation(ContainerID=%d, SlotIndex=%d)" % [container_id, slot_index]


## 创建副本
func duplicate() -> ItemLocation:
	return ItemLocation.new(container_id, slot_index)


## 判断是否相同位置
func equals(other: ItemLocation) -> bool:
	if other == null:
		return false
	return container_id == other.container_id and slot_index == other.slot_index
