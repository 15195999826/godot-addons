## Phase A · BasicAttackLandedEvent 基线：Strike 命中后必定 emit 一条事件
##
## V1 契约:
## - Strike 主伤命中且未被 cancelled / 目标未死 → 一条 BasicAttackLandedEvent
## - 字段必含: attacker_actor_id / target_actor_id / source_ability_id /
##   source_ability_config_id / actual_life_damage / damage_event
## - actual_life_damage > 0 (无 shield 全吸)
## - 单次 Strike cast 只触发 1 条 BasicAttackLandedEvent (Phase G 起 Strike 不再
##   自带 crit bonus damage, 暴击改由装备 grant 的 PreBasicAttackEvent passive 决定)
##
## 时序:
##   t=0 caster atk=40 cast Strike target enemy_0 → HIT @ t=300
##     → damage event source=caster target=enemy_0
##     → on_hit callback _EmitBasicAttackLandedAction → BasicAttackLandedEvent
class_name BasicAttackLandedStrikeEmitsScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "BasicAttackLanded: Strike emits one BasicAttackLandedEvent per cast"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var enemy := ctx.enemy_id(0)
	var attack_events := ctx.events_of_kind("basic_attack_landed")
	ctx.assert_eq(attack_events.size(), 1,
		"Expect exactly 1 BasicAttackLandedEvent (got %d)" % attack_events.size())
	if attack_events.is_empty():
		return
	var e: Dictionary = attack_events[0]
	ctx.assert_eq(e.get("attacker_actor_id", ""), ctx.caster_id,
		"attacker_actor_id = caster")
	ctx.assert_eq(e.get("target_actor_id", ""), enemy,
		"target_actor_id = enemy_0")
	ctx.assert_eq(e.get("source_ability_config_id", ""), HexBattleStrike.CONFIG_ID,
		"source_ability_config_id = skill_strike")
	ctx.assert_true(not str(e.get("source_ability_id", "")).is_empty(),
		"source_ability_id not empty (runtime ability instance id)")
	var actual_life := e.get("actual_life_damage", -1.0) as float
	ctx.assert_true(actual_life > 0.0,
		"actual_life_damage > 0 (no shield absorb) — got %.2f" % actual_life)
	var damage_event = e.get("damage_event", null)
	ctx.assert_true(damage_event is Dictionary and not (damage_event as Dictionary).is_empty(),
		"damage_event payload populated")
	if damage_event is Dictionary:
		var de := damage_event as Dictionary
		ctx.assert_eq(de.get("kind", ""), "damage", "damage_event.kind = damage")
		ctx.assert_eq(de.get("target_actor_id", ""), enemy,
			"damage_event.target_actor_id = enemy_0")
