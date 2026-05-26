## Phase G · 预校验拒绝: item config granted_abilities 含未注册 ability_config_id →
## HexItemDomain.can_move_item / HexActorEquipmentContainer.can_add_item reject move
##
## V1 契约 (per equipment-attack-effects-next-stage.md §"Equipment Integration"
## "callback 不能承担失败回滚"):
##   ItemSystem.move_item
##     → HexItemDomain.can_move_item / HexActorEquipmentContainer.can_add_item
##     → if target is equipment container:
##         item config.granted_abilities 必须全部能解析为 AbilityConfig
##         任一无法解析 = reject move
##     → 不走 container callbacks (grant 链路不被触发)
##
## 设定: 用 inline _BrokenCatalog 注入一个 granted_abilities 含未注册 config_id 的 item,
## 尝试 move 到 equipment container → 期望 move_item.success == false 且容器内 0 个 item +
## _granted_abilities 不含 item_id。
##
## 注意: 本 scenario 不依赖 catalog 持久化 (每次 setup_battle 重新 configure_domain),
## 不污染其它 scenario 的 catalog 状态。
class_name EquipmentGrantPrecheckRejectMoveScenario
extends SkillScenario


# 自定义 catalog: 在 HexItemCatalog 基础上加一个 "broken" item, granted_abilities 指向
# 不存在的 ability_config_id, 用来验证预校验链路。
class _BrokenCatalog extends HexItemCatalog:
	const BROKEN_ITEM_ID := &"phase_g_broken_equipment"

	func _init() -> void:
		super._init()
		_configs[BROKEN_ITEM_ID] = {
			"id": BROKEN_ITEM_ID,
			"display_name": "Broken Equipment (test)",
			"icon_key": "rune",
			"max_stack": 1,
			"item_tags": [&"equipment"],
			"equipable": true,
			"granted_abilities": [
				{
					"ability_config_id": &"passive_does_not_exist_phase_g_test",
					"source": &"equipment",
				},
			],
		}


func get_name() -> String:
	return "Equipment: granted_abilities precheck rejects move when ability_config_id unregistered"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 30, "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}


# 不发战斗 action; 仅在 setup_battle 内验证 move_item reject。time_ms=-1 让 _fire_action
# 立刻执行, 进入 tick 后可立即收敛。
func get_actions() -> Array[Dictionary]:
	return [{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "auto", "time_ms": -1}]


func get_max_ticks() -> int:
	return 30


func setup_battle(
	_battle: Object,
	caster: Object,
	_ally_actors: Array,
	_enemy_actors: Array,
	setup_errors: Array,
) -> bool:
	var caster_id: String = caster.get_id()
	if caster_id.is_empty():
		setup_errors.append("setup: caster_id 为空")
		return false

	# 使用自定义 catalog 替换默认 HexItemCatalog
	ItemSystem.reset_session()
	ItemSystem.configure_domain(HexItemDomain.new(), _BrokenCatalog.new())

	var inv := HexPlayerInventory.new()
	inv.init_inventory()
	if inv.player_bag_id <= 0:
		setup_errors.append("init_inventory 失败 (bag id=%d)" % inv.player_bag_id)
		return false
	var equipment_cid := inv.register_actor(caster_id)
	if equipment_cid < 0:
		setup_errors.append("register_actor 失败 (cid=%d)" % equipment_cid)
		return false

	# 在 bag 创建 broken item
	var create_r := ItemSystem.create_item(inv.player_bag_id, _BrokenCatalog.BROKEN_ITEM_ID, 1, -1)
	if not create_r.success:
		setup_errors.append("create_item broken_equipment 失败: %s" % create_r.error_message)
		return false
	if create_r.created_item_ids.is_empty():
		setup_errors.append("create_item broken_equipment 返回 success 但 created_item_ids 为空")
		return false
	var item_id: int = create_r.created_item_ids[0]

	# 尝试 move 到 equipment container — 期望 fail
	var move_r := ItemSystem.move_item(item_id, equipment_cid, 0)
	if move_r.success:
		setup_errors.append("expected move_item to REJECT broken item, but succeeded")
		return false

	# 验证 item 仍在 bag 内 (没被错误地移走 / 重复 attribution)
	var bag_items := ItemSystem.get_items_in_container(inv.player_bag_id)
	if not bag_items.has(item_id):
		setup_errors.append("item should remain in player bag after rejected move (bag_items=%s)" % str(bag_items))
		return false

	# 验证 equipment container 没有该 item + grant 映射为空
	var container := ItemSystem.get_container(equipment_cid) as HexActorEquipmentContainer
	if container.get_granted_ability_instance_ids(item_id).size() != 0:
		setup_errors.append("equipment container should have empty _granted_abilities for item %d after rejected move" % item_id)
		return false
	var snap := container.snapshot_granted_abilities()
	if not snap.is_empty():
		setup_errors.append("equipment container _granted_abilities should be empty, got %s" % str(snap))
		return false

	# caster 的 ability_set 不应含未知 config_id (grant 没发生)
	var ab_set: AbilitySet = caster.ability_set
	if ab_set.has_ability("passive_does_not_exist_phase_g_test"):
		setup_errors.append("caster ability_set should NOT contain rejected ability")
		return false
	return true


func assert_replay(ctx: ScenarioAssertContext) -> void:
	ctx.assert_eq(ctx.setup_errors.size(), 0,
		"setup_battle precheck assertions all passed (got errors: %s)" % str(ctx.setup_errors))
	# 普攻一切照常 (装备 grant 失败不影响 base damage 链路)
	var dmgs := ctx.filter_damage_events({"source_actor_id": ctx.caster_id, "target_actor_id": ctx.enemy_id(0)})
	ctx.assert_true(dmgs.size() >= 1, "Strike still hits enemy normally (rejected move did not break basic attack)")
