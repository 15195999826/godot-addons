## 被动技能配置
##
## 使用 NoInstanceComponent 实现被动触发效果。
## 被动技能监听游戏事件，满足条件时自动执行 Action 链。

class_name HexBattlePassiveAbilities


# ========== 被动技能配置 ==========

## 荆棘反伤 - 受到伤害时反弹固定伤害
##
## 触发条件：自己受到伤害时
## 效果：对攻击者造成 2 点纯粹伤害
static var THORN_PASSIVE := (
	AbilityConfig.builder()
	.config_id("passive_thorn")
	.display_name("荆棘反伤")
	.description("受到伤害时，对攻击者造成 2 点伤害")
	.ability_tags(["passive", "defensive", "reflect"])
	.component_config(
		NoInstanceConfig.builder()
		.trigger(TriggerConfig.new("damage", _thorn_filter()))
		.action(HexBattleReflectDamageAction.new(
			2.0,
			BattleEvents.DamageType.PURE
		))
		.build()
	)
	.build()
)


## 荆棘反伤过滤器
static func _thorn_filter() -> Callable:
	return func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var owner_id := ctx.owner_actor_id
		if owner_id.is_empty():
			return false
		# 使用强类型事件
		var damage_event := BattleEvents.DamageEvent.from_dict(event_dict)
		var is_target := damage_event.target_actor_id == owner_id
		var has_source := not damage_event.source_actor_id.is_empty()
		var not_self_damage := damage_event.source_actor_id != owner_id
		return is_target and has_source and not_self_damage and not damage_event.is_reflected


## 亡语：死亡爆发 - 死亡时对所有敌方单位造成 20 点纯粹伤害
##
## 触发条件：自己死亡时
## 效果：对所有敌方存活单位造成 20 点纯粹伤害
static var DEATHRATTLE_AOE := (
	AbilityConfig.builder()
	.config_id("passive_deathrattle_aoe")
	.display_name("死亡爆发")
	.description("死亡时，对所有敌方单位造成 20 点纯粹伤害")
	.ability_tags(["passive", "offensive", "deathrattle"])
	.component_config(
		NoInstanceConfig.builder()
		.trigger(TriggerConfig.new("death", _deathrattle_filter()))
		.action(HexBattleDamageAction.new(
			HexBattleTargetSelectors.all_enemies(),
			20.0,
			BattleEvents.DamageType.PURE
		))
		.build()
	)
	.build()
)


## 亡语过滤器：仅当死亡者是自己时触发
static func _deathrattle_filter() -> Callable:
	return func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var owner_id := ctx.owner_actor_id
		if owner_id.is_empty():
			return false
		var death_event := BattleEvents.DeathEvent.from_dict(event_dict)
		return death_event.actor_id == owner_id


## 生命力被动 - max_hp 越高，atk 越高
##
## 效果：atk += max_hp * 0.01
## 与 VIGOR_PASSIVE 形成循环依赖，用于验证收敛机制
static var VITALITY_PASSIVE: AbilityConfig = (
	AbilityConfig.builder()
	.config_id("passive_vitality")
	.display_name("生命力")
	.description("max_hp 越高，atk 越高（atk += max_hp * 0.01）")
	.ability_tags(["passive", "buff", "dynamic"])
	.component_config(DynamicStatModifierComponentConfig.new(
		DynamicStatModifierConfig.new(
			HexBattleCharacterAttributeSet.max_hp_attribute,                          # 源属性
			HexBattleCharacterAttributeSet.atk_attribute,                             # 目标属性
			AttributeModifier.Type.ADD_BASE,  # 修改器类型
			0.01                               # 系数
		)
	))
	.build()
)


## 活力被动 - atk 越高，max_hp 越高
##
## 效果：max_hp += atk * 0.1
## 与 VITALITY_PASSIVE 形成循环依赖，用于验证收敛机制
static var VIGOR_PASSIVE: AbilityConfig = (
	AbilityConfig.builder()
	.config_id("passive_vigor")
	.display_name("活力")
	.description("atk 越高，max_hp 越高（max_hp += atk * 0.1）")
	.ability_tags(["passive", "buff", "dynamic"])
	.component_config(DynamicStatModifierComponentConfig.new(
		DynamicStatModifierConfig.new(
			HexBattleCharacterAttributeSet.atk_attribute,                             # 源属性
			HexBattleCharacterAttributeSet.max_hp_attribute,                          # 目标属性
			AttributeModifier.Type.ADD_BASE,  # 修改器类型
			0.1                                # 系数
		)
	))
	.build()
)


# ========== 导出 ==========

## 所有被动技能
static func get_passive_ability(passive_type: String) -> AbilityConfig:
	match passive_type:
		"Thorn":
			return THORN_PASSIVE
		"Vitality":
			return VITALITY_PASSIVE
		"Vigor":
			return VIGOR_PASSIVE
		"DeathrattleAoe":
			return DEATHRATTLE_AOE
		_:
			return null
