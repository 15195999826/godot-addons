## HexActorEquipmentContainer - Actor 6 槽位装备容器
##
## V1 槽位 = 1..6 (UI 显示;底层 slot_index 0..5)。
## 只接受 catalog config `equipable == true` 的 item;只接受空槽(不做 swap)。
##
## 槽位编号约定:
## - 底层 slot_index: 0..5 (InventoryKit FixedSlotSpaceManager 用整数索引)
## - UI label / DevAgent command 参数: 1..6 (1-based, 用户友好)
##   adapter 负责 ±1 转换;本类只认 0..5。
##
## 父类 BaseContainer 已经做:
## - is_slot_available(slot_index) → 空 vs 已占用
## - mark_slot_occupied / mark_slot_available
## - on_item_added / on_item_moved_in / on_item_moved_out / on_item_removed
class_name HexActorEquipmentContainer
extends BaseContainer


## 装备槽数
const EQUIPMENT_SLOT_COUNT := 6

## 槽位类型 (固定 6 个,统一命名 slot_1..slot_6 — Plan §"Resolved Decisions":
## "装备槽位只使用 1..6 号槽,不命名、不分类")
const SLOT_TYPES: Array[StringName] = [
	&"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5", &"slot_6",
]

## 拥有此装备容器的 actor id (HexBattleActor.get_id() 返回的 String)
## 给 UI / DevAgent / debug 用;V1 不参与校验。
var owner_actor_id: String = ""


## 工厂方法: 创建一个 6 槽位装备容器,关联到 actor_id
static func create_for_actor(actor_id: String) -> HexActorEquipmentContainer:
	var container := HexActorEquipmentContainer.new()
	container.container_name = StringName("EquipmentContainer:%s" % actor_id)
	container.space_config = ContainerSpaceConfig.create_fixed(SLOT_TYPES)
	container.space_manager = container._create_space_manager(container.space_config)
	container.owner_actor_id = actor_id
	return container


## 重写 can_add_item: 加入 equipable 校验。
## 槽位 occupied 检查走父类 (space_manager.is_slot_available)。
func can_add_item(item_id: int, slot_index: int = -1) -> ContainerResult:
	# 先走父类的 slot_index 校验
	var base_result := super.can_add_item(item_id, slot_index)
	if not base_result.success:
		return base_result

	# item_id < 0 = ItemSystem.register_item_instance 的初始登记探测,
	# 没有真实 item 可校验 equipable;父类的 slot 校验已足够。
	# 业务 create_item 不会用 equipment container (只会 player bag),
	# 所以正常路径不会走到此分支拒绝。
	if item_id < 0:
		return base_result

	var data := ItemSystem.get_item_data(item_id) as ItemInstanceData
	if data == null:
		return ContainerResult.fail("item %d 无 instance data,无法装备" % item_id)

	var cfg := ItemSystem.get_item_config(data.config_id)
	if not bool(cfg.get("equipable", false)):
		return ContainerResult.fail("item %s 不可装备" % str(data.config_id))

	return ContainerResult.ok(true)
