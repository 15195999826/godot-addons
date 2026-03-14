## InventoryKit - 固定槽位容器空间管理器
##
## 预定义固定数量的槽位，每个槽位对应特定的类型标签
## 适用于装备系统、快捷栏等场景
class_name FixedSlotSpaceManager
extends SpaceManager

## 槽位索引到类型标签的映射
var index_to_slot_type: Dictionary = {}  # int -> StringName

## 类型标签到槽位索引的映射
var slot_type_to_index: Dictionary = {}  # StringName -> int

## 槽位状态：0=可用，1=占用
var slot_flags: Array[int] = []


func _init(cfg: ContainerSpaceConfig) -> void:
	super(cfg)
	_initialize()


func _initialize() -> void:
	if config == null:
		return

	slot_flags.clear()
	index_to_slot_type.clear()
	slot_type_to_index.clear()

	for i in range(config.fixed_slot_types.size()):
		var slot_type: StringName = config.fixed_slot_types[i]
		index_to_slot_type[i] = slot_type
		slot_type_to_index[slot_type] = i
		slot_flags.append(0)  # 初始状态：可用


## 获取槽位总数
func get_total_slots() -> int:
	return slot_flags.size()


## 获取容量
func get_capacity() -> int:
	return slot_flags.size()


## 检查指定槽位是否可用
func is_slot_available(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slot_flags.size():
		return false
	return slot_flags[slot_index] == 0


## 标记槽位为已占用
func mark_slot_occupied(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < slot_flags.size():
		slot_flags[slot_index] = 1
		add_item_count()


## 标记槽位为可用
func mark_slot_available(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < slot_flags.size():
		slot_flags[slot_index] = 0
		remove_item_count()


## 获取第一个可用槽位
func get_first_available_slot() -> int:
	for i in range(slot_flags.size()):
		if slot_flags[i] == 0:
			return i
	return -1


## 根据类型获取槽位索引
## [param slot_type] 槽位类型标签
## [return] 返回槽位索引，如果不存在返回 -1
func get_slot_index_by_type(slot_type: StringName) -> int:
	if slot_type_to_index.has(slot_type):
		return slot_type_to_index[slot_type]
	return -1


## 根据槽位索引获取类型
## [param slot_index] 槽位索引
## [return] 返回类型标签，如果不存在返回空 StringName
func get_slot_type_by_index(slot_index: int) -> StringName:
	if index_to_slot_type.has(slot_index):
		return index_to_slot_type[slot_index]
	return &""


## 清空所有槽位
func clear() -> void:
	super.clear()
	for i in range(slot_flags.size()):
		slot_flags[i] = 0
