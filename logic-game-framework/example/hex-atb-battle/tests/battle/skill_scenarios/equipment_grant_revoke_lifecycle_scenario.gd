## Phase G · 装备 grant/revoke 生命周期 — equip 后 ability + attribute 生效;
## unequip 后 instance 精确 revoke + attribute 归零。
##
## V1 契约:
##   - equip morbid_mask: caster ability_set 含 passive_vampiric_training 实例 +
##     attack_lifesteal_pct = 0.5
##   - unequip 后: 该实例 (按 instance id) 被精确 revoke, attack_lifesteal_pct = 0.0
##   - container._granted_abilities 不再保存 item_id
##   - actor 自带的同 config_id passive (V2 验证, V1 仅 equipment-granted 单实例; 不重复 grant)
##
## 时序: setup_battle 内完成 equip → 检查 → unequip → 检查; 不发任何 action;
##       assert_replay 验证 setup_errors 为空 + 最终 attribute 归零。
class_name EquipmentGrantRevokeLifecycleScenario
extends SkillScenario


func get_name() -> String:
	return "Equipment: grant on equip + precise revoke on unequip (lifecycle)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 100, "max_hp": 200, "atk": 30},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}


# 不发 Strike (我们只验证 grant/revoke state, 不验 lifesteal heal — 那是 S1 职责)
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
	var ctx := EquipmentScenarioHelper.setup(caster.get_id(), setup_errors)
	if ctx == null:
		return false

	# 装备 morbid_mask → 验证 grant
	var item_id := EquipmentScenarioHelper.equip(ctx, &"morbid_mask", setup_errors)
	if item_id < 0:
		return false
	var container := ctx.get_equipment_container()
	var granted_after_equip := container.get_granted_ability_instance_ids(item_id)
	if granted_after_equip.size() != 1:
		setup_errors.append("post-equip: expected 1 granted instance, got %d" % granted_after_equip.size())
		return false
	# 直接读 caster runtime ability_set
	var ability_set: AbilitySet = caster.ability_set
	if ability_set.find_ability_by_id(granted_after_equip[0]) == null:
		setup_errors.append("post-equip: granted instance %s 未出现在 caster.ability_set" % granted_after_equip[0])
		return false
	var pct_after_equip: float = caster.attribute_set.attack_lifesteal_pct
	if absf(pct_after_equip - HexBattleVampiricTraining.LIFESTEAL_PCT) > 0.001:
		setup_errors.append("post-equip: attack_lifesteal_pct expected %.2f, got %.2f" % [
			HexBattleVampiricTraining.LIFESTEAL_PCT, pct_after_equip
		])
		return false

	# 卸装 morbid_mask → 验证 revoke
	if not EquipmentScenarioHelper.unequip(ctx, item_id, setup_errors):
		return false
	var granted_after_unequip := container.get_granted_ability_instance_ids(item_id)
	if granted_after_unequip.size() != 0:
		setup_errors.append("post-unequip: expected 0 tracked instances, got %d" % granted_after_unequip.size())
		return false
	if ability_set.find_ability_by_id(granted_after_equip[0]) != null:
		setup_errors.append("post-unequip: revoked instance %s 仍然存在于 caster.ability_set" % granted_after_equip[0])
		return false
	var pct_after_unequip: float = caster.attribute_set.attack_lifesteal_pct
	if absf(pct_after_unequip) > 0.001:
		setup_errors.append("post-unequip: attack_lifesteal_pct expected 0.0, got %.4f" % pct_after_unequip)
		return false
	return true


func assert_replay(ctx: ScenarioAssertContext) -> void:
	ctx.assert_eq(ctx.setup_errors.size(), 0,
		"setup_battle should pass without errors (got: %s)" % str(ctx.setup_errors))
	# 卸装后跑了一次 Strike, 不应有 heal event (pct 已归零)
	var heal_events: Array = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "heal":
			continue
		if str(e.get("target_actor_id", "")) != ctx.caster_id:
			continue
		heal_events.append(e)
	ctx.assert_eq(heal_events.size(), 0,
		"After unequip, Strike should NOT trigger lifesteal heal (got %d heal events)" % heal_events.size())
	# 最终 attack_lifesteal_pct 归零
	var attrs: Dictionary = ctx.final_actor_attributes.get(ctx.caster_id, {})
	ctx.assert_float_eq(
		attrs.get("attack_lifesteal_pct", -1.0) as float, 0.0,
		"After unequip, caster.attack_lifesteal_pct = 0.0",
		0.001,
	)
	# VampiricTraining ability 不在 final_ability_states (已被 revoke)
	var caster_abilities: Array = ctx.final_ability_states.get(ctx.caster_id, [])
	ctx.assert_true(
		not caster_abilities.has(HexBattleVampiricTraining.CONFIG_ID),
		"After unequip, VampiricTraining instance revoked (caster_abilities=%s)" % str(caster_abilities))
