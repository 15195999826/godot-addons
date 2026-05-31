## Phase G · Morbid Mask 装备 grant VampiricTraining → owner 普攻吸血生效
##
## V1 契约:
##   - 装备 grant passive 后, owner attack_lifesteal_pct = 0.5 (VampiricTraining 默认值)
##   - 普攻命中 → BasicAttackLandedEvent → GeneralPassive 监听 → 按
##     actual_life_damage * 0.5 heal caster
##   - 与"caster_passives 直接 grant VampiricTraining"的 lifesteal_attribute_basic 契约一致,
##     差别在 grant 路径走 HexActorEquipmentContainer.on_item_moved_in
##
## 时序:
##   setup: morbid_mask 装备到 caster slot 0 → grant passive_vampiric_training instance
##   t=0   caster atk=40 cast Strike enemy_0 → HIT @ t=300
##           → damage event actual_life_damage=40 (无 shield)
##           → BasicAttackLandedEvent
##           → GeneralPassive heal caster 40*0.5=20
class_name EquipmentGrantAttributeMorbidMaskScenario
extends SkillScenario


const CASTER_ATK := 40.0
const CASTER_START_HP := 100.0
const CASTER_MAX_HP := 200.0


func get_name() -> String:
	return "Equipment: morbid_mask grants VampiricTraining → lifesteal active"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": CASTER_START_HP, "max_hp": CASTER_MAX_HP, "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 30


func setup_battle(
	_battle: Object,
	caster: Object,
	_ally_actors: Array,
	_enemy_actors: Array,
	setup_errors: Array,
) -> bool:
	var setup_ctx := EquipmentScenarioHelper.setup(caster.get_id(), setup_errors)
	if setup_ctx == null:
		return false
	var item_id := EquipmentScenarioHelper.equip(setup_ctx, &"morbid_mask", setup_errors)
	if item_id < 0:
		return false
	# 校验 grant 真发生 (V1: 一个 instance)
	var container := setup_ctx.get_equipment_container()
	var granted := container.get_granted_ability_instance_ids(item_id)
	if granted.size() != 1:
		setup_errors.append("morbid_mask: expected 1 granted ability instance, got %d" % granted.size())
		return false
	return true


func assert_replay(ctx: ScenarioAssertContext) -> void:
	if ctx.setup_errors.size() > 0:
		ctx.fail("setup_battle failed: %s" % str(ctx.setup_errors))
		return

	# 1. 主伤事件
	var main_damages := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_eq(main_damages.size(), 1, "Expect 1 main damage event")
	if main_damages.is_empty():
		return
	var actual: float = main_damages[0].get("actual_life_damage", main_damages[0].get("damage", 0.0)) as float
	var expected_heal: float = actual * HexBattleVampiricTraining.LIFESTEAL_PCT

	# 2. heal event on caster, amount = actual * 0.5
	var heal_events: Array = []
	for e in ctx.events:
		if str(e.get("kind", "")) != "heal":
			continue
		if str(e.get("target_actor_id", "")) != ctx.caster_id:
			continue
		heal_events.append(e)
	ctx.assert_eq(heal_events.size(), 1,
		"Expect 1 heal event on caster (from equipment-granted lifesteal), got %d" % heal_events.size())
	if heal_events.is_empty():
		return
	var heal_amount := heal_events[0].get("amount", heal_events[0].get("heal_amount", 0.0)) as float
	ctx.assert_float_eq(heal_amount, expected_heal,
		"Heal = actual_life_damage %.1f * %.2f = %.1f (got %.1f)" % [actual, HexBattleVampiricTraining.LIFESTEAL_PCT, expected_heal, heal_amount],
		1.0)

	# 3. caster final hp > start hp (lifesteal 真生效)
	var final_hp := ctx.actor_final_hp(ctx.caster_id)
	ctx.assert_true(final_hp > CASTER_START_HP,
		"After equipment lifesteal, caster hp (%.1f) > start hp (%.1f)" % [final_hp, CASTER_START_HP])

	# 4. caster 最终属性 attack_lifesteal_pct == 0.5 (VampiricTraining grant 后)
	var attrs: Dictionary = ctx.final_actor_attributes.get(ctx.caster_id, {})
	ctx.assert_float_eq(
		attrs.get("attack_lifesteal_pct", 0.0) as float, HexBattleVampiricTraining.LIFESTEAL_PCT,
		"caster.attack_lifesteal_pct == %.2f (granted by morbid_mask)" % HexBattleVampiricTraining.LIFESTEAL_PCT,
		0.001,
	)
