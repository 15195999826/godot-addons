## InventoryKit - 物品系统
##
## 物品系统是库存框架的核心权威数据源
## 负责管理所有物品的创建、移动、查询和销毁
## 作为 AutoLoad 单例运行

extends Node

## ============================================
## 信号定义
## ============================================

## 物品创建时触发
signal item_created(item_id: int, location: ItemLocation)

## 物品移动时触发
signal item_moved(item_id: int, old_location: ItemLocation, new_location: ItemLocation)

## 物品销毁时触发
signal item_destroyed(item_id: int)

## 容器注册时触发
signal container_registered(container_id: int, container_name: StringName)

## 容器注销时触发
signal container_unregistered(container_id: int)


## ============================================
## 内部数据
## ============================================

## 物品ID计数器（用于生成唯一物品ID）
var _next_item_id: int = 1

## 容器ID计数器（用于生成唯一容器ID）
var _next_container_id: int = 1

## 物品映射表: item_id -> ItemInstance
var _item_map: Dictionary = {}  # int -> ItemInstance

## 容器映射表: container_id -> BaseContainer
var _container_map: Dictionary = {}  # int -> BaseContainer

## 虚空容器（用于存放无容器的物品）
var _void_container: BaseContainer


## ============================================
## 初始化
## ============================================

func _ready() -> void:
	Log.info("ItemSystem", "物品系统初始化")

	# 创建虚空容器
	_void_container = BaseContainer.new()
	_void_container.init_container(0, &"VoidContainer", ContainerSpaceConfig.create_unordered(-1))
	_container_map[0] = _void_container

	Log.info("ItemSystem", "虚空容器已创建 (ContainerID=0)")


func _exit_tree() -> void:
	Log.info("ItemSystem", "物品系统开始清理")
	
	# 1. 清理所有非虚空容器
	var container_ids := _container_map.keys()
	for container_id in container_ids:
		if container_id != 0:  # 跳过虚空容器
			unregister_container(container_id)
	
	# 2. 清理所有物品
	var item_ids := _item_map.keys()
	for item_id in item_ids:
		_item_map.erase(item_id)
	
	# 3. 清理虚空容器（最后清理）
	if _void_container:
		_void_container.clear()
		_void_container.queue_free()  # 关键：释放 Node 实例
		_void_container = null
	
	# 4. 清空映射表
	_item_map.clear()
	_container_map.clear()
	
	Log.info("ItemSystem", "物品系统已清理")


## ============================================
## 容器管理
## ============================================

## 注册容器到物品系统
## [param container] 容器实例
## [return] 返回分配的容器ID，失败返回 -1
func register_container(container: BaseContainer) -> int:
	if container == null:
		Log.error("ItemSystem", "注册容器失败：容器为 null")
		return -1

	if container.container_id >= 0 and _container_map.has(container.container_id):
		Log.warning("ItemSystem", "容器 %s 已注册，跳过" % container.container_name)
		return container.container_id

	# 分配容器ID
	var container_id := _next_container_id
	_next_container_id += 1

	# 初始化容器
	container.init_container(container_id, container.container_name, container.space_config)

	# 添加到容器映射表
	_container_map[container_id] = container

	container_registered.emit(container_id, container.container_name)
	Log.info("ItemSystem", "容器已注册: ID=%d, Name=%s" % [container_id, container.container_name])

	return container_id


## 注销容器
## [param container_id] 容器ID
## [return] 成功返回 true，失败返回 false
func unregister_container(container_id: int) -> bool:
	if container_id == 0:
		Log.error("ItemSystem", "不能注销虚空容器")
		return false

	if not _container_map.has(container_id):
		Log.warning("ItemSystem", "容器不存在: ID=%d" % container_id)
		return false

	var container: BaseContainer = _container_map[container_id]

	# 移除容器中的所有物品
	var items := container.get_all_items()
	for item_id in items:
		destroy_item(item_id)

	# 从映射表中移除
	_container_map.erase(container_id)

	container_unregistered.emit(container_id)
	Log.info("ItemSystem", "容器已注销: ID=%d, Name=%s" % [container_id, container.container_name])

	return true


## 获取容器实例
## [param container_id] 容器ID
## [return] 返回容器实例，不存在返回 null
func get_container(container_id: int) -> BaseContainer:
	if _container_map.has(container_id):
		return _container_map[container_id]
	return null


## 获取所有已注册的容器ID
## [return] 返回容器ID数组
func get_all_containers() -> Array[int]:
	var container_ids: Array[int] = []
	for cid in _container_map.keys():
		container_ids.append(int(cid))
	return container_ids


