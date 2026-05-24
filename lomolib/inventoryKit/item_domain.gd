## InventoryKit - 物品规则扩展点
##
## ItemSystem 通过 configure_domain() 注册项目规则。
## V1 接口只提供同步、确定性的规则 hook,不做 UI、不持有 Node、不直接生成 scene 对象。
##
## 各 hook 调用顺序在 ItemSystem.create_item / move_item / destroy_item 中固定:
## create_item:
##   catalog lookup -> domain.can_create_item -> domain.merge_stack (target 容器内)
##   -> domain.create_instance_data -> register_item_instance(notify=false)
##   -> _item_data_by_id[item_id] = data -> mirror debug metadata
##   -> container.on_item_added -> domain.on_item_created -> emit item_created
## move_item:
##   domain.can_move_item -> target_container.can_add_item
##   -> container callbacks (moved_out / moved_in 或 on_item_moved 同容器)
##   -> location update -> domain.on_item_moved -> emit item_moved
## destroy_item:
##   container callback -> domain.on_item_destroyed
##   -> _item_data_by_id.erase -> base item map erase -> emit item_destroyed
class_name ItemDomain
extends RefCounted


## 项目侧据 config 和 count 创建 ItemInstanceData (或子类)
## 默认返回 base ItemInstanceData
func create_instance_data(config_id: StringName, count: int) -> ItemInstanceData:
	return ItemInstanceData.new(config_id, count)


## 同一容器内能否堆叠 existing item 与新 config
func can_stack(_existing_item_id: int, _config_id: StringName) -> bool:
	return false


## 把 incoming_count 合并到 existing_data; 返回未合并的剩余 count。
##
## **实现合约**: 子类必须 mutate `existing_data.count`,把成功合并的部分加到
## 已有 stack 上 — ItemSystem 只看返回值知道还有多少 leftover,不会自己
## 改 existing_data.count。如果子类只 return leftover < incoming_count
## 而不 mutate existing_data.count,会出现 phantom merge:
## ItemCreateResult.updated_item_ids 报告合并成功,但 stack 实际 count 没变。
##
## ItemSystem 在调用后会断言 `existing_data.count <= max_stack`,避免子类
## 错误实现把 stack 撑爆。
##
## (max_stack 来自 catalog config; 默认实现整批拒绝合并)
func merge_stack(_existing_data: ItemInstanceData, incoming_count: int, _max_stack: int) -> int:
	return incoming_count


## 业务 create_item 前的规则检查
func can_create_item(_config_id: StringName, _container_id: int, _slot_index: int, _count: int) -> ContainerResult:
	return ContainerResult.ok(true)


## 业务 move_item 前的规则检查
func can_move_item(_item_id: int, _target_container_id: int, _target_slot_index: int) -> ContainerResult:
	return ContainerResult.ok(true)


## item 创建成功后的 hook (item_data 已写入)
func on_item_created(_item_id: int, _data: ItemInstanceData) -> void:
	pass


## item 移动成功后的 hook
func on_item_moved(_item_id: int, _old_location: ItemLocation, _new_location: ItemLocation) -> void:
	pass


## item 销毁前的 hook (item_data 仍可访问)
##
## **Raw item**: 通过 `ItemSystem.register_item_instance()` 创建的 raw item
## 没有 instance_data,本 hook 仍会被调用但 `data == null`。子类如果在
## tracking item_id (counter / tag 索引等),需要据 `data is_instance_valid`
## 决定如何处理。
func on_item_destroyed(_item_id: int, _data: ItemInstanceData) -> void:
	pass


## 构建 snapshot (UI / DevAgent 读取); 默认实现合并 catalog config + instance data
## 子类可补充字段
func build_item_snapshot(_item_id: int, _data: ItemInstanceData) -> Dictionary:
	return {}


## domain 自身的 reset (ItemSystem.reset_session 时调用)
func reset() -> void:
	pass
