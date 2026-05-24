## InventoryKit - 物品系统 (autoload)
##
## 唯一 item runtime: 持 item id / container id / item location / item instance data;
## 通过 configure_domain(ItemDomain, ItemCatalog) 接入项目规则。
##
## API 分层:
## - 底层 (InventoryKit 自身 / 底层测试可直接调用):
##     register_item_instance(container_id, slot_index, item_type, notify) -> int
##     register_container / unregister_container / get_container ...
## - 业务 (项目通过 configure_domain 注册规则后使用):
##     create_item(container_id, config_id, count, slot_index) -> ItemCreateResult
##     move_item(item_id, target_container_id, target_slot_index) -> ItemMoveResult
##     destroy_item(item_id) -> bool
##     get_item_data(item_id) -> ItemInstanceData
##     get_item_config(config_id) -> Dictionary
##     get_item_snapshot(item_id) -> Dictionary
##     configure_domain(domain, catalog) -> void
##     reset_session() -> void
##
## callback / signal 顺序约定见 ItemDomain 头部文档。
extends Node


## ============================================
## 信号定义
## ============================================

signal item_created(item_id: int, location: ItemLocation)
signal item_moved(item_id: int, old_location: ItemLocation, new_location: ItemLocation)
signal item_destroyed(item_id: int)
signal container_registered(container_id: int, container_name: StringName)
signal container_unregistered(container_id: int)


## ============================================
## 内部数据
## ============================================

var _next_item_id: int = 1
var _next_container_id: int = 1
var _item_map: Dictionary = {}  # int -> ItemInstance
var _container_map: Dictionary = {}  # int -> BaseContainer
var _void_container: BaseContainer

## 项目层 instance data: item_id -> ItemInstanceData (业务 create_item 写入)
var _item_data_by_id: Dictionary = {}  # int -> ItemInstanceData

## domain / catalog (configure_domain 注册; 默认 no-op)
var _domain: ItemDomain
var _catalog: ItemCatalog


## ============================================
## 初始化
## ============================================

func _ready() -> void:
	Log.info("ItemSystem", "物品系统初始化")

	_domain = DefaultItemDomain.new()
	_catalog = EmptyItemCatalog.new()

	_void_container = BaseContainer.new()
	_void_container.init_container(0, &"VoidContainer", ContainerSpaceConfig.create_unordered(-1))
	_container_map[0] = _void_container

	Log.info("ItemSystem", "虚空容器已创建 (ContainerID=0)")


func _exit_tree() -> void:
	Log.info("ItemSystem", "物品系统开始清理")

	# 1. 清理所有非虚空容器
	var container_ids := _container_map.keys()
	for container_id in container_ids:
		if container_id != 0:
			unregister_container(container_id)

	# 2. 清理所有物品
	var item_ids := _item_map.keys()
	for item_id in item_ids:
		_item_map.erase(item_id)
	_item_data_by_id.clear()

	# 3. 清理虚空容器
	if _void_container:
		_void_container.clear()
		_void_container.queue_free()
		_void_container = null

	# 4. 清空映射表
	_item_map.clear()
	_container_map.clear()

	Log.info("ItemSystem", "物品系统已清理")


## ============================================
## Domain 配置 / 会话生命周期
## ============================================

## 注册项目规则; 不会清理已有 items/containers (那是 reset_session 的事)
func configure_domain(domain: ItemDomain, catalog: ItemCatalog) -> void:
	_domain = domain if domain != null else DefaultItemDomain.new()
	_catalog = catalog if catalog != null else EmptyItemCatalog.new()
	Log.info("ItemSystem", "domain 已配置: %s + catalog: %s" % [_domain.get_class(), _catalog.get_class()])


