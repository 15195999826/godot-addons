## InventoryKit - 物品基础实例结构
##
## 描述物品的基本信息
class_name ItemInstance
extends RefCounted

## 物品唯一ID
var item_id: int = -1

## 物品位置
var location: ItemLocation

## 物品类型标识（用于区分不同类型的物品）
var item_type: StringName = &""

## 物品数据（可扩展字段，用于存储自定义数据）
var metadata: Dictionary = {}


func _init(id: int = -1, loc: ItemLocation = null, type: StringName = &"") -> void:
	item_id = id
	location = loc if loc != null else ItemLocation.new()
	item_type = type


## 转换为字符串表示
func to_string() -> String:
	return "ItemInstance(ID=%d, Type=%s, %s)" % [item_id, item_type, location.to_string()]


## 设置元数据
func set_metadata(key: StringName, value: Variant) -> void:
	metadata[key] = value


## 获取元数据
func get_metadata(key: StringName, default_value: Variant = null) -> Variant:
	if metadata.has(key):
		return metadata[key]
	return default_value
