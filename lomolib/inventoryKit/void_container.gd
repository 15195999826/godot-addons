## InventoryKit - 虚空容器
##
## 虚空容器是一个特殊的容器，用于存放没有明确容器的物品
## 它总是接受物品的添加和移动，容器ID固定为 0

class_name VoidContainer
extends BaseContainer


## 虚空容器的构造函数
func _init() -> void:
	container_name = &"VoidContainer"
	container_id = 0
	space_config = ContainerSpaceConfig.create_unordered(-1)
	space_manager = UnorderedSpaceManager.new(space_config)
	_is_initialized = true


## 重写初始化方法（虚空容器已经预先初始化）
func init_container(cid: int, name: StringName, config: ContainerSpaceConfig) -> void:
	# 虚空容器的ID固定为0，不允许修改
	if cid != 0:
		Log.warning("VoidContainer", "虚空容器ID必须为0，忽略传入的ID=%d" % cid)


## 重写添加检查 - 虚空容器总是接受物品
func can_add_item(item_id: int, slot_index: int = -1) -> ContainerResult:
	return ContainerResult.ok(true)


## 重写移动检查 - 虚空容器总是接受物品
func can_move_item(item_id: int, slot_index: int = -1) -> ContainerResult:
	return ContainerResult.ok(true)


## 转换为字符串表示
func to_string() -> String:
	return "VoidContainer(ID=0, Items=%d)" % item_ids.size()