## 完整 teardown: 销毁本轮 tracked items + tracked containers + instance data + domain state
## 之后 ItemSystem 回到 ready 状态 (void container 保留, domain/catalog 复位为 default)
func reset_session() -> void:
	Log.info("ItemSystem", "reset_session: 清理本轮所有 containers/items/data")

	# 1. 清理所有非虚空容器 (会顺带 destroy_item 容器内 items)
	var container_ids := _container_map.keys()
	for container_id in container_ids:
		if container_id != 0:
			unregister_container(container_id)

	# 2. 兜底清理 item_map / data_map (理论上 unregister_container 已经清光)
	var item_ids := _item_map.keys()
	for item_id in item_ids:
		_item_map.erase(item_id)
	_item_data_by_id.clear()

	# 3. 让外发 domain 清理可能保留的状态 (counter / cache),BEFORE 我们丢引用
	if _domain != null:
		_domain.reset()

	# 4. 安装新的 default; 故意不调 reset() — 新实例本身已是 pristine 状态
	_domain = DefaultItemDomain.new()
	_catalog = EmptyItemCatalog.new()

	Log.info("ItemSystem", "reset_session 完成")


func get_domain() -> ItemDomain:
	return _domain


func get_catalog() -> ItemCatalog:
	return _catalog


## ============================================
## 容器管理
## ============================================

func register_container(container: BaseContainer) -> int:
	if container == null:
		Log.error("ItemSystem", "注册容器失败：容器为 null")
		return -1

	if container.container_id >= 0 and _container_map.has(container.container_id):
		Log.warning("ItemSystem", "容器 %s 已注册，跳过" % container.container_name)
		return container.container_id

	var container_id := _next_container_id
	_next_container_id += 1

	container.init_container(container_id, container.container_name, container.space_config)
	_container_map[container_id] = container

	container_registered.emit(container_id, container.container_name)
	Log.info("ItemSystem", "容器已注册: ID=%d, Name=%s" % [container_id, container.container_name])

	return container_id


## destructive: 销毁容器内所有 items 后再 unregister。
## Hex 项目侧装备容器 unregister 前应先用 move_item 把 item 转移到 player bag,
## 否则会丢失装备 (业务规则,框架不强制)。
func unregister_container(container_id: int) -> bool:
	if container_id == 0:
		Log.error("ItemSystem", "不能注销虚空容器")
		return false

	if not _container_map.has(container_id):
		Log.warning("ItemSystem", "容器不存在: ID=%d" % container_id)
		return false

	var container: BaseContainer = _container_map[container_id]

	var items := container.get_all_items()
	for item_id in items:
		destroy_item(item_id)

	_container_map.erase(container_id)

	container_unregistered.emit(container_id)
	Log.info("ItemSystem", "容器已注销: ID=%d, Name=%s" % [container_id, container.container_name])

	return true


func get_container(container_id: int) -> BaseContainer:
	if _container_map.has(container_id):
		return _container_map[container_id]
	return null


func get_all_containers() -> Array[int]:
	var container_ids: Array[int] = []
	for cid in _container_map.keys():
		container_ids.append(int(cid))
	return container_ids


## ============================================
## 底层 API (InventoryKit 内部 / 底层测试)
## ============================================