## ============================================
## 物品管理
## ============================================

## 创建物品
## [param container_id] 目标容器ID
## [param slot_index] 目标槽位索引（-1 表示自动分配）
## [param item_type] 物品类型
## [param notify] 是否通知容器（默认 true）
## [return] 返回创建的物品ID，失败返回 -1
func create_item(container_id: int, slot_index: int = -1, item_type: StringName = &"", notify: bool = true) -> int:
	var container := get_container(container_id)
	if container == null:
		Log.error("ItemSystem", "创建物品失败：容器不存在 ID=%d" % container_id)
		return -1

	# 检查容器是否可接受物品
	var can_add_result := container.can_add_item(-1, slot_index)
	if not can_add_result.success:
		Log.warning("ItemSystem", "创建物品失败：%s" % can_add_result.error_message)
		return -1

	# 自动分配槽位
	if slot_index < 0:
		var space_manager := container.get_space_manager()
		if space_manager != null:
			slot_index = space_manager.get_first_available_slot()

	# 生成物品ID
	var item_id := _next_item_id
	_next_item_id += 1

	# 创建物品位置
	var location := ItemLocation.new(container_id, slot_index)

	# 创建物品实例
	var item_instance := ItemInstance.new(item_id, location, item_type)

	# 添加到物品映射表
	_item_map[item_id] = item_instance

	# 通知容器
	if notify:
		container.on_item_added(item_id, slot_index)

	item_created.emit(item_id, location)
	Log.debug("ItemSystem", "物品已创建: ID=%d, Type=%s, Location=Container%d:%d" % [
		item_id, item_type, container_id, slot_index
	])

	return item_id


## 移动物品
## [param item_id] 物品ID
## [param target_container_id] 目标容器ID
## [param target_slot_index] 目标槽位索引（-1 表示自动分配）
## [return] 成功返回 true，失败返回 false
func move_item(item_id: int, target_container_id: int, target_slot_index: int = -1) -> bool:
	# 验证物品存在
	if not _item_map.has(item_id):
		Log.error("ItemSystem", "移动物品失败：物品不存在 ID=%d" % item_id)
		return false

	var item_instance: ItemInstance = _item_map[item_id]
	var old_location := item_instance.location.duplicate()
	var source_container_id := old_location.container_id

	# 验证源容器存在
	var source_container := get_container(source_container_id)
	if source_container == null:
		Log.error("ItemSystem", "移动物品失败：源容器不存在 ID=%d" % source_container_id)
		return false

	# 如果目标容器相同，只更新槽位
	if target_container_id == source_container_id:
		return _move_item_within_container(item_id, source_container, old_location.slot_index, target_slot_index)

	# 验证目标容器存在
	var target_container := get_container(target_container_id)
	if target_container == null:
		Log.error("ItemSystem", "移动物品失败：目标容器不存在 ID=%d" % target_container_id)
		return false

	# 检查目标容器是否可接受物品
	var can_add_result := target_container.can_add_item(item_id, target_slot_index)
	if not can_add_result.success:
		Log.warning("ItemSystem", "移动物品失败：%s" % can_add_result.error_message)
		return false

	# 自动分配槽位
	if target_slot_index < 0:
		var space_manager := target_container.get_space_manager()
		if space_manager != null:
			target_slot_index = space_manager.get_first_available_slot()

	# 通知源容器物品移出
	source_container.on_item_moved_out(item_id, target_container_id, target_slot_index)

	# 通知目标容器物品移入
	target_container.on_item_moved_in(item_id, source_container_id, old_location.slot_index, target_slot_index)

	# 更新物品位置
	var new_location := ItemLocation.new(target_container_id, target_slot_index)
	item_instance.location = new_location

	item_moved.emit(item_id, old_location, new_location)
	Log.debug("ItemSystem", "物品已移动: ID=%d, Container%d:%d -> Container%d:%d" % [
		item_id, source_container_id, old_location.slot_index, target_container_id, target_slot_index
	])

	return true


## 在同一容器内移动物品
func _move_item_within_container(item_id: int, container: BaseContainer, old_slot: int, new_slot: int) -> bool:
	if new_slot < 0:
		var space_manager := container.get_space_manager()
		if space_manager != null:
			new_slot = space_manager.get_first_available_slot()

	if new_slot < 0:
		Log.warning("ItemSystem", "移动物品失败：无可用槽位")
		return false

	var item_instance: ItemInstance = _item_map[item_id]
	var old_location := item_instance.location.duplicate()

	# 更新物品位置
	item_instance.location.slot_index = new_slot

	item_moved.emit(item_id, old_location, item_instance.location)
	Log.debug("ItemSystem", "物品已移动（同容器）: ID=%d, Container%d:%d -> %d" % [
		item_id, container.container_id, old_slot, new_slot
	])

	return true


