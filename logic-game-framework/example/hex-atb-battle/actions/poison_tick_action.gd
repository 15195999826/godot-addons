## PoisonTickAction - 中毒 DOT 每轮 tick
##
## 职责（单个 execute 内完成）：
## 1. 解析当前 poison_buff ability（通过 ctx.ability_ref.resolve()）
## 2. 读取 stacks；若 stacks <= 0 → expire ability，return（loop 不再驱动）
## 3. 对 ability owner 自身造成 = stacks 的 PURE 伤害（走 pre/post damage 全流程）
## 4. remove_stacks(1)；若减完后为 0 → expire ability
##
## 设计约定：
## - Action 共享无状态 → 所有中间值用 local var，绝不写 self
## - 伤害 source = buff.source_actor_id（原施法者），target = buff.owner_actor_id（中毒者自己）
## - 走 HexBattleDamageUtils.apply_damage 以复用 pre/death/log 流程，避免重复实现
class_name HexBattlePoisonTickAction
extends Action.BaseAction


func _init() -> void:
	# Poison tick 的"目标"始终是 buff 持有者自身，无需 target_selector
	super._init(HexBattleTargetSelectors.ability_owner())
	type = "poison_tick"


func execute(ctx: ExecutionContext) -> ActionResult:
	if ctx.ability_ref == null:
		return ActionResult.create_success_result([], {})

	var ability := ctx.ability_ref.resolve()
	if ability == null or ability.is_expired():
		return ActionResult.create_success_result([], {})

	var stacks := ability.get_stacks()
	if stacks <= 0:
		ability.expire("poison_exhausted")
		return ActionResult.create_success_result([], {})

	var battle: HexBattle = ctx.game_state_provider
	if battle == null:
		return ActionResult.create_success_result([], {})

	var target_id := ability.owner_actor_id
	var source_id := ability.source_actor_id if not ability.source_actor_id.is_empty() else target_id
	var alive_actor_ids := battle.get_alive_actor_ids()

	# ========== Pre 阶段（允许减伤/免疫拦截） ==========
	var pre_event := HexBattlePreEvents.PreDamageEvent.create(
		source_id, target_id, float(stacks),
		BattleEvents._damage_type_to_string(BattleEvents.DamageType.PURE)
	)
	var mutable: MutableEvent = GameWorld.event_processor.process_pre_event(pre_event.to_dict(), battle)
	var all_events: Array[Dictionary] = []

	if not mutable.cancelled:
		var final_damage: float = mutable.get_current_value("damage")
		var damage_event := BattleEvents.DamageEvent.create(
			target_id, final_damage, BattleEvents.DamageType.PURE, source_id, false, false
		)
		var damage_result := HexBattleDamageUtils.apply_damage(damage_event, alive_actor_ids, ctx, battle)
		all_events.append_array(damage_result.all_events)
		HexBattleDamageUtils.broadcast_post_damage(damage_result.damage_event_dict, alive_actor_ids, battle)

	# ========== 层数递减（无论是否 cancelled 都消耗一层） ==========
	ability.remove_stacks(1)
	if ability.get_stacks() <= 0:
		ability.expire("poison_exhausted")

	return ActionResult.create_success_result(all_events, { "poison_tick_stacks": stacks })