## 底层 item instance 登记。业务代码应优先使用 create_item();
## 直接调用本 API 跳过 catalog/domain 规则,只做 base ItemInstance + location 写入。
##
## **公共 signal 约定**: 本 API 永远不 emit public `item_created` signal。
## 业务 create_item() 才是 public signal 唯一来源,确保 signal 触发时
## `_item_data_by_id[item_id]` 已写入 — UI / DevAgent / 项目 domain
## listener 可安全调用 `get_item_data()` / `get_item_snapshot()`。
## 如果 raw API 也 emit,listener 会收到没有 instance_data 的 item,
## 违反 Plan §"ItemDomain Contract" 的 "_item_data_by_id 已写入后才触发 public signal" 约束。
## 仅 container 级别的 `item_added` signal 会(在 notify=true 时)触发,因为 container
## 听众通常只关心 slot/cache 更新,不会查询 project instance data。
##
## [param container_id] 目标容器ID
## [param slot_index] 目标槽位索引（-1 表示自动分配）
## [param item_type] 物品类型 (用于 base instance.item_type 字段)
## [param notify] 是否触发 container.on_item_added (业务 create_item 设 false,
##                自己控制 callback 顺序;raw 调用通常用 true)
## [return] 返回新 item_id; 失败返回 -1
func register_item_instance(container_id: int, slot_index: int = -1, item_type: StringName = &"", notify: bool = true) -> int:
	var container := get_container(container_id)
	if container == null:
		Log.error("ItemSystem", "register_item_instance 失败：容器不存在 ID=%d" % container_id)
		return -1

	var can_add_result := container.can_add_item(-1, slot_index)
	if not can_add_result.success:
		Log.warning("ItemSystem", "register_item_instance 失败：%s" % can_add_result.error_message)
		return -1

	if slot_index < 0:
		var space_manager := container.get_space_manager()
		if space_manager != null:
			slot_index = space_manager.get_first_available_slot()

	var item_id := _next_item_id
	_next_item_id += 1

	var location := ItemLocation.new(container_id, slot_index)
	var item_instance := ItemInstance.new(item_id, location, item_type)
	_item_map[item_id] = item_instance

	if notify:
		container.on_item_added(item_id, slot_index)
		# 注意: 此处不 emit public item_created signal — 见函数 doc 中的
		# "公共 signal 约定"。

	Log.debug("ItemSystem", "register_item_instance: ID=%d, Type=%s, Container%d:%d" % [
		item_id, item_type, container_id, slot_index
	])
	return item_id


## ============================================
## 业务 API (Hex / 其他项目通过 configure_domain 注册规则后使用)
## ============================================

## 业务 create_item: catalog lookup -> domain.can_create_item -> stack merge ->
## domain.create_instance_data -> register_item_instance -> _item_data_by_id write
## -> container.on_item_added -> domain.on_item_created -> emit item_created。
##
## [param container_id] 目标容器ID
## [param config_id] catalog 中的 item config 标识
## [param count] 创建数量 (stackable item 可能合并到已有 stack)
## [param slot_index] 目标槽位 (-1 自动分配)
## [return] ItemCreateResult
func create_item(container_id: int, config_id: StringName, count: int = 1, slot_index: int = -1) -> ItemCreateResult:
	if count <= 0:
		return ItemCreateResult.fail("count 必须 > 0 (got %d)" % count)

	if not _catalog.has_config(config_id):
		return ItemCreateResult.fail("catalog 不识别 config_id: %s" % str(config_id), count)

	var config := _catalog.get_config(config_id)
	var max_stack: int = int(config.get("max_stack", 1))

	var container := get_container(container_id)
	if container == null:
		return ItemCreateResult.fail("容器不存在 ID=%d" % container_id, count)

	var domain_check := _domain.can_create_item(config_id, container_id, slot_index, count)
	if not domain_check.success:
		return ItemCreateResult.fail(domain_check.error_message, count)

	# stack merge phase: 只在目标 container 内合并已有 stack。
	var updated: Array[int] = []
	var remaining := count
	if max_stack > 1:
		for existing_id in container.get_all_items():
			if remaining <= 0:
				break
			var existing_data: ItemInstanceData = _item_data_by_id.get(existing_id, null)
			if existing_data == null or existing_data.config_id != config_id:
				continue
			if not _domain.can_stack(existing_id, config_id):
				continue
			var leftover := _domain.merge_stack(existing_data, remaining, max_stack)
			# Domain 合约: merge_stack 必须 mutate existing_data.count;
			# leftover 描述未合并的 incoming count。撑爆 max_stack = domain bug。
			Log.assert_crash(existing_data.count <= max_stack, "ItemSystem",
				"ItemDomain.merge_stack overran max_stack: %d > %d (item %d, config %s)" % [
					existing_data.count, max_stack, existing_id, str(config_id)
				])
			var merged := remaining - leftover
			if merged > 0:
				updated.append(existing_id)
				_mirror_metadata(existing_id, existing_data)
			remaining = leftover

	# 剩余 count 走新建 stack(s) — V1 简单实现: 一次 create 至多新建一个 stack
	# (count 超出 max_stack 时,剩余进 remaining_count 字段)。Plan 不要求 split,
	# 多 stack 创建留给项目层 (Hex sandbox 容量足够,不会触发)。
	var created: Array[int] = []
	if remaining > 0:
		var new_stack_count: int = mini(remaining, max_stack)
		var add_check := container.can_add_item(-1, slot_index)
		if not add_check.success:
			# bag full / slot occupied 等; updated 已成功的不回滚
			if updated.is_empty():
				return ItemCreateResult.fail(add_check.error_message, remaining)
			# stack merge 成功但新 stack 创建失败: 返回 partial-success
			return ItemCreateResult.ok(created, updated, remaining)

		var data := _domain.create_instance_data(config_id, new_stack_count)
		var new_item_id := register_item_instance(container_id, slot_index, config_id, false)
		if new_item_id < 0:
			if updated.is_empty():
				return ItemCreateResult.fail("register_item_instance 失败 (container=%d slot=%d)" % [container_id, slot_index], remaining)
			var partial := ItemCreateResult.ok(created, updated, remaining)
			return partial

		_item_data_by_id[new_item_id] = data
		_mirror_metadata(new_item_id, data)

		# callback 顺序: container.on_item_added 在 _item_data_by_id 写入后
		var item_instance: ItemInstance = _item_map[new_item_id]
		container.on_item_added(new_item_id, item_instance.location.slot_index)
		_domain.on_item_created(new_item_id, data)
		item_created.emit(new_item_id, item_instance.location.duplicate())

		created.append(new_item_id)
		remaining -= new_stack_count

	return ItemCreateResult.ok(created, updated, remaining)


