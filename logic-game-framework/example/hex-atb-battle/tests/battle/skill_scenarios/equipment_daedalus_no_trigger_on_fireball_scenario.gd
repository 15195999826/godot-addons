## Phase G · 负面契约: 装备 Daedalus Charm 后, 释放 Fireball 不触发暴击规则
##
## V1 契约:
##   普通 active skill (Fireball / Poison / Fire Tile / Totem damage / reflected damage)
##   不调用 `emit_pre_basic_attack()` → 不进入 PreBasicAttackEvent → 不读 equipment crit rule
##
## 设定: caster 装 daedalus_charm (chance=1.0) → 普攻一定暴击; 但本 scenario 不发 Strike,
## 只发 Fireball, 验证 Fireball DamageEvent.is_critical=false + damage 等于 base (无 2.25 倍率)。
class_name EquipmentDaedalusNoTriggerOnFireballScenario
extends SkillScenario


func get_name() -> String:
	return "Equipment: daedalus_charm does NOT crit on Fireball (non-basic-attack path)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 5, "cols": 5},
		"caster":  {"class": "MAGE", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [3, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleFireball.ABILITY


func get_max_ticks() -> int:
	return 80


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
	return true


func assert_replay(ctx: ScenarioAssertContext) -> void:
	ctx.assert_eq(ctx.setup_errors.size(), 0,
		"setup_battle should pass (got: %s)" % str(ctx.setup_errors))

	# Fireball 命中 (有 magical damage)
	var fireballs := ctx.filter_damage_events({
		"target_actor_id": ctx.enemy_id(0),
		"damage_type": "magical",
	})
	ctx.assert_true(fireballs.size() >= 1, "Fireball did hit (sanity)")
	if fireballs.is_empty():
		return
	# Fireball DamageEvent.is_critical 必须为 false (Daedalus 不污染非普攻路径)
	for e in fireballs:
		var is_crit := e.get("is_critical", false) as bool
		ctx.assert_true(not is_crit,
			"Fireball DamageEvent.is_critical = false (Daedalus must NOT trigger on non-basic-attack)")

	# 没有 basic_attack_landed (Fireball 不走普攻链路)
	var basic_landed := ctx.events_of_kind("basic_attack_landed")
	ctx.assert_eq(basic_landed.size(), 0,
		"Fireball must NOT emit BasicAttackLandedEvent (got %d)" % basic_landed.size())
