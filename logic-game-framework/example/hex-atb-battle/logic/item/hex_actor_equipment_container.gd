## HexActorEquipmentContainer - Actor 6 槽位装备容器
##
## V1 槽位 = 1..6 (UI 显示;底层 slot_index 0..5)。
## 只接受 catalog config `equipable == true` 的 item;只接受空槽(不做 swap)。
##
## §Phase G — Ability grant/revoke 同步:
##   item 进入 equipment container 时 (`on_item_added` / `on_item_moved_in`),
##   读 item config `granted_abilities[*]`, 通过 `HexEquipmentAbilityResolver` 拿
##   `AbilityConfig`, 给 owner 的 `ability_set.grant_ability(...)`, 记录 instance id 到
##   `_granted_abilities[item_id]`。item 移出时 (`on_item_removed` / `on_item_moved_out`)
##   按 instance id 精确 revoke (不按 config_id 粗暴 revoke, 避免误删 actor 自带 / 其它
##   装备 grant 出来的同 config_id passive)。
##
##   - container 默认只持 `owner_actor_id` (避免 dangling Actor / AbilitySet 引用);
##     grant/revoke 时通过 `GameWorld.get_actor(owner_actor_id)` 即时 fetch。
##   - 写 runtime attribution (`source = equipment` / `item_id` / `item_config_id`) 前
##     必须 `ability.metadata = ability.metadata.duplicate(true)`, 不 mutate 共享 AbilityConfig.metadata。
##   - granted_abilities 解析失败 (resolver 返回 null) 应在 `can_add_item` 阶段就被
##     reject (Plan §"callback 不能承担失败回滚"); 本类 callback 阶段假定 prevalidated。
##   - V1 不存 `owner_instance_id` (没有 GRANTED_SELF self-trigger 需求);
##     grant_ability 不传 game_state_provider, 不广播 ABILITY_GRANTED_EVENT。
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

## metadata 写入 key (replay / DevAgent / debug attribution 用)
const META_SOURCE := "source"
const META_ITEM_ID := "item_id"
const META_ITEM_CONFIG_ID := "item_config_id"
const SOURCE_EQUIPMENT := "equipment"

## 拥有此装备容器的 actor id (HexBattleActor.get_id() 返回的 String)
## 给 UI / DevAgent / debug 用;V1 不参与校验。
var owner_actor_id: String = ""

## item_id → Array[String]: grant 给 owner 的 ability runtime instance id 列表。
## item 离场时按 instance id 精确 revoke, 避免误删同 config_id 但来自其它装备 / actor 自带的 passive。
var _granted_abilities: Dictionary = {}


## 工厂方法: 创建一个 6 槽位装备容器,关联到 actor_id
static func create_for_actor(actor_id: String) -> HexActorEquipmentContainer:
	var container := HexActorEquipmentContainer.new()
	container.container_name = StringName("EquipmentContainer:%s" % actor_id)
	container.space_config = ContainerSpaceConfig.create_fixed(SLOT_TYPES)
	container.space_manager = container._create_space_manager(container.space_config)
	container.owner_actor_id = actor_id
	return container


## 重写 can_add_item: 加入 equipable + granted_abilities 解析校验。
## 槽位 occupied 检查走父类 (space_manager.is_slot_available)。
##
## Phase G: granted_abilities[*].ability_config_id 必须都能由
## HexEquipmentAbilityResolver 解析为已注册 AbilityConfig, 否则 reject。
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

	# Phase G: granted_abilities 解析校验 (任一无法解析 → reject)
	var granted: Variant = cfg.get("granted_abilities", null)
	if not HexEquipmentAbilityResolver.resolve_all_ok(granted):
		return ContainerResult.fail(
			"item %s granted_abilities 含未注册 ability_config_id, 拒绝装备" % str(data.config_id)
		)

	return ContainerResult.ok(true)


## Phase G grant 路径: item 进入装备容器时给 owner grant 该 item 的所有 granted_abilities。
## 父类 BaseContainer.on_item_added 负责 item_ids cache + space_manager 标记 + signal。
func on_item_added(item_id: int, slot_index: int) -> void:
	super.on_item_added(item_id, slot_index)
	_grant_item_abilities(item_id)


func on_item_moved_in(item_id: int, source_container_id: int, source_slot_index: int, target_slot_index: int) -> void:
	super.on_item_moved_in(item_id, source_container_id, source_slot_index, target_slot_index)
	_grant_item_abilities(item_id)


## Phase G revoke 路径: item 离开装备容器时按 instance id 精确 revoke 之前 grant 的 abilities。
func on_item_removed(item_id: int) -> void:
	_revoke_item_abilities(item_id)
	super.on_item_removed(item_id)


func on_item_moved_out(item_id: int, target_container_id: int, target_slot_index: int) -> void:
	_revoke_item_abilities(item_id)
	super.on_item_moved_out(item_id, target_container_id, target_slot_index)


