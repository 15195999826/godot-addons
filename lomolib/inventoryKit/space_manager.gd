## InventoryKit - 容器空间管理器基类
##
## 空间管理器负责管理容器中的槽位空间和物品布局策略
## 所有空间管理器继承自此基类
class_name SpaceManager
extends RefCounted

## 容器配置
var config: ContainerSpaceConfig

## 当前物品数量
var item_count: int = 0


func _init(cfg: ContainerSpaceConfig) -> void:
	config = cfg


## 初始化空间管理器
## 子类可以重写此方法进行初始化
func _initialize() -> void:
	pass


## 获取容器空间类型
func get_space_type() -> ContainerSpaceType.ContainerSpaceType:
	return config.space_type if config != null else ContainerSpaceType.ContainerSpaceType.UNORDERED


## 获取容量
## 返回 -1 表示无限容量
func get_capacity() -> int:
	return -1


## 获取当前物品数量
func get_item_count() -> int:
	return item_count


## 增加物品计数
func add_item_count(delta: int = 1) -> void:
	item_count += delta


## 减少物品计数
func remove_item_count(delta: int = 1) -> void:
	item_count = max(0, item_count - delta)


## 检查是否已满
func is_full() -> bool:
	var cap := get_capacity()
	return cap >= 0 and item_count >= cap


## 检查是否为空
func is_empty() -> bool:
	return item_count == 0


## 检查指定槽位是否可用
## [param slot_index] 槽位索引
## [return] 如果槽位可用返回 true，否则返回 false
func is_slot_available(slot_index: int) -> bool:
	push_error("SpaceManager.is_slot_available() 必须由子类实现")
	return false


## 标记槽位为已占用
## [param slot_index] 槽位索引
func mark_slot_occupied(slot_index: int) -> void:
	push_error("SpaceManager.mark_slot_occupied() 必须由子类实现")


## 标记槽位为可用
## [param slot_index] 槽位索引
func mark_slot_available(slot_index: int) -> void:
	push_error("SpaceManager.mark_slot_available() 必须由子类实现")


## 获取第一个可用槽位
## [return] 返回可用槽位索引，如果没有可用槽位返回 -1
func get_first_available_slot() -> int:
	push_error("SpaceManager.get_first_available_slot() 必须由子类实现")
	return -1


## 槽位索引转坐标（用于网格容器）
## [param slot_index] 槽位索引
## [return] 返回包含 x 和 y 的字典
func index_to_coordinate(slot_index: int) -> Dictionary:
	push_error("SpaceManager.index_to_coordinate() 必须由子类实现")
	return {"x": -1, "y": -1}


## 坐标转槽位索引（用于网格容器）
## [param x] X 坐标
## [param y] Y 坐标
## [return] 返回槽位索引
func coordinate_to_index(x: int, y: int) -> int:
	push_error("SpaceManager.coordinate_to_index() 必须由子类实现")
	return -1


## 获取槽位总数
func get_total_slots() -> int:
	push_error("SpaceManager.get_total_slots() 必须由子类实现")
	return 0


## 清空所有槽位
func clear() -> void:
	item_count = 0


## 转换为字符串表示
func to_string() -> String:
	return "SpaceManager(Type=%s, Items=%d)" % [
		ContainerSpaceType.ContainerSpaceType.keys()[get_space_type()], item_count
	]
