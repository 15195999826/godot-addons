## Daedalus 暴击 — equipment-granted attack effect (Phase G)
##
## Daedalus Charm 装备 grant 本 passive 给 owner; owner 普攻进入 `DamageAction` 前的
## `PreBasicAttackEvent` 阶段, 按 chance 决定本次普攻是否暴击, 命中时:
##   - `Modification.multiply("attack_damage", DAMAGE_MULTIPLIER)` 放大本次普攻 attack_damage
##   - `Modification.set_value("is_critical", 1.0)` 把 is_critical 写为 numeric 1.0
##     (DamageAction 内部 `>= 0.5` → DamageEvent.is_critical = true)
##
## 普通 active skill / Fireball / Poison / Fire Tile / Totem damage / reflected damage
## 不调用 `emit_pre_basic_attack()`, 不进入本 handler; equipment crit rule 与那些伤害源
## 解耦 (这是与 `PreDamageEvent` 的关键区别)。
##
## §V1 数值: dev scene 配置 chance = 1.0, damage_multiplier = 2.25 ——
##   - chance = 1.0 让 dev scene 自主验收 (DevAgent /run-dev-scene) 不被 RNG flaky 影响
##   - 生产装备可在 `create_config()` 传入 chance = 0.3 等较低值
##   - V1 不引入 fixed-seed RNG hook; 真实概率装备的 scenario 假设上层 RNG 已确定 (例
##     headless `randf` seed 一致或 scenario assert 接受概率分布)
class_name HexBattlePassiveDaedalusCriticalStrike


const CONFIG_ID := "passive_daedalus_critical_strike"

## V1 默认值: dev scene 必命中, demo 数值好观察
const DEFAULT_CHANCE := 1.0
const DEFAULT_DAMAGE_MULTIPLIER := 2.25

const SOURCE_NAME := "Daedalus Critical Strike"


static var ABILITY: AbilityConfig = create_config(DEFAULT_CHANCE, DEFAULT_DAMAGE_MULTIPLIER)


## 工厂方法: 允许调用方覆盖 chance / damage_multiplier (生产装备可改 chance = 0.3 等)。
##
## [param chance] 0.0..1.0 概率, randf() < chance 暴击
## [param damage_multiplier] 暴击时 attack_damage 倍率
## [return] AbilityConfig
static func create_config(chance: float = DEFAULT_CHANCE, damage_multiplier: float = DEFAULT_DAMAGE_MULTIPLIER) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("代达罗斯暴击")
		.description("%.0f%% 概率使普攻暴击, 暴击伤害 ×%.2f (Phase G equipment-granted attack effect)" % [chance * 100.0, damage_multiplier])
		.ability_tags(["passive", "equipment", "attack_effect", "critical_strike"])
		.meta(&"attack_effect", {
			"kind": &"critical_strike",
			"chance": chance,
			"damage_multiplier": damage_multiplier,
		})
		.component_config(_build_pre_basic_attack_config(chance, damage_multiplier))
		.build()
	)


## 仅当 PreBasicAttackEvent.source_actor_id == owner 时 roll;
## 命中后 modify attack_damage *= damage_multiplier 且 set is_critical = 1.0。
##
## 字段名 (`attack_damage` / `is_critical`) 必须与 HexBattlePreEvents.PreBasicAttackEvent.to_dict()
## 严格一致 —— DamageAction 通过 `mutable_basic.get_current_value("attack_damage")` /
## `("is_critical")` 读取 modified 值。
static func _build_pre_basic_attack_config(chance: float, damage_multiplier: float) -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_BASIC_ATTACK_EVENT,
		func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			if randf() >= chance:
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("attack_damage", damage_multiplier, ctx.ability.config_id, SOURCE_NAME),
				Modification.set_value("is_critical", 1.0, ctx.ability.config_id, SOURCE_NAME),
			]),
		func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return event_dict.get("source_actor_id", "") == ctx.owner_actor_id,
		SOURCE_NAME,
	)
