## Phase B · attack_lifesteal_pct 默认 0 时 Strike 不回血
##
## V1 契约:
## - 默认 attack_lifesteal_pct = 0
## - Strike 触发 BasicAttackLandedEvent (Phase A 已验) → HexBattleGeneralPassive 监听
## - GeneralPassive 自检 pct <= 0 → early return, 不调 HexBattleHealAction
## - replay 没有 heal event (caster 没被 heal)
##
## 这是 Phase B 自动 grant 的"零侵入"验证：所有 CharacterActor 默认装 GeneralPassive,
## 没属性来源时静悄悄, 不污染既有战斗.
class_name LifestealAttributeDefaultZeroScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "AttackLifesteal: default pct=0 → no heal on Strike"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 100, "max_hp": 200, "atk": CASTER_ATK},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Sanity: Strike emitted BasicAttackLandedEvent (Phase A 契约)
	var attack_events := ctx.events_of_kind("basic_attack_landed")
	ctx.assert_true(attack_events.size() >= 1, "Strike emitted at least 1 BasicAttackLandedEvent (sanity)")

	# 核心契约: 默认 pct=0, 没有任何 heal_event
	var heal_events := ctx.events_of_kind("heal")
	ctx.assert_eq(heal_events.size(), 0,
		"Expect 0 heal events when attack_lifesteal_pct=0 (got %d)" % heal_events.size())
