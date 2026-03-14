## InventoryKit - 基础容器组件
##
## 容器是物品的存储位置，可以是背包、装备栏、箱子等
## 所有容器都继承自此基类

class_name BaseContainer
extends Node

## 容器ID（由物品系统自动分配）
var container_id: int = -1

## 容器名称（用于调试和识别）
var container_name: StringName = &""

## 容器配置
var space_config: ContainerSpaceConfig

## 空间管理器
var space_manager: SpaceManager

## 物品ID缓存（本地维护，用于快速访问）
var item_ids: Array[int] = []

## 容器是否已初始化
var _is_initialized: bool = false


## 容器信号
## 物品添加时触发
signal item_added(item_id: int, slot_index: int)

## 物品移除时触发
signal item_removed(item_id: int, slot_index: int)

## 物品移动时触发（从当前容器移出到其他容器）
signal item_moved_out(item_id: int, target_container_id: int, target_slot_index: int)

## 物品移入时触发（从其他容器移入当前容器）
signal item_moved_in(item_id: int, source_container_id: int, source_slot_index: int)


## 初始化容器
## [param cid] 容器ID（由物品系统分配）
## [param name] 容器名称
## [param config] 容器空间配置
func init_container(cid: int, name: StringName, config: ContainerSpaceConfig) -> void:
	if _is_initialized:
		Log.warning("BaseContainer", "容器 %s 已初始化，跳过重复初始化" % name)
		return

	container_id = cid
	container_name = name
	space_config = config

	# 创建对应的空间管理器
	space_manager = _create_space_manager(config)
	if space_manager == null:
		Log.error("BaseContainer", "创建空间管理器失败: %s" % name)
		return

	_is_initialized = true
	Log.info("BaseContainer", "容器已初始化: ID=%d, Name=%s, Type=%s" % [
		container_id, container_name, ContainerSpaceType.ContainerSpaceType.keys()[config.space_type]
	])


## 创建空间管理器
## [param config] 容器空间配置
## [return] 返回对应的空间管理器实例
func _create_space_manager(config: ContainerSpaceConfig) -> SpaceManager:
	match config.space_type:
		ContainerSpaceType.ContainerSpaceType.UNORDERED:
			return UnorderedSpaceManager.new(config)
		ContainerSpaceType.ContainerSpaceType.FIXED:
			return FixedSlotSpaceManager.new(config)
		ContainerSpaceType.ContainerSpaceType.GRID:
			return GridSpaceManager.new(config)
		_:
			push_error("未知的容器空间类型: %d" % config.space_type)
			return null


## 获取容器ID
func get_container_id() -> int:
	return container_id


## 获取容器名称
func get_container_name() -> StringName:
	return container_name


## 获取空间管理器
func get_space_manager() -> SpaceManager:
	return space_manager


## 获取所有物品ID
## [return] 返回物品ID数组的副本
func get_all_items() -> Array[int]:
	return item_ids.duplicate()


## 获取物品数量
func get_item_count() -> int:
	return item_ids.size()


## 检查容器是否为空
func is_empty() -> bool:
	return item_ids.is_empty()


## 检查容器是否已满
func is_full() -> bool:
	if space_manager == null:
		return true
	return space_manager.is_full()


## 检查是否可以添加物品到指定槽位
## [param item_id] 物品ID
## [param slot_index] 目标槽位索引
## [return] 返回操作结果
func can_add_item(item_id: int, slot_index: int = -1) -> ContainerResult:
	if not _is_initialized:
		return ContainerResult.fail("容器未初始化")

	if space_manager == null:
		return ContainerResult.fail("空间管理器为空")

	# 检查槽位是否可用
	if slot_index >= 0:
		if not space_manager.is_slot_available(slot_index):
			return ContainerResult.fail("槽位 %d 不可用" % slot_index)
	else:
		# 自动查找可用槽位
		var available_slot := space_manager.get_first_available_slot()
		if available_slot < 0:
			return ContainerResult.fail("无可用槽位")

	return ContainerResult.ok(true)


## 检查是否可以移动物品到指定槽位
## [param item_id] 物品ID
## [param slot_index] 目标槽位索引
## [return] 返回操作结果
func can_move_item(item_id: int, slot_index: int = -1) -> ContainerResult:
	# 对于基础容器，移动和添加的逻辑相同
	return can_add_item(item_id, slot_index)


## 物品添加通知（由物品系统调用）
## [param item_id] 物品ID
## [param slot_index] 槽位索引
func on_item_added(item_id: int, slot_index: int) -> void:
	if not item_ids.has(item_id):
		item_ids.append(item_id)

	# 更新空间管理器状态
	if space_manager != null and slot_index >= 0:
		space_manager.mark_slot_occupied(slot_index)

	item_added.emit(item_id, slot_index)
	Log.debug("BaseContainer", "容器 %s 添加物品: ID=%d, Slot=%d" % [container_name, item_id, slot_index])


