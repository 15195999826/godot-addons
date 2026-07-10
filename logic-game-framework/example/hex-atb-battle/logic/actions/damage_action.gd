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
## 1. §Phase G PreBasicAttackEvent (仅 emit_pre_basic_attack=true 普攻路径):
##    - Strike 等普攻 action 通过 emit_pre_basic_attack() chain 开启
##    - 允许装备 grant 的 attack-effect passive 修改 attack_damage / is_critical
##    - 如果 mutable_basic.cancelled，跳过此目标
##
## 2. Pre 阶段：创建 pre_damage 事件
##    - 允许减伤/免疫等被动修改或取消伤害
##    - 如果 mutable.cancelled，跳过此目标
##
## 3. 产生事件 + 应用状态（原子操作）：
##    - ctx.event_collector.push(damage_event)  ← 事件入队（录像用）
##    - target.attribute_set.set_hp_base(target.attribute_set.hp - damage) ← 立即扣血
##
## 4. 死亡检测：
##    - if check_death():
##        push(death_event) → process_post_event(death_event) → remove_actor()
##
## 5. 处理回调：on_hit / on_critical / on_kill
##
## 6. Post 阶段：触发反伤/吸血等被动响应
##
## ========== 支持的回调 ==========
##
## - on_hit: 每次命中时触发
## - on_critical: 暴击时触发 (is_critical 来源于 PreBasicAttackEvent; 非普攻路径恒为 false)
## - on_kill: 击杀时触发
##
## ========== §Phase G 暴击规则 ==========
##
## DamageAction 自身不再做 randf 暴击；is_critical 由本次的 attack_pipeline 决定：
## - 普攻路径 (Strike emit_pre_basic_attack()): 由装备 grant 的 PreBasicAttackEvent
##   handler 决定 (例如 Daedalus passive 写 `Modification.set_value("is_critical", 1.0)`)
## - 非普攻 (Fireball / Poison / Reflect / Fire Tile / Totem / ...): is_critical 恒为 false
##
class_name HexBattleDamageAction
extends Action.BaseAction


var _damage_resolver: FloatResolver
var _damage_type: BattleEvents.DamageType
## §Phase G: 是否在每个 target 上 emit PreBasicAttackEvent。
##
## 仅由"普攻类 action"(目前是 Strike) 通过 emit_pre_basic_attack() 打开。
## 默认 false: 通用 DamageAction (Fireball/Poison/Reflect/Fire Tile/Totem/...)
## 不参与普攻特效链路, is_critical 始终为 false。
##
## 打开后 per-target 流程:
##   PreBasicAttackEvent → (cancel? skip : 取 modified attack_damage / is_critical)
##     → PreDamageEvent → apply_damage → callbacks → broadcast
var _emit_pre_basic_attack: bool = false

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


## §Phase G: 把本 DamageAction 标记为"普攻"路径,使其在每个 target 上先 emit
## `PreBasicAttackEvent`,让装备 grant 的 attack-effect passive 修改本次 attack_damage
## 与 is_critical。Strike (以及未来其它 basic-attack ability) 应在 builder chain 末尾调用。
## 其它伤害源 (skill / DOT / reflect / passive damage) 不调用。
func emit_pre_basic_attack(p_value: bool = true) -> HexBattleDamageAction:
	_emit_pre_basic_attack = p_value
	return self


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


## 只读探查口: 合并返回全部已注册回调 action(on_hit / on_critical / on_kill),
## 供 manifest lint 收集回调链上的 StageCue 等静态声明。执行路径不使用。
func get_callback_actions() -> Array[Action.BaseAction]:
	var out: Array[Action.BaseAction] = []
	out.append_array(_on_hit_callbacks)
	out.append_array(_on_critical_callbacks)
	out.append_array(_on_kill_callbacks)
	return out


# ============================================================
# 执行
# ============================================================

func execute(ctx: ExecutionContext) -> ActionResult:
	var source_actor_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var source_ability_id := ctx.ability_ref.id if ctx.ability_ref != null else ""
	var source_ability_config_id := ctx.ability_ref.config_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var event_processor := GameWorld.event_processor
	var all_events: Array[Dictionary] = []
	var alive_actor_ids := battle.get_alive_actor_ids()
	# 每次 execute 解析一次 base damage（同一次施法对所有目标使用同一数值）
	var base_damage := _damage_resolver.resolve(ctx)

	for target_id in targets:
		# §0.5: per-target dead/null guard.
		# 死亡 actor 留在 world 用于死亡动画 / buff 对账,但 DamageAction 不应继续对其结算。
		# skip 后：不进 PreDamageEvent / 不 apply_damage / 不触发 on_hit/on_critical/on_kill
		# 回调 / 不 broadcast post damage,避免 shield/expose/lifesteal/thorns/counter 误触发。
		var target_actor: HexBattleActor = battle.get_actor(target_id) if battle != null else null
		if target_actor == null or target_actor.is_dead():
			continue

		# ========== §Phase G PreBasicAttackEvent (仅普攻路径) ==========
		# 普攻特效 (Daedalus critical strike 等) 在此 modify attack_damage / is_critical。
		# 非普攻 (skill / DOT / reflect / Fire Tile / Totem) 默认 _emit_pre_basic_attack=false,
		# 跳过此阶段, is_critical 始终 false。
		var attack_damage: float = base_damage
		var is_critical: bool = false
		if _emit_pre_basic_attack:
			var pre_basic := HexBattlePreEvents.PreBasicAttackEvent.create(
				source_actor_id, target_id, base_damage,
				source_ability_id, source_ability_config_id,
			)
			var mutable_basic: MutableEvent = event_processor.process_pre_event(pre_basic.to_dict(), battle)
			if mutable_basic.cancelled:
				var cancelled_target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
				print("  [DamageAction] %s 的普攻被 PreBasicAttackEvent 取消" % cancelled_target_name)
				continue
			attack_damage = mutable_basic.get_current_value("attack_damage") as float
			is_critical = (mutable_basic.get_current_value("is_critical") as float) >= 0.5

		# ========== PreDamageEvent (通用伤害修改) ==========
		var pre_event := HexBattlePreEvents.PreDamageEvent.create(
			source_actor_id,
			target_id,
			attack_damage,
			BattleEvents._damage_type_to_string(_damage_type)
		)

		var mutable: MutableEvent = event_processor.process_pre_event(pre_event.to_dict(), battle)

		if mutable.cancelled:
			var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)
			print("  [DamageAction] %s 的伤害被取消" % target_name)
			continue

		var final_damage: float = mutable.get_current_value("damage")

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