## 销毁物品
## [param item_id] 物品ID
## [return] 成功返回 true，失败返回 false
func destroy_item(item_id: int) -> bool:
	if not _item_map.has(item_id):
		Log.warning("ItemSystem", "销毁物品失败：物品不存在 ID=%d" % item_id)
		return false

	var item_instance: ItemInstance = _item_map[item_id]
	var location := item_instance.location
	var container := get_container(location.container_id)

	if container != null:
		container.on_item_removed(item_id)

	# 从物品映射表中移除
	_item_map.erase(item_id)

	item_destroyed.emit(item_id)
	Log.debug("ItemSystem", "物品已销毁: ID=%d" % item_id)

	return true


## ============================================
## 查询接口
## ============================================

## 获取物品位置
## [param item_id] 物品ID
## [return] 返回物品位置的副本，物品不存在返回 null
func get_item_location(item_id: int) -> ItemLocation:
	if not _item_map.has(item_id):
		return null
	var item_instance: ItemInstance = _item_map[item_id]
	return item_instance.location.duplicate()


## 获取物品实例
## [param item_id] 物品ID
## [return] 返回物品实例，不存在返回 null
func get_item_instance(item_id: int) -> ItemInstance:
	if _item_map.has(item_id):
		return _item_map[item_id]
	return null


## 获取容器中的所有物品
## [param container_id] 容器ID
## [return] 返回物品ID数组
func get_items_in_container(container_id: int) -> Array[int]:
	var container := get_container(container_id)
	if container == null:
		return []
	return container.get_all_items()


## 检查物品是否存在
## [param item_id] 物品ID
## [return] 存在返回 true，否则返回 false
func item_exists(item_id: int) -> bool:
	return _item_map.has(item_id)


## 获取物品总数
## [return] 返回物品总数
func get_total_item_count() -> int:
	return _item_map.size()


## ============================================
## 工具方法
## ============================================

## 转移物品（从源容器到目标容器）
## [param item_id] 物品ID
## [param target_container_id] 目标容器ID
## [return] 成功返回 true，失败返回 false
func transfer_item(item_id: int, target_container_id: int) -> bool:
	return move_item(item_id, target_container_id, -1)


## 批量转移物品
## [param source_container_id] 源容器ID
## [param target_container_id] 目标容器ID
## [return] 返回成功转移的物品数量
func transfer_all_items(source_container_id: int, target_container_id: int) -> int:
	var source_container := get_container(source_container_id)
	var target_container := get_container(target_container_id)

	if source_container == null or target_container == null:
		Log.error("ItemSystem", "批量转移失败：容器不存在")
		return 0

	var items := source_container.get_all_items()
	var transferred_count := 0

	for item_id in items:
		if move_item(item_id, target_container_id):
			transferred_count += 1

	Log.info("ItemSystem", "批量转移完成: Container%d -> Container%d, 转移 %d/%d 个物品" % [
		source_container_id, target_container_id, transferred_count, items.size()
	])

	return transferred_count


## 清空容器
## [param container_id] 容器ID
## [return] 返回销毁的物品数量
func clear_container(container_id: int) -> int:
	var container := get_container(container_id)
	if container == null:
		return 0

	var items := container.get_all_items()
	var destroyed_count := 0

	for item_id in items:
		if destroy_item(item_id):
			destroyed_count += 1

	Log.info("ItemSystem", "容器已清空: ID=%d, 销毁 %d 个物品" % [container_id, destroyed_count])

	return destroyed_count


## ============================================
## 调试方法
## ============================================

## 获取系统状态信息
## [return] 返回系统状态字典
func get_system_status() -> Dictionary:
	return {
		"total_items": _item_map.size(),
		"total_containers": _container_map.size(),
		"next_item_id": _next_item_id,
		"next_container_id": _next_container_id
	}


## 打印系统状态
func print_system_status() -> void:
	var status := get_system_status()
	print("=== ItemSystem 状态 ===")
	print("总物品数: %d" % status.total_items)
	print("总容器数: %d" % status.total_containers)
	print("下一个物品ID: %d" % status.next_item_id)
	print("下一个容器ID: %d" % status.next_container_id)
	print("=====================")
