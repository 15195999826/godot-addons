## Dota2DamageAction - 基础攻击的伤害 Action（attack point keyframe 触发）
##
## lgf-skill-model.md / m1-contract.md：基础攻击走 Ability/Timeline/Action/Event 路径，
## AttackTargetIntent **不**直接掉血。本 Action 由 Dota2BasicAttackAbility 的 Timeline
## 在 attack point tag 处触发：
##   pre_damage（buff/passive hook，M1 handler 空）→ 应用伤害（原子：扣 hp + push 事件）
##   → attack_landed / damage_applied →（若致死）unit_died → post_damage 广播
##
## M1 简化：伤害 = attacker.attribute_set.attack_damage（无 armor 公式，见
## actor-attributes.md armor 待定）。与 hex damage_action / rts basic_attack_action 同构。
class_name Dota2DamageAction
extends Action.BaseAction


func _init(target_selector: TargetSelector) -> void:
	super._init(target_selector)
	type = "dota2_damage"


func execute(ctx: ExecutionContext) -> ActionResult:
	var source_id: String = ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if source_id.is_empty():
		return ActionResult.create_failure_result("no source actor (ability_ref missing)")

	var world: Dota2WorldGameplayInstance = ctx.game_state_provider as Dota2WorldGameplayInstance
	if world == null:
		return ActionResult.create_failure_result("game_state_provider not Dota2WorldGameplayInstance")

	var attacker: Dota2UnitActor = world.get_actor(source_id) as Dota2UnitActor
	if attacker == null or attacker.is_dead():
		return ActionResult.create_success_result([])

	var targets := get_targets(ctx)
	if targets.is_empty():
		return ActionResult.create_success_result([])

	var event_processor: EventProcessor = GameWorld.event_processor
	var event_collector: EventCollector = ctx.event_collector
	var all_events: Array[Dictionary] = []
	var alive_actor_ids := world.get_alive_actor_ids()
	var base_damage: float = attacker.attribute_set.attack_damage

	for target_id in targets:
		var target: Dota2BattleActor = world.get_actor(target_id) as Dota2BattleActor
		if target == null or target.is_dead():
			continue

		# ===== Pre 阶段（M1 handler 空，一律 PASS；边界先在给未来 buff/passive）=====
		var pre_event := Dota2BattleEvents.make_pre_damage(source_id, target_id, base_damage)
		var mutable: MutableEvent = event_processor.process_pre_event(pre_event, world)
		if mutable.cancelled:
			continue
		var final_damage: float = mutable.get_current_value("damage")

		# ===== attack_landed（命中事实，伤害结算前）=====
		var landed := Dota2BattleEvents.make_attack_landed(source_id, target_id, final_damage)
		event_collector.push(landed)
		all_events.append(landed)

		# ===== 应用伤害（原子：扣 hp + push 事件连续）=====
		var target_attrs := target.get_attribute_set()
		var hp_before: float = target_attrs.hp
		var hp_after: float = maxf(0.0, hp_before - final_damage)
		target_attrs.set_hp_base(hp_after)

		var dmg_evt := Dota2BattleEvents.make_damage_applied(source_id, target_id, final_damage, hp_after)
		event_collector.push(dmg_evt)
		all_events.append(dmg_evt)

		# ===== 死亡判定 =====
		if hp_after <= 0.0 and not target.is_dead():
			target.mark_dead()
			var died := Dota2BattleEvents.make_unit_died(target_id, source_id)
			event_collector.push(died)
			all_events.append(died)

		# ===== Post 阶段（thorns/lifesteal 等未来被动 hook；M1 广播即可）=====
		var post_event := Dota2BattleEvents.make_post_damage(source_id, target_id, final_damage, hp_after)
		event_processor.process_post_event(post_event, alive_actor_ids, world)

	return ActionResult.create_success_result(all_events)
