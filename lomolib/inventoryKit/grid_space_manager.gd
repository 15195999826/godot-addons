## InventoryKit - 网格容器空间管理器
##
## 二维网格布局，支持坐标与索引的双向转换
## 适用于需要可视化布局的库存界面
class_name GridSpaceManager
extends SpaceManager

## 网格宽度
var grid_width: int = 0

## 网格高度
var grid_height: int = 0

## 槽位状态：0=可用，1=占用
var slot_flags: Array[int] = []


func _init(cfg: ContainerSpaceConfig) -> void:
	super(cfg)
	_initialize()


func _initialize() -> void:
	if config == null:
		return

	grid_width = config.grid_width
	grid_height = config.grid_height

	slot_flags.clear()
	var total_slots := grid_width * grid_height
	for i in range(total_slots):
		slot_flags.append(0)  # 初始状态：可用


## 获取槽位总数
func get_total_slots() -> int:
	return slot_flags.size()


## 获取容量
func get_capacity() -> int:
	return slot_flags.size()


## 坐标转索引
## [param x] X 坐标（列）
## [param y] Y 坐标（行）
## [return] 返回一维槽位索引
func coordinate_to_index(x: int, y: int) -> int:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return -1
	return y * grid_width + x


## 索引转坐标
## [param slot_index] 槽位索引
## [return] 返回包含 x 和 y 的字典
func index_to_coordinate(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slot_flags.size():
		return {"x": -1, "y": -1}
	return {"x": slot_index % grid_width, "y": slot_index / grid_width}


## 通过坐标获取槽位索引
## [param x] X 坐标（列）
## [param y] Y 坐标（行）
## [return] 返回一维槽位索引
func get_slot_index_by_xy(x: int, y: int) -> int:
	return coordinate_to_index(x, y)


## 检查指定槽位是否可用
func is_slot_available(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slot_flags.size():
		return false
	return slot_flags[slot_index] == 0


## 检查指定坐标是否可用
## [param x] X 坐标
## [param y] Y 坐标
func is_coordinate_available(x: int, y: int) -> bool:
	var idx := coordinate_to_index(x, y)
	return is_slot_available(idx)


## 标记槽位为已占用
func mark_slot_occupied(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < slot_flags.size():
		slot_flags[slot_index] = 1
		add_item_count()


## 标记坐标为已占用
## [param x] X 坐标
## [param y] Y 坐标
func mark_coordinate_occupied(x: int, y: int) -> void:
	var idx := coordinate_to_index(x, y)
	mark_slot_occupied(idx)


## 标记槽位为可用
func mark_slot_available(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < slot_flags.size():
		slot_flags[slot_index] = 0
		remove_item_count()


## 标记坐标为可用
## [param x] X 坐标
## [param y] Y 坐标
func mark_coordinate_available(x: int, y: int) -> void:
	var idx := coordinate_to_index(x, y)
	mark_slot_available(idx)


## 获取第一个可用槽位
func get_first_available_slot() -> int:
	for i in range(slot_flags.size()):
		if slot_flags[i] == 0:
			return i
	return -1


## 清空所有槽位
func clear() -> void:
	super.clear()
	for i in range(slot_flags.size()):
		slot_flags[i] = 0
