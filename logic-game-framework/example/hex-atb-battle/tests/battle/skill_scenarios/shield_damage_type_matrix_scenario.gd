## Shield damage-type matrix:
##   physical shield absorbs physical only
##   magical shield absorbs magical only
##   universal Ward absorbs pure as well
class_name ShieldDamageTypeMatrixScenario
extends SkillScenario


const TEST_DAMAGE := 10.0
const TIMELINE_ID := HexBattleStrike.TIMELINE_ID


static var PHYSICAL_HIT := _build_hit_ability(
	"test_physical_hit",
	"测试物理伤害",
	BattleEvents.DamageType.PHYSICAL
)


static var MAGICAL_HIT := _build_hit_ability(
	"test_magical_hit",
	"测试魔法伤害",
	BattleEvents.DamageType.MAGICAL
)


static var PURE_HIT := _build_hit_ability(
	"test_pure_hit",
	"测试纯粹伤害",
	BattleEvents.DamageType.PURE
)


static func _build_hit_ability(
	config_id: String,
	display_name: String,
	damage_type: BattleEvents.DamageType
) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(config_id)
		.display_name(display_name)
		.ability_tags(["skill", "active", "test"])
		.active_use(
			ActiveUseConfig.builder()
			.timeline_id(TIMELINE_ID)
			.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				Resolvers.float_val(TEST_DAMAGE),
				damage_type
			)])
			.build()
		)
		.build()
	)


func get_name() -> String:
	return "Shield damage-type matrix: physical/magical/universal"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 5},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000},
			{"class": "MAGE", "pos": [2, 0], "hp": 1000},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 1000},
		],
	}


func get_passives() -> Array[AbilityConfig]:
	return [
		HexBattleShieldBuffs.PHYSICAL_SHIELD_BUFF,
		HexBattleShieldBuffs.MAGICAL_SHIELD_BUFF,
		HexBattleWardBuff.WARD_BUFF,
	]


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "enemy_0", "skill": PHYSICAL_HIT, "target": "caster", "time_ms": 0},
		{"caster": "enemy_1", "skill": MAGICAL_HIT, "target": "caster", "time_ms": 1000},
		{"caster": "enemy_2", "skill": PURE_HIT, "target": "caster", "time_ms": 2000},
	]


func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	_assert_single_absorbed_by(
		ctx,
		"physical",
		HexBattleShieldBuffs.PHYSICAL_CONFIG_ID,
		"physical damage consumed physical shield"
	)
	_assert_single_absorbed_by(
		ctx,
		"magical",
		HexBattleShieldBuffs.MAGICAL_CONFIG_ID,
		"magical damage consumed magical shield"
	)
	_assert_single_absorbed_by(
		ctx,
		"pure",
		HexBattleWardBuff.CONFIG_ID,
		"pure damage consumed universal Ward shield"
	)

	ctx.assert_float_eq(ctx.total_damage_to(ctx.caster_id), 0.0,
		"all typed hits were fully absorbed")
	ctx.assert_float_eq(
		ctx.total_shield_absorbed_for(ctx.caster_id),
		ctx.total_modified_damage_to(ctx.caster_id),
		"shield absorption equals modified incoming damage"
	)
	ctx.assert_actor_ability_present(ctx.caster_id, HexBattleShieldBuffs.PHYSICAL_CONFIG_ID,
		"physical shield remains after one small physical hit")
	ctx.assert_actor_ability_present(ctx.caster_id, HexBattleShieldBuffs.MAGICAL_CONFIG_ID,
		"magical shield remains after one small magical hit")
	ctx.assert_actor_ability_present(ctx.caster_id, HexBattleWardBuff.CONFIG_ID,
		"universal Ward remains after one small pure hit")


func _assert_single_absorbed_by(
	ctx: ScenarioAssertContext,
	damage_type: String,
	expected_config_id: String,
	msg: String
) -> void:
	var hits := ctx.filter_damage_events({
		"target_actor_id": ctx.caster_id,
		"damage_type": damage_type,
	})
	ctx.assert_eq(hits.size(), 1, "%s: exactly one %s hit" % [msg, damage_type])
	if hits.size() != 1:
		return

	var hit: Dictionary = hits[0]
	var damage: float = hit.get("damage", 0.0) as float
	ctx.assert_float_eq(hit.get("shield_absorbed", -1.0) as float, damage,
		"%s: shield_absorbed equals damage" % msg)
	ctx.assert_float_eq(hit.get("actual_life_damage", -1.0) as float, 0.0,
		"%s: actual_life_damage is zero" % msg)

	var records: Array = hit.get("consumption_records", [])
	ctx.assert_eq(records.size(), 1, "%s: exactly one shield participated" % msg)
	if records.size() != 1:
		return
	var record: Dictionary = records[0]
	ctx.assert_eq(record.get("shield_config_id", ""), expected_config_id,
		"%s: consumed shield config" % msg)
	ctx.assert_eq(record.get("damage_type", ""), damage_type,
		"%s: record damage_type" % msg)
