## ReflectDamageAction - 反伤 Action
##
## ========== 设计原则 ==========
##
## Action 是原子操作单元：push 事件 + 应用状态 + post 事件 必须连续执行。
## 与 DamageAction 遵循相同的设计，确保状态同步的原子性。
##
## ========== 用途 ==========
##
## 用于被动技能触发时，对攻击来源造成固定伤害。
## 从触发事件中获取 source（攻击者），对其造成伤害。
##
## ========== 执行流程 ==========
##
## 1. 从 current_event 获取 source_actor_id（攻击者）
## 2. 产生反伤事件 + 立即应用伤害（原子操作）
## 3. 死亡检测：push(death_event) → process_post_event → remove_actor
## 4. Post 阶段：触发其他被动（如吸血）
##
## ========== 反伤链防护 ==========
##
## 反伤产生的 damage 事件带有 is_reflected: true 标记，
## 荆棘被动应在 filter 中排除这类事件，避免无限循环。
##
class_name HexBattleReflectDamageAction
extends Action.BaseAction


var _damage: float
var _damage_type: BattleEvents.DamageType


## 构造函数
## @param damage: 反伤伤害值
## @param damage_type: 伤害类型（默认 PURE）
func _init(
	damage: float,
	damage_type: BattleEvents.DamageType = BattleEvents.DamageType.PURE
) -> void:
	super._init(HexBattleTargetSelectors.event_source())
	type = "reflect_damage"
	_damage = damage
	_damage_type = damage_type


func execute(ctx: ExecutionContext) -> ActionResult:
	var targets := get_targets(ctx)
	if targets.is_empty():
		print("  [ReflectDamageAction] 无攻击来源，跳过反伤")
		return ActionResult.create_success_result([], { "skipped": true })
	
	var attacker_id := targets[0]
	var owner_actor_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var battle: HexBattle = ctx.game_state_provider
	var alive_actor_ids := battle.get_alive_actor_ids()
	
	var owner_name := HexBattleGameStateUtils.get_actor_display_name(owner_actor_id, battle)
	var attacker_name := HexBattleGameStateUtils.get_actor_display_name(attacker_id, battle)
	var damage_type_str := BattleEvents._damage_type_to_string(_damage_type)
	print("  [ReflectDamageAction] %s 反伤 %s %.0f 点 %s 伤害" % [owner_name, attacker_name, _damage, damage_type_str])
	
	# ========== 应用伤害 + 死亡处理 ==========
	var event := BattleEvents.DamageEvent.create(
		attacker_id, _damage, _damage_type, owner_actor_id, false, true
	)
	var damage_result := HexBattleDamageUtils.apply_damage(
		event, alive_actor_ids, ctx, battle,
	)
	
	# ========== Post damage 广播 ==========
	HexBattleDamageUtils.broadcast_post_damage(
		damage_result.damage_event_dict, alive_actor_ids, battle,
	)
	
	return ActionResult.create_success_result(
		damage_result.all_events, { "damage": _damage, "target": attacker_id }
	)
