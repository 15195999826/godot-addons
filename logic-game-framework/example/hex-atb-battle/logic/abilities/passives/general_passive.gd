## HexBattleGeneralPassive · 角色内建规则桥
##
## 每个 CharacterActor 自动持有的"角色属性 → 标准战斗效果"翻译层. 不是普通 passive —
## 不打 `passive` tag, Break 不应禁用它. tags 使用 `intrinsic` / `character_rules`
## 表达"角色固有规则, 与 buff/可选 passive 区分".
##
## Phase B 实现的子能力:
##   - attack_lifesteal_pct: BasicAttackLandedEvent → 按 actual_life_damage * pct heal attacker.
##
## 未来按需扩展 (本文档列出的 contract):
##   - hp_regen_per_sec (Phase C)
##   - mp_regen_per_sec (留语义, 不本轮实现)
##
## 不承载: Thorn / DemonForm / FrostOrb / kill-trigger / counter-attack / 任何
## 有独立 cooldown / 叠层 / 互斥 / 优先级管理 的命名机制. 这些都建模为独立 passive,
## 受 Break / Cleanse 管控.
##
## 属性来源:
## - VampiricTraining 等普通 passive 通过 StatModifier 给 owner 加 attack_lifesteal_pct.
## - Break 禁用 VampiricTraining 之类的属性来源后, attack_lifesteal_pct 自然归零,
##   HexBattleGeneralPassive 自然 no-op. HexBattleGeneralPassive 自己不变.
class_name HexBattleGeneralPassive


const CONFIG_ID := "general_passive"
const REGEN_TIMELINE_ID := "general_passive_regen"
const REGEN_INTERVAL_MS := 1000.0  # 每 1 秒 tick 一次, 与 hp_regen_per_sec 单位对齐.
const REGEN_INTERVAL_SECONDS := REGEN_INTERVAL_MS / 1000.0


static var REGEN_TIMELINE := TimelineData.periodic(REGEN_TIMELINE_ID, REGEN_INTERVAL_MS)


## per-sec 解析: 在每次 tick 时读 owner 当前 hp_regen_per_sec (会随 buff/passive grant/revoke 浮动).
static var _HP_REGEN_PER_SEC_RESOLVER: FloatResolver = Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
	var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if owner_id.is_empty():
		return 0.0
	var actor := GameWorld.get_actor(owner_id)
	if actor == null or not (actor is CharacterActor):
		return 0.0
	return (actor as CharacterActor).attribute_set.hp_regen_per_sec
)


## attack_lifesteal_pct = 0 / actual_life_damage = 0 / source 不在场都走早退,
## 不产生 heal event. 健壮性 ge: 不假设 attacker 仍活 (caster mid-cast 死亡仍允许 emit
## BasicAttackLandedEvent —— consumer 自查).
class _LifestealAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleGeneralPassive.CONFIG_ID)
		type = "general_passive_lifesteal"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var event_dict := ctx.get_current_event()
		if event_dict.is_empty():
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_event" })
		var actual_life_damage := event_dict.get("actual_life_damage", 0.0) as float
		if actual_life_damage <= 0.0:
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_actual_damage" })

		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_game_state" })
		var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if owner_id.is_empty():
			return ActionResult.create_success_result([], { "lifesteal_skipped": "no_owner" })
		var attacker := battle.get_character_actor(owner_id)
		if attacker == null or attacker.is_dead():
			return ActionResult.create_success_result([], { "lifesteal_skipped": "attacker_unavailable" })
		var pct := attacker.attribute_set.attack_lifesteal_pct
		if pct <= 0.0:
			return ActionResult.create_success_result([], { "lifesteal_skipped": "zero_pct" })

		var heal_amount := actual_life_damage * pct
		var heal_action := HexBattleHealAction.new(
			HexBattleTargetSelectors.fixed([owner_id]),
			Resolvers.float_val(heal_amount),
		)
		var result := heal_action.execute(ctx)
		return ActionResult.create_success_result(
			result.event_dicts if result != null else [],
			{ "lifesteal_heal": heal_amount, "actual_life_damage": actual_life_damage, "pct": pct }
		)


## Trigger filter: attacker 必须是 passive owner; basic_attack_landed event 只对"我打出"那一次响应.
## actual_life_damage > 0 检查放在 _LifestealAction 内部, 不进 filter —— 仅作风格选择, NoInstanceComponent
## 的 filter 对其它 basic_attack_landed 消费者 (Phase B+ 装备 on-hit / 法球) 没有 short-circuit 语义.
static func _basic_attack_landed_filter() -> Callable:
	return func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		var owner_id := ctx.owner_actor_id
		if owner_id.is_empty():
			return false
		var attacker_id := event_dict.get("attacker_actor_id", "") as String
		return attacker_id == owner_id


static var ABILITY: AbilityConfig = (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("角色内建规则")
	.description("角色属性 → 标准战斗效果的桥接：普攻吸血、生命恢复、未来法力恢复")
	.ability_tags(["intrinsic", "character_rules"])
	.component_config(
		NoInstanceConfig.builder()
		.trigger(TriggerConfig.new("basic_attack_landed", _basic_attack_landed_filter()))
		.action(_LifestealAction.new())
		.build()
	)
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline(REGEN_TIMELINE)
		.on_timeline_end([HexBattleRegenerateAction.new(
			HexBattleTargetSelectors.ability_owner(),
			"hp",
			_HP_REGEN_PER_SEC_RESOLVER,
			REGEN_INTERVAL_SECONDS,
			"general_passive",
		)])
		.build()
	)
	.build()
)
