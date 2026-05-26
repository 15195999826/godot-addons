## Phase G · Daedalus Charm 装备 grant 暴击 passive → 普攻 is_critical=true + 伤害 ×2.25
##
## V1 契约:
##   - 装备 daedalus_charm (chance=1.0, damage_multiplier=2.25, V1 dev scene 默认值)
##   - caster Strike enemy_0:
##       Strike DamageAction.emit_pre_basic_attack() → PreBasicAttackEvent
##       → Daedalus PreEventConfig handler: chance=1.0 必中 →
##           Modification.multiply("attack_damage", 2.25)
##           Modification.set_value("is_critical", 1.0)
##       → DamageAction 收 final attack_damage = base * 2.25, is_critical = true
##       → DamageEvent.is_critical = true, damage = base * 2.25
##
## chance = 1.0 让 scenario 不被 RNG flaky 影响 (Goal §"V1 关键假设" 已声明)。
class_name EquipmentDaedalusCriticalBasicAttackScenario
extends SkillScenario


const CASTER_ATK := 40.0
# Daedalus V1 默认: damage_multiplier = 2.25
const EXPECTED_CRIT_MULT := HexBattlePassiveDaedalusCriticalStrike.DEFAULT_DAMAGE_MULTIPLIER


func get_name() -> String:
	return "Equipment: daedalus_charm → Strike crit (is_critical=true, damage × 2.25)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 5000}],
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
	var ctx := EquipmentScenarioHelper.setup(caster.get_id(), setup_errors)
	if ctx == null:
		return false
	var item_id := EquipmentScenarioHelper.equip(ctx, &"daedalus_charm", setup_errors)
	if item_id < 0:
		return false
	var container := ctx.get_equipment_container()
	if container.get_granted_ability_instance_ids(item_id).size() != 1:
		setup_errors.append("daedalus_charm equip did not grant exactly 1 ability instance")
		return false
	return true


func assert_replay(ctx: ScenarioAssertContext) -> void:
	ctx.assert_eq(ctx.setup_errors.size(), 0,
		"setup_battle should pass (got: %s)" % str(ctx.setup_errors))

	var dmgs := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_eq(dmgs.size(), 1, "Expect exactly 1 damage event from Strike (no crit bonus event)")
	if dmgs.is_empty():
		return
	var damage_event: Dictionary = dmgs[0]
	var expected_damage: float = CASTER_ATK * EXPECTED_CRIT_MULT
	var actual_damage: float = damage_event.get("damage", 0.0) as float
	ctx.assert_float_eq(actual_damage, expected_damage,
		"Daedalus crit damage = %.1f * %.2f = %.2f (got %.2f)" % [CASTER_ATK, EXPECTED_CRIT_MULT, expected_damage, actual_damage],
		0.5)

	var is_crit := damage_event.get("is_critical", false) as bool
	ctx.assert_true(is_crit,
		"DamageEvent.is_critical = true (Daedalus PreBasicAttackEvent set is_critical=1.0)")

	# basic_attack_landed 仍应 emit 一次 (主伤路径), 携带 actual_life_damage
	var basic_landed := ctx.events_of_kind("basic_attack_landed")
	ctx.assert_eq(basic_landed.size(), 1,
		"Expect 1 BasicAttackLandedEvent from the crit'd Strike (got %d)" % basic_landed.size())