## 业务 move_item: domain.can_move_item -> target.can_add_item -> container
## callbacks -> location update -> domain.on_item_moved -> emit item_moved。
func move_item(item_id: int, target_container_id: int, target_slot_index: int = -1) -> ItemMoveResult:
	if not _item_map.has(item_id):
		return ItemMoveResult.fail("物品不存在 ID=%d" % item_id)

	var item_instance: ItemInstance = _item_map[item_id]
	var old_location := item_instance.location.duplicate()
	var source_container_id := old_location.container_id

	var source_container := get_container(source_container_id)
	if source_container == null:
		return ItemMoveResult.fail("源容器不存在 ID=%d" % source_container_id, old_location)

	var target_container := get_container(target_container_id)
	if target_container == null:
		return ItemMoveResult.fail("目标容器不存在 ID=%d" % target_container_id, old_location)

	# Domain validation
	var domain_check := _domain.can_move_item(item_id, target_container_id, target_slot_index)
	if not domain_check.success:
		var attempted := ItemLocation.new(target_container_id, target_slot_index)
		return ItemMoveResult.fail(domain_check.error_message, old_location, attempted)

	# 同容器走 _move_item_within_container
	if target_container_id == source_container_id:
		return _move_item_within_container(item_id, source_container, old_location, target_slot_index)

	# 跨容器: 目标 container 校验
	var can_add_result := target_container.can_add_item(item_id, target_slot_index)
	if not can_add_result.success:
		var attempted := ItemLocation.new(target_container_id, target_slot_index)
		return ItemMoveResult.fail(can_add_result.error_message, old_location, attempted)

	if target_slot_index < 0:
		var space_manager := target_container.get_space_manager()
		if space_manager != null:
			target_slot_index = space_manager.get_first_available_slot()

	source_container.on_item_moved_out(item_id, target_container_id, target_slot_index)
	target_container.on_item_moved_in(item_id, source_container_id, old_location.slot_index, target_slot_index)

	var new_location := ItemLocation.new(target_container_id, target_slot_index)
	item_instance.location = new_location

	_domain.on_item_moved(item_id, old_location, new_location)
	item_moved.emit(item_id, old_location, new_location)
	Log.debug("ItemSystem", "move_item: ID=%d, Container%d:%d -> Container%d:%d" % [
		item_id, source_container_id, old_location.slot_index, target_container_id, target_slot_index
	])

	return ItemMoveResult.ok(old_location, new_location)


