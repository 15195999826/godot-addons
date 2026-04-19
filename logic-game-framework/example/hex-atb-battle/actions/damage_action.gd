## DamageAction - 伤害 Action
##
## ========== 设计原则 ==========
##
## Action 是原子操作单元：push 事件 + 应用状态 + post 事件 必须连续执行。
## EventCollector 仅供录像/表演层消费，不参与逻辑状态同步。
##
## 分层职责：
## - AbilityComponent 决定「何时执行」
## - Action 决定「做什么」
## - BattleEvent 记录「结果」
##
## ========== 执行流程 ==========
##
## 1. Pre 阶段：创建 pre_damage 事件
##    - 允许减伤/免疫等被动修改或取消伤害
##    - 如果 mutable.cancelled，跳过此目标
##
## 2. 产生事件 + 应用状态（原子操作）：
##    - ctx.event_collector.push(damage_event)  ← 事件入队（录像用）
##    - target.attribute_set.set_hp_base(target.attribute_set.hp - damage) ← 立即扣血
##
## 3. 死亡检测：
##    - if check_death(): 
##        push(death_event) → process_post_event(death_event) → remove_actor()
##
## 4. 处理回调：on_hit / on_critical / on_kill
##
## 5. Post 阶段：触发反伤/吸血等被动响应
##
## ========== 支持的回调 ==========
##
## - on_hit: 每次命中时触发
## - on_critical: 暴击时触发
## - on_kill: 击杀时触发
##
class_name HexBattleDamageAction
extends Action.BaseAction


var _damage_resolver: FloatResolver
var _damage_type: BattleEvents.DamageType

# 回调列表
var _on_hit_callbacks: Array[Action.BaseAction] = []
var _on_critical_callbacks: Array[Action.BaseAction] = []
var _on_kill_callbacks: Array[Action.BaseAction] = []


## damage_resolver 在 execute() 中按 ctx 解析一次。
## 固定伤害用 Resolvers.float_val(X)；随施法者属性缩放用 Resolvers.float_fn。
func _init(
	target_selector: TargetSelector,
	damage_resolver: FloatResolver,
	damage_type: BattleEvents.DamageType = BattleEvents.DamageType.PHYSICAL
) -> void:
	super._init(target_selector)
	type = "damage"
	_damage_resolver = damage_resolver
	_damage_type = damage_type


## 重写 _freeze 以冻结回调 Action
func _freeze() -> void:
	super._freeze()
	for callback in _on_hit_callbacks:
		callback._freeze()
	for callback in _on_critical_callbacks:
		callback._freeze()
	for callback in _on_kill_callbacks:
		callback._freeze()


# ============================================================
# 回调注册（链式调用）
# ============================================================

## 注册命中回调
func on_hit(action: Action.BaseAction) -> HexBattleDamageAction:
	_on_hit_callbacks.append(action)
	return self


## 注册暴击回调
func on_critical(action: Action.BaseAction) -> HexBattleDamageAction:
	_on_critical_callbacks.append(action)
	return self


## 注册击杀回调
func on_kill(action: Action.BaseAction) -> HexBattleDamageAction:
	_on_kill_callbacks.append(action)
	return self


# ============================================================
# 执行
# ============================================================

func execute(ctx: ExecutionContext) -> ActionResult:
	var source_actor_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var event_processor := GameWorld.event_processor
	var all_events: Array[Dictionary] = []
	var alive_actor_ids := battle.get_alive_actor_ids()
	# 每次 execute 解析一次 base damage（同一次施法对所有目标使用同一数值）
	var base_damage := _damage_resolver.resolve(ctx)

	for target_id in targets:
		# ========== Pre 阶段 ==========
		var pre_event := HexBattlePreEvents.PreDamageEvent.create(
			source_actor_id,
			target_id,
			base_damage,
			BattleEvents._damage_type_to_string(_damage_type)
		)

		var mutable: MutableEvent = event_processor.process_pre_event(pre_event.to_dict(), battle)

		if mutable.cancelled:
			var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
			print("  [DamageAction] %s 的伤害被取消" % target_name)
			continue

		var final_damage: float = mutable.get_current_value("damage")
		var is_critical := randf() < 0.1
		if is_critical:
			final_damage *= 1.5

		var source_name := HexBattleGameStateUtils.get_actor_display_name(source_actor_id, battle)
		var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
		var damage_type_str := BattleEvents._damage_type_to_string(_damage_type)
		var crit_text := " (暴击!)" if is_critical else ""
		if final_damage != base_damage:
			print("  [DamageAction] %s 对 %s 造成 %.0f %s 伤害%s (原始: %.0f)" % [source_name, target_name, final_damage, damage_type_str, crit_text, base_damage])
		else:
			print("  [DamageAction] %s 对 %s 造成 %.0f %s 伤害%s" % [source_name, target_name, final_damage, damage_type_str, crit_text])

		# ========== 应用伤害 + 死亡处理 ==========
		var event := BattleEvents.DamageEvent.create(
			target_id, final_damage, _damage_type, source_actor_id, is_critical, false
		)
		var damage_result := HexBattleDamageUtils.apply_damage(
			event, alive_actor_ids, ctx, battle,
		)
		all_events.append_array(damage_result.all_events)

		# ========== 回调处理（在 post damage 广播之前） ==========
		var callback_events := _process_callbacks(damage_result.damage_event_dict, is_critical, ctx)
		all_events.append_array(callback_events)

		# ========== Post damage 广播 ==========
		HexBattleDamageUtils.broadcast_post_damage(
			damage_result.damage_event_dict, alive_actor_ids, battle,
		)

	return ActionResult.create_success_result(all_events, { "damage": base_damage })


# ============================================================
# 回调处理
# ============================================================

func _process_callbacks(damage_event: Dictionary, is_critical: bool, ctx: ExecutionContext) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var callback_ctx := ExecutionContext.create_callback_context(ctx, damage_event)
	
	# on_hit: 每次命中都触发
	for callback in _on_hit_callbacks:
		var result := callback.execute(callback_ctx)
		callback._verify_unchanged()
		if result != null and result.event_dicts:
			events.append_array(result.event_dicts)
	
	# on_critical: 仅暴击时触发
	if is_critical:
		for callback in _on_critical_callbacks:
			var result := callback.execute(callback_ctx)
			callback._verify_unchanged()
			if result != null and result.event_dicts:
				events.append_array(result.event_dicts)
	
	# on_kill: 检查目标是否死亡
	var is_kill := _check_target_killed(damage_event, ctx)
	if is_kill:
		for callback in _on_kill_callbacks:
			var result := callback.execute(callback_ctx)
			callback._verify_unchanged()
			if result != null and result.event_dicts:
				events.append_array(result.event_dicts)
	
	return events


func _check_target_killed(damage_event: Dictionary, ctx: ExecutionContext) -> bool:
	# 使用强类型事件
	var event := BattleEvents.DamageEvent.from_dict(damage_event)
	if event.target_actor_id.is_empty():
		return false
	return HexBattleGameStateUtils.is_actor_dead(event.target_actor_id, ctx.game_state_provider)