## 给 item 关联的 granted_abilities 在 owner 身上 grant 出来 (Phase G):
##   - 通过 HexEquipmentAbilityResolver 拿 AbilityConfig (预校验已通过, 此处 null 视为 lifecycle bug)
##   - `Ability.new(cfg, owner_actor_id)` → metadata.duplicate(true) 后写 source/item_id/item_config_id
##   - `actor.ability_set.grant_ability(ability)` (V1 不传 game_state_provider, 不触发 self-trigger)
##   - 记录 instance id 到 `_granted_abilities[item_id]` 供后续精确 revoke
func _grant_item_abilities(item_id: int) -> void:
	var actor := GameWorld.get_actor(owner_actor_id)
	if actor == null:
		Log.error("HexActorEquipmentContainer",
			"grant: owner actor %s 未注册到 GameWorld, 跳过 grant (item=%d)" % [owner_actor_id, item_id])
		return
	var ability_set: AbilitySet = null
	if "ability_set" in actor:
		ability_set = actor.get("ability_set")
	if ability_set == null:
		Log.error("HexActorEquipmentContainer",
			"grant: actor %s 没有 ability_set, 跳过 grant (item=%d)" % [owner_actor_id, item_id])
		return

	var data := ItemSystem.get_item_data(item_id) as ItemInstanceData
	if data == null:
		Log.error("HexActorEquipmentContainer",
			"grant: item %d 无 instance data, 跳过" % item_id)
		return
	var cfg := ItemSystem.get_item_config(data.config_id)
	var granted_list: Variant = cfg.get("granted_abilities", null)
	if granted_list == null or not (granted_list is Array):
		return  # 没有 grant 要求, no-op

	var instance_ids: Array[String] = []
	for entry in (granted_list as Array):
		if not (entry is Dictionary):
			Log.error("HexActorEquipmentContainer",
				"grant: item %s granted_abilities entry 不是 Dictionary, 跳过此项" % str(data.config_id))
			continue
		var entry_dict := entry as Dictionary
		var raw_id: Variant = entry_dict.get("ability_config_id", "")
		var ability_cfg := HexEquipmentAbilityResolver.resolve(raw_id)
		Log.assert_crash(ability_cfg != null,
			"HexActorEquipmentContainer",
			"grant: ability_config_id %s 解析失败 — can_add_item 预校验未拦住 (item=%d, config=%s)" % [
				str(raw_id), item_id, str(data.config_id)
			])
		var ability := Ability.new(ability_cfg, owner_actor_id)
		# 不 mutate 共享 AbilityConfig.metadata; runtime attribution 写在 duplicate 后的副本
		ability.metadata = ability.metadata.duplicate(true)
		ability.metadata[META_SOURCE] = SOURCE_EQUIPMENT
		ability.metadata[META_ITEM_ID] = item_id
		ability.metadata[META_ITEM_CONFIG_ID] = String(data.config_id)
		ability_set.grant_ability(ability)
		instance_ids.append(ability.id)

	if not instance_ids.is_empty():
		_granted_abilities[item_id] = instance_ids
		Log.info("HexActorEquipmentContainer",
			"actor %s 装备 item %d (%s) → grant %d ability instances" % [
				owner_actor_id, item_id, str(data.config_id), instance_ids.size()
			])


## 精确 revoke item 之前 grant 出的 ability instance ids; 不存在记录时静默 no-op。
func _revoke_item_abilities(item_id: int) -> void:
	if not _granted_abilities.has(item_id):
		return
	var instance_ids: Array[String] = _granted_abilities[item_id]
	_granted_abilities.erase(item_id)

	var actor := GameWorld.get_actor(owner_actor_id)
	if actor == null:
		Log.warning("HexActorEquipmentContainer",
			"revoke: owner actor %s 已离场, 仅清理本地映射 (item=%d, %d ability instances 视为随 actor 销毁)" % [
				owner_actor_id, item_id, instance_ids.size()
			])
		return
	var ability_set: AbilitySet = null
	if "ability_set" in actor:
		ability_set = actor.get("ability_set")
	if ability_set == null:
		Log.warning("HexActorEquipmentContainer",
			"revoke: actor %s 没有 ability_set (可能已 shutdown), 跳过 revoke (item=%d)" % [
				owner_actor_id, item_id
			])
		return

	for instance_id in instance_ids:
		var ok := ability_set.revoke_ability(instance_id, AbilitySet.REVOKE_REASON_MANUAL)
		if not ok:
			Log.warning("HexActorEquipmentContainer",
				"revoke: actor %s ability instance %s 未找到 (可能已先被其它路径移除) (item=%d)" % [
					owner_actor_id, instance_id, item_id
				])
	Log.info("HexActorEquipmentContainer",
		"actor %s 卸装 item %d → revoke %d ability instances" % [
			owner_actor_id, item_id, instance_ids.size()
		])


## 查询接口: item_id → grant 出去的 ability instance ids (副本) — DevAgent / debug 用。
func get_granted_ability_instance_ids(item_id: int) -> Array[String]:
	if not _granted_abilities.has(item_id):
		var empty: Array[String] = []
		return empty
	var src: Array[String] = _granted_abilities[item_id]
	var copy: Array[String] = []
	copy.append_array(src)
	return copy


## 全量 dump: 所有 item_id → instance ids 的快照 (副本) — DevAgent observation 用。
func snapshot_granted_abilities() -> Dictionary:
	var out: Dictionary = {}
	for item_id in _granted_abilities.keys():
		var src: Array[String] = _granted_abilities[item_id]
		var copy: Array[String] = []
		copy.append_array(src)
		out[item_id] = copy
	return out