func _move_item_within_container(item_id: int, container: BaseContainer, old_location: ItemLocation, new_slot: int) -> ItemMoveResult:
	if new_slot < 0:
		var space_manager := container.get_space_manager()
		if space_manager != null:
			new_slot = space_manager.get_first_available_slot()

	if new_slot < 0:
		var attempted := ItemLocation.new(container.container_id, -1)
		return ItemMoveResult.fail("无可用槽位", old_location, attempted)

	if new_slot == old_location.slot_index:
		return ItemMoveResult.ok(old_location, old_location.duplicate())

	var can_add_result := container.can_add_item(item_id, new_slot)
	if not can_add_result.success:
		var attempted := ItemLocation.new(container.container_id, new_slot)
		return ItemMoveResult.fail(can_add_result.error_message, old_location, attempted)

	var item_instance: ItemInstance = _item_map[item_id]

	# 同容器 callback: 释放旧槽 + 占新槽 (container 内部 item_ids 不变)
	container.on_item_moved(item_id, old_location.slot_index, new_slot)

	item_instance.location.slot_index = new_slot
	var new_location := ItemLocation.new(container.container_id, new_slot)

	_domain.on_item_moved(item_id, old_location, new_location)
	item_moved.emit(item_id, old_location, new_location)
	Log.debug("ItemSystem", "move_item (同容器): ID=%d, Container%d:%d -> %d" % [
		item_id, container.container_id, old_location.slot_index, new_slot
	])

	return ItemMoveResult.ok(old_location, new_location)


## 业务 destroy_item: container callback -> domain.on_item_destroyed ->
## _item_data_by_id.erase -> _item_map.erase -> emit item_destroyed
##
## **Raw item 行为**: 通过 `register_item_instance()` 创建的 raw item 没有
## instance_data,domain.on_item_destroyed 会以 `data == null` 调用,
## 让 project domain 自行决定是否处理 (counter 之类的可以根据 item_id
## 仍然 tracking)。这样 raw 与业务 item 在销毁路径上行为一致,
## 避免 domain 收不到 raw item 的 destroy 通知造成 silent leak。
func destroy_item(item_id: int) -> bool:
	if not _item_map.has(item_id):
		Log.warning("ItemSystem", "destroy_item: 物品不存在 ID=%d" % item_id)
		return false

	var item_instance: ItemInstance = _item_map[item_id]
	var location := item_instance.location
	var container := get_container(location.container_id)

	var data: ItemInstanceData = _item_data_by_id.get(item_id, null)

	if container != null:
		container.on_item_removed(item_id)

	# 即使 data == null 也 notify domain — raw item 也是 item, domain 可能在
	# tracking item_id (例如全局 counter)。子类需自行判断 data 是否为 null。
	if _domain != null:
		_domain.on_item_destroyed(item_id, data)

	_item_data_by_id.erase(item_id)
	_item_map.erase(item_id)

	item_destroyed.emit(item_id)
	Log.debug("ItemSystem", "destroy_item: ID=%d" % item_id)

	return true


## ============================================
## 查询接口
## ============================================

func get_item_location(item_id: int) -> ItemLocation:
	if not _item_map.has(item_id):
		return null
	var item_instance: ItemInstance = _item_map[item_id]
	return item_instance.location.duplicate()


func get_item_instance(item_id: int) -> ItemInstance:
	if _item_map.has(item_id):
		return _item_map[item_id]
	return null


func get_item_data(item_id: int) -> ItemInstanceData:
	return _item_data_by_id.get(item_id, null)


func get_item_config(config_id: StringName) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_config(config_id)


