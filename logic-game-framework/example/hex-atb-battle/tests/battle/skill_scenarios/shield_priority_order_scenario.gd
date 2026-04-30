## Shield 多盾消耗顺序：priority desc → grant_index desc(LIFO) → ability.id asc
##
## 设计：caster 装两个独立护盾
##   LOW_PRIORITY_SHIELD  (priority 0,  capacity 50)  ← 先 grant，grant_index = 0
##   HIGH_PRIORITY_SHIELD (priority 10, capacity 20)  ← 后 grant，grant_index = 1
##
## enemy.atk = 30 → strike 命中 30（无暴击）或 45（暴击）
## 期望消耗顺序：先 HIGH（priority 高），HIGH 破后剩余打 LOW
##   - 30 伤害：HIGH 吸 20 broken → LOW 吸 10（剩 40，未破）
##   - 45 伤害：HIGH 吸 20 broken → LOW 吸 25（剩 25，未破）
class_name ShieldPriorityOrderScenario
extends SkillScenario


const TEST_HIGH_CONFIG_ID := "test_shield_high_priority"
const TEST_LOW_CONFIG_ID := "test_shield_low_priority"
const HIGH_CAPACITY := 20.0
const LOW_CAPACITY := 50.0


## 高优先 shield：cap 20，priority 10。无 duration 限制（60s，跑不到那么久）。
static var HIGH_PRIORITY_SHIELD := (
	AbilityConfig.builder()
	.config_id(TEST_HIGH_CONFIG_ID)
	.display_name("高优先盾(测试)")
	.ability_tags(["buff", "shield", "test"])
	.component_config(HexBattleShieldComponentConfig.new(
		HIGH_CAPACITY, ["all"], 10, "independent"
	))
	.component_config(TimeDurationConfig.new(60000.0))
	.build()
)


## 低优先 shield：cap 50，priority 0
static var LOW_PRIORITY_SHIELD := (
	AbilityConfig.builder()
	.config_id(TEST_LOW_CONFIG_ID)
	.display_name("低优先盾(测试)")
	.ability_tags(["buff", "shield", "test"])
	.component_config(HexBattleShieldComponentConfig.new(
		LOW_CAPACITY, ["all"], 0, "independent"
	))
	.component_config(TimeDurationConfig.new(60000.0))
	.build()
)


func get_name() -> String:
	return "Shield priority order: high priority consumed first regardless of grant order"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 1000},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "atk": 30, "hp": 500}],
	}


## passives 顺序故意把 LOW 放前面（grant_index 小），HIGH 后面 —— 验证 priority 优先于 LIFO
func get_passives() -> Array[AbilityConfig]:
	return [LOW_PRIORITY_SHIELD, HIGH_PRIORITY_SHIELD]


func get_actions() -> Array[Dictionary]:
	return [{"caster": "enemy_0", "skill": HexBattleStrike.ABILITY, "target": "caster"}]


func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var dmgs := ctx.filter_damage_events({"target_actor_id": ctx.caster_id})
	if dmgs.is_empty():
		ctx.fail("no damage event captured")
		return

	var first: Dictionary = dmgs[0]
	var records: Array = first.get("consumption_records", [])

	# damage 30 / 45：两道护盾都参与
	ctx.assert_eq(records.size(), 2, "exactly 2 shields participated")
	if records.size() < 2:
		return

	# 第一条应是 HIGH（priority 优先）
	var first_record: Dictionary = records[0]
	ctx.assert_eq(first_record.get("shield_config_id", ""), TEST_HIGH_CONFIG_ID,
		"first consumed = high priority shield")
	ctx.assert_eq(first_record.get("broken", false), true,
		"high priority shield broken (cap 20 < damage)")
	ctx.assert_float_eq(first_record.get("absorbed", 0.0) as float, HIGH_CAPACITY,
		"high priority shield absorbed = 20")

	# 第二条应是 LOW，未破
	var second_record: Dictionary = records[1]
	ctx.assert_eq(second_record.get("shield_config_id", ""), TEST_LOW_CONFIG_ID,
		"second consumed = low priority shield")
	ctx.assert_eq(second_record.get("broken", false), false,
		"low priority shield not broken (cap 50 > leftover)")

	# 整体 actual_life_damage 应为 0（护盾总容量 70 > 任意 strike 命中）
	var actual_life: float = first.get("actual_life_damage", -1.0) as float
	ctx.assert_float_eq(actual_life, 0.0, "actual_life_damage = 0 (shields cover all)")