## 物品移动通知（从当前容器移出）
## [param item_id] 物品ID
## [param target_container_id] 目标容器ID
## [param target_slot_index] 目标槽位索引
func on_item_moved_out(item_id: int, target_container_id: int, target_slot_index: int) -> void:
	var slot_index := _get_item_slot_index(item_id)

	# 从本地缓存中移除
	item_ids.erase(item_id)

	# 更新空间管理器状态
	if space_manager != null and slot_index >= 0:
		space_manager.mark_slot_available(slot_index)

	item_moved_out.emit(item_id, target_container_id, target_slot_index)
	Log.debug("BaseContainer", "容器 %s 移出物品: ID=%d -> ContainerID=%d" % [
		container_name, item_id, target_container_id
	])


## 物品移入通知（从其他容器移入）
## [param item_id] 物品ID
## [param source_container_id] 源容器ID
## [param source_slot_index] 源槽位索引
## [param target_slot_index] 目标槽位索引
func on_item_moved_in(item_id: int, source_container_id: int, source_slot_index: int, target_slot_index: int) -> void:
	if not item_ids.has(item_id):
		item_ids.append(item_id)

	# 更新空间管理器状态
	if space_manager != null and target_slot_index >= 0:
		space_manager.mark_slot_occupied(target_slot_index)

	item_moved_in.emit(item_id, source_container_id, source_slot_index)
	Log.debug("BaseContainer", "容器 %s 移入物品: ID=%d <- ContainerID=%d" % [
		container_name, item_id, source_container_id
	])


## 物品移除通知（由物品系统调用）
## [param item_id] 物品ID
func on_item_removed(item_id: int) -> void:
	var slot_index := _get_item_slot_index(item_id)

	# 从本地缓存中移除
	item_ids.erase(item_id)

	# 更新空间管理器状态
	if space_manager != null and slot_index >= 0:
		space_manager.mark_slot_available(slot_index)

	item_removed.emit(item_id, slot_index)
	Log.debug("BaseContainer", "容器 %s 移除物品: ID=%d" % [container_name, item_id])


## 获取物品所在的槽位索引
## [param item_id] 物品ID
## [return] 返回槽位索引，如果未找到返回 -1
func _get_item_slot_index(item_id: int) -> int:
	# 对于无序容器，总是返回 0
	if space_manager != null and space_manager.get_space_type() == ContainerSpaceType.ContainerSpaceType.UNORDERED:
		return 0

	# 对于固定槽位和网格容器，需要查询物品系统
	if ItemSystem != null:
		var item_instance := ItemSystem.get_item_instance(item_id)
		if item_instance != null and item_instance.location != null:
			return item_instance.location.slot_index

	return -1


## 清空容器
func clear() -> void:
	item_ids.clear()
	if space_manager != null:
		space_manager.clear()
	Log.debug("BaseContainer", "容器 %s 已清空" % container_name)


## 转换为字符串表示
func to_string() -> String:
	return "BaseContainer(ID=%d, Name=%s, Items=%d)" % [
		container_id, container_name, item_ids.size()
	]


## ============================================
## 容器工厂方法
## ============================================

## 创建容器实例
## [param name] 容器名称
## [param config] 容器空间配置
## [return] 返回创建的容器实例
static func create(name: StringName, config: ContainerSpaceConfig) -> BaseContainer:
	var container := BaseContainer.new()
	container.container_name = name
	container.space_config = config
	container.space_manager = container._create_space_manager(config)
	return container


## 创建无序容器（背包等）
## [param name] 容器名称
## [param capacity] 容量（-1 表示无限）
## [return] 返回创建的容器实例
static func create_unordered(name: StringName, capacity: int = -1) -> BaseContainer:
	var config := ContainerSpaceConfig.create_unordered(capacity)
	return create(name, config)


## 创建固定槽位容器（装备栏等）
## [param name] 容器名称
## [param slot_types] 槽位类型数组
## [return] 返回创建的容器实例
static func create_fixed(name: StringName, slot_types: Array[StringName]) -> BaseContainer:
	var config := ContainerSpaceConfig.create_fixed(slot_types)
	return create(name, config)


## 创建网格容器（二维库存）
## [param name] 容器名称
## [param width] 网格宽度
## [param height] 网格高度
## [return] 返回创建的容器实例
static func create_grid(name: StringName, width: int, height: int) -> BaseContainer:
	var config := ContainerSpaceConfig.create_grid(width, height)
	return create(name, config)
