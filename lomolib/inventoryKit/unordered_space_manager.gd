## InventoryKit - 无序容器空间管理器
##
## 不关心物品的具体位置，所有物品使用统一槽位索引（0）
## 适用于背包等不关注物品顺序的场景
class_name UnorderedSpaceManager
extends SpaceManager


func _init(cfg: ContainerSpaceConfig) -> void:
	super(cfg)
	_initialize()


func _initialize() -> void:
	item_count = 0


## 获取容量
func get_capacity() -> int:
	return config.capacity if config != null else -1


## 检查指定槽位是否可用
## 无序容器只使用槽位 0，只要有容量即可
func is_slot_available(slot_index: int) -> bool:
	if slot_index != 0:
		return false
	return not is_full()


## 标记槽位为已占用
func mark_slot_occupied(slot_index: int) -> void:
	if slot_index == 0:
		add_item_count()


## 标记槽位为可用
func mark_slot_available(slot_index: int) -> void:
	if slot_index == 0:
		remove_item_count()


## 获取第一个可用槽位
func get_first_available_slot() -> int:
	return 0 if is_slot_available(0) else -1


## 获取槽位总数
func get_total_slots() -> int:
	var cap := get_capacity()
	return cap if cap >= 0 else 0