## Snapshot 合并: domain.build_item_snapshot + base identity/location + catalog config
func get_item_snapshot(item_id: int) -> Dictionary:
	if not _item_map.has(item_id):
		return {}

	var item_instance: ItemInstance = _item_map[item_id]
	var snapshot: Dictionary = {
		"item_id": item_id,
		"container_id": item_instance.location.container_id,
		"slot_index": item_instance.location.slot_index,
		"item_type": String(item_instance.item_type),
	}

	var data: ItemInstanceData = _item_data_by_id.get(item_id, null)
	if data == null:
		return snapshot

	snapshot["config_id"] = String(data.config_id)
	snapshot["count"] = data.count

	if _catalog != null and _catalog.has_config(data.config_id):
		var cfg := _catalog.get_config(data.config_id)
		var max_stack: int = int(cfg.get("max_stack", 1))
		snapshot["display_name"] = String(cfg.get("display_name", String(data.config_id)))
		snapshot["icon_key"] = String(cfg.get("icon_key", ""))
		snapshot["item_tags"] = cfg.get("item_tags", [])
		snapshot["max_stack"] = max_stack
		snapshot["stackable"] = max_stack > 1
		snapshot["equipable"] = bool(cfg.get("equipable", false))

	if _domain != null:
		var domain_snapshot := _domain.build_item_snapshot(item_id, data)
		for key in domain_snapshot.keys():
			snapshot[key] = domain_snapshot[key]

	return snapshot


func get_items_in_container(container_id: int) -> Array[int]:
	var container := get_container(container_id)
	if container == null:
		return []
	return container.get_all_items()


func item_exists(item_id: int) -> bool:
	return _item_map.has(item_id)


func get_total_item_count() -> int:
	return _item_map.size()


## ============================================
## 工具方法
## ============================================

func transfer_item(item_id: int, target_container_id: int) -> ItemMoveResult:
	return move_item(item_id, target_container_id, -1)


func transfer_all_items(source_container_id: int, target_container_id: int) -> int:
	var source_container := get_container(source_container_id)
	var target_container := get_container(target_container_id)

	if source_container == null or target_container == null:
		Log.error("ItemSystem", "批量转移失败：容器不存在")
		return 0

	var items := source_container.get_all_items()
	var transferred_count := 0

	for item_id in items:
		var r := move_item(item_id, target_container_id)
		if r.success:
			transferred_count += 1

	Log.info("ItemSystem", "批量转移完成: Container%d -> Container%d, 转移 %d/%d 个物品" % [
		source_container_id, target_container_id, transferred_count, items.size()
	])

	return transferred_count


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

func get_system_status() -> Dictionary:
	return {
		"total_items": _item_map.size(),
		"total_containers": _container_map.size(),
		"next_item_id": _next_item_id,
		"next_container_id": _next_container_id,
		"domain_class": _domain.get_class() if _domain != null else "<null>",
		"catalog_class": _catalog.get_class() if _catalog != null else "<null>",
		"tracked_item_data_count": _item_data_by_id.size(),
	}


func print_system_status() -> void:
	var status := get_system_status()
	print("=== ItemSystem 状态 ===")
	print("总物品数: %d" % status.total_items)
	print("总容器数: %d" % status.total_containers)
	print("下一个物品ID: %d" % status.next_item_id)
	print("下一个容器ID: %d" % status.next_container_id)
	print("Domain: %s, Catalog: %s, TrackedItemData: %d" % [status.domain_class, status.catalog_class, status.tracked_item_data_count])
	print("=====================")


## ============================================
## 内部辅助
## ============================================

## 把 instance data 镜像到 base instance.metadata,只用于 debug / inspector 显示。
## 业务逻辑必须通过 get_item_data() 拿权威 instance data,不能读 metadata。
func _mirror_metadata(item_id: int, data: ItemInstanceData) -> void:
	var instance: ItemInstance = _item_map.get(item_id, null)
	if instance == null:
		return
	instance.metadata["config_id"] = data.config_id
	instance.metadata["count"] = data.count
