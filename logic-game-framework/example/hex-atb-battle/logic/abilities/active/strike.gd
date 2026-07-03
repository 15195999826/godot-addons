## Strike - 近战基础攻击 (basic attack)
##
## 相邻格物理伤害,以 caster.atk 作为本次普攻基础伤害。
##
## §Phase G — 普攻特效契约:
##   1. Strike 进入 DamageAction 时通过 `emit_pre_basic_attack()` 在每个 target 上 emit
##      `PreBasicAttackEvent`,允许装备 grant 的 attack-effect passive 修改 attack_damage /
##      is_critical (例如 Daedalus passive 写 multiply 2.25 / set is_critical=1.0)。
##   2. Strike 自身不再硬编码暴击 (移除 `randf() < 0.1` / `* 1.5` / `+10 crit bonus`)。
##   3. 普通 active skill / Fireball / Poison / Fire Tile / Totem damage / reflected damage
##      不调用 `emit_pre_basic_attack()`,不读 equipment crit rule。
##
## 命中后通过 `on_hit` 链路 emit `BasicAttackLandedEvent`,供 GeneralPassive 触发 lifesteal
## 等"普攻命中后"反应。
##
## 契约示范:damage 用 Resolver 读 caster.atk,随属性缩放。
##   - 这让 Buff/Debuff/装备对 atk 的修改自动影响 Strike 伤害
##   - Hook 类技能(Ward 拦伤、Expose 增伤)在 PreDamage 阶段作用于已解析的数值
##   - 未来其他物理技能(CrushingBlow 等)可复制此 resolver 模板
class_name HexBattleStrike


const CONFIG_ID := "skill_strike"
const TIMELINE_ID := "skill_strike"
const COOLDOWN_MS := 2000.0


static var STRIKE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


## caster.atk 作为基础伤害；resolve 在 DamageAction.execute() 时按 ctx 读取
static var _CASTER_ATK_DAMAGE: FloatResolver = HexBattleSkillHelpers.caster_atk_damage()


## Phase A · 普攻命中后 emit BasicAttackLandedEvent.
## 挂在主 damage action 的 on_hit chain。
## callback ctx 已携带主 damage event dict; cancelled / dead-target 由 DamageAction 上游 skip,
## 这里不会被复触发。事件 push 到 event_collector + broadcast 给存活 actor 以触发被动.
##
## alive_actor_ids 用 fresh fetch (不复用父 DamageAction 的 stale snapshot): 若 target 在
## 本次 hit 被打死, fresh list 会自动排除 target —— basic_attack_landed broadcast 不去打扰已死的
## actor 是更符合"基础攻击命中"语义的选择. (broadcast_post_damage 沿用 stale 是 LGF 框架既定
## 约定, 二者不强求一致.) 当前 attacker 侧 lifesteal 监听, attacker 必在 fresh list.
class _EmitBasicAttackLandedAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), HexBattleStrike.CONFIG_ID)
		type = "emit_basic_attack_landed"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var damage_event_dict := ctx.get_current_event()
		if damage_event_dict.is_empty():
			return ActionResult.create_success_result([], { "basic_attack_landed_skipped": "no_damage_event" })
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return ActionResult.create_success_result([], { "basic_attack_landed_skipped": "no_game_state" })
		var attacker_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if attacker_id.is_empty():
			return ActionResult.create_success_result([], { "basic_attack_landed_skipped": "no_attacker" })

		Log.assert_crash(damage_event_dict.has("actual_life_damage"),
			"HexBattleStrike._EmitBasicAttackLandedAction",
			"damage_event_dict 缺 actual_life_damage 字段; 上游应通过 HexBattleDamageUtils.apply_damage 注入")
		Log.assert_crash(damage_event_dict.has("target_actor_id"),
			"HexBattleStrike._EmitBasicAttackLandedAction",
			"damage_event_dict 缺 target_actor_id 字段")

		var target_id := damage_event_dict.get("target_actor_id", "") as String
		var actual_life_damage := damage_event_dict.get("actual_life_damage", 0.0) as float
		var source_ability_id := ctx.ability_ref.id if ctx.ability_ref != null else ""
		var source_ability_config_id := ctx.ability_ref.config_id if ctx.ability_ref != null else ""

		var event := BattleEvents.BasicAttackLandedEvent.create(
			attacker_id,
			target_id,
			source_ability_id,
			source_ability_config_id,
			actual_life_damage,
			damage_event_dict,
		)
		var event_dict: Dictionary = ctx.event_collector.push(event.to_dict())

		var alive_actor_ids := battle.get_alive_actor_ids()
		if alive_actor_ids.size() > 0:
			GameWorld.event_processor.process_post_event(event_dict, alive_actor_ids, battle)

		return ActionResult.create_success_result(
			[event_dict],
			{ "basic_attack_landed_actual_life_damage": actual_life_damage }
		)


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("普通攻击")
	.description("近战攻击，对敌人造成物理伤害（暴击/特效由装备 grant 的 PreBasicAttackEvent passive 决定）")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 1)
	.active_use(
		HexBattleCooldownSystem.apply_basic_attack_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("melee_slash")
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL
			).emit_pre_basic_attack().on_hit(_EmitBasicAttackLandedAction.new()),
		])
		.build()
	)
	.build()
)
