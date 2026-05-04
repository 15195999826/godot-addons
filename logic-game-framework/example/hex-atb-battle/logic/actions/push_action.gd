## PushAction - 击退 / 推开 Action
##
## ========== 设计原则 ==========
##
## 数据驱动的 forced displacement: 沿 caster→target 方向尝试推进 N 格,
## 沿途遇到 occupant / 地图边界则停下并按 CollisionProfile 结算碰撞伤害。
## 不是物理引擎: 只是数据结算表 (CollisionProfile 字段) + 一段 raycast。
##
## V1 默认 N=1, 但循环已支持 N>1。未来 wind_torrent / chain push 传更大 distance 即可。
##
## ========== 事件 ==========
##
## - ActorDisplacedEvent: 仅当 final_pos != original_pos 时 push (target 真的移动了)
## - PushBlockedEvent:    沿途撞到 edge / actor 时 push
##                        N=1 撞正前方: 只有 PushBlockedEvent
##                        N>1 移动后撞: ActorDisplacedEvent + PushBlockedEvent 都 push
##
## ========== 碰撞伤害 contract ==========
##
## - deterministic: 无随机暴击 (跟 DamageAction 的 randf() < 0.1 区别开)
## - 不走 PreDamageEvent: M1 不允许 modifier 介入 collision 伤害结算
##   (未来若 Expose 想加 collision 增伤, 再扩 DamageUtils 显式入口)
## - 走 HexBattleDamageUtils.apply_damage + broadcast_post_damage:
##   仍然有 ShieldComponent 吸收 / death / post-damage thorns 反伤
## - source_actor_id = caster (gameplay attribution, 非物理模拟):
##   * thorns 反给 caster
##   * kill credit 归 caster
##   * target 撞 blocker 时, blocker 受的 collision damage 也归 caster
##
## ========== 字段语义 (CollisionProfile, 视角 = "被撞物") ==========
##
## - blocker.damage_dealt_to_pusher       → target 受多少 (撞我的人受多少)
## - blocker.damage_taken_on_blocked_push → blocker 自己受多少
## - 撞 edge 时用 CollisionProfile.default_wall() 兜底, 仅 dealt_to_pusher 生效 (target 受 1)
##
## ========== Case 6 死亡跳过 ==========
##
## 若 PushAction 执行前 target 已经 is_dead (上一步 DamageAction 已击杀),
## 整个 Action 跳过 — 不产生 ActorDisplacedEvent / PushBlockedEvent / 碰撞伤害。
##
class_name HexBattlePushAction
extends Action.BaseAction


const KIND_KNOCKBACK := "knockback"
const BLOCKED_BY_EDGE := "edge"
const BLOCKED_BY_ACTOR := "actor"


## 击退距离 (格数). V1 在 KnockbackPunch 用 N=1。
var _distance: int

## 位移类型字符串, 写入 ActorDisplacedEvent.displacement_kind。
## 当前可选 KIND_KNOCKBACK; 未来 "pull" / "scatter" 等扩展。
var _displacement_kind: String


## @param target_selector: 被推目标 (用 current_target 选 ability 的 target)
## @param distance:        推开格数 (默认 1)
## @param displacement_kind: 写入 ActorDisplacedEvent 的语义标签 (默认 KIND_KNOCKBACK)
func _init(
	target_selector: TargetSelector,
	distance: int = 1,
	displacement_kind: String = KIND_KNOCKBACK
) -> void:
	super._init(target_selector)
	type = "push"
	_distance = distance
	_displacement_kind = displacement_kind


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var caster := battle.get_actor(caster_id)
	var targets := get_targets(ctx)
	if caster == null or targets.is_empty():
		return ActionResult.create_success_result([], { "skipped": true })

	var target_id := targets[0]
	var target := battle.get_actor(target_id)
	if target == null:
		return ActionResult.create_success_result([], { "skipped": true })

	# Case 6: base damage 已经击杀 target → 整段 push 跳过
	if target.is_dead():
		return ActionResult.create_success_result([], { "skipped": true })

	var caster_pos := caster.hex_position
	var target_pos := target.hex_position
	if not caster_pos.is_valid() or not target_pos.is_valid():
		return ActionResult.create_success_result([], { "skipped": true })

	var dir := caster_pos.direction_to_neighbor(target_pos)
	if dir < 0:
		push_warning("[PushAction] caster and target not adjacent: caster=%s target=%s" % [
			caster_pos, target_pos
		])
		return ActionResult.create_success_result([], { "skipped": true })

	# ========== Raycast 推进 ==========
	var original_pos := target_pos
	var final_pos := target_pos
	var blocked_by := ""
	var attempted_to := HexCoord.invalid()
	var blocker: HexBattleActor = null

	for _step in range(_distance):
		var next := final_pos.neighbor(dir)
		if not battle.grid.has_tile(next):
			blocked_by = BLOCKED_BY_EDGE
			attempted_to = next
			break
		var occupant := battle.grid.get_occupant(next) as HexBattleActor
		if occupant != null:
			blocked_by = BLOCKED_BY_ACTOR
			blocker = occupant
			attempted_to = next
			break
		final_pos = next

	var all_events: Array[Dictionary] = []
	var displaced := not final_pos.equals(original_pos)
	var actual_distance := original_pos.distance_to(final_pos)
	var collision_action_lock_bonus_ms := (
		HexBattleActionLockStatus.COLLISION_ACTION_LOCK_BONUS_MS
		if blocked_by != "" else 0.0
	)
	var action_lock_duration_ms := 0.0
	if displaced or blocked_by != "":
		action_lock_duration_ms = HexBattleActionLockStatus.compute_displacement_duration_ms(
			actual_distance,
			collision_action_lock_bonus_ms
		)

	# ========== 实际移动 + ActorDisplacedEvent ==========
	if displaced:
		var moved := battle.grid.move_occupant(original_pos, final_pos)
		if moved:
			target.hex_position = final_pos
			var displaced_event := BattleEvents.ActorDisplacedEvent.create(
				target_id,
				original_pos.to_dict(),
				final_pos.to_dict(),
				_displacement_kind,
				caster_id,
				actual_distance,
				action_lock_duration_ms,
				collision_action_lock_bonus_ms,
			)
			all_events.append(ctx.event_collector.push(displaced_event.to_dict()))
		else:
			push_warning("[PushAction] grid.move_occupant failed: %s -> %s" % [
				original_pos, final_pos
			])
			displaced = false
			if blocked_by == "":
				action_lock_duration_ms = 0.0

	# ========== 阻挡 + 碰撞伤害 ==========
	if blocked_by != "":
		var blocker_id := blocker.get_id() if blocker != null else ""
		var blocked_event := BattleEvents.PushBlockedEvent.create(
			target_id,
			final_pos.to_dict(),
			attempted_to.to_dict(),
			blocked_by,
			blocker_id,
			caster_id,
			actual_distance,
			action_lock_duration_ms,
			collision_action_lock_bonus_ms,
		)
		all_events.append(ctx.event_collector.push(blocked_event.to_dict()))

		# 碰撞伤害结算: 用 blocker 的 profile, 撞 edge 用 default_wall。
		# blocker.collision_profile 由 HexBattleActor 基类不变量保证非空。
		var blocker_profile := (
			blocker.collision_profile if blocker != null
			else CollisionProfile.default_wall()
		)

		# target 受 dealt_to_pusher (字段定义: 撞我的人受多少)
		var target_dmg := blocker_profile.damage_dealt_to_pusher
		if target_dmg > 0.0 and not target.is_dead():
			all_events.append_array(
				_push_collision_damage(target_id, target_dmg, caster_id, ctx, battle)
			)

		# blocker 受 taken_on_blocked_push (仅当撞的是 actor, edge 时 blocker == null)
		if blocker != null and not blocker.is_dead():
			var blocker_dmg := blocker_profile.damage_taken_on_blocked_push
			if blocker_dmg > 0.0:
				all_events.append_array(
					_push_collision_damage(blocker.get_id(), blocker_dmg, caster_id, ctx, battle)
				)

	if (displaced or blocked_by != "") and action_lock_duration_ms > 0.0 and not target.is_dead():
		_grant_displacement_action_lock(target, action_lock_duration_ms, caster_id, battle)

	return ActionResult.create_success_result(all_events, {
		"displaced": displaced,
		"blocked_by": blocked_by,
		"actual_distance": actual_distance,
		"action_lock_duration_ms": action_lock_duration_ms,
	})


func _grant_displacement_action_lock(
	target: HexBattleActor,
	duration_ms: float,
	source_caster_id: String,
	battle: HexWorldGameplayInstance
) -> void:
	if not (target is CharacterActor):
		return
	var character := target as CharacterActor
	var action_lock := Ability.new(
		HexBattleActionLockStatus.create_config(
			duration_ms,
			HexBattleActionLockStatus.REASON_DISPLACEMENT_STAGGER,
			HexBattleActionLockStatus.REASON_DISPLACEMENT_STAGGER
		),
		character.get_id(),
		source_caster_id
	)
	character.ability_set.grant_ability(action_lock, battle)


## inline collision damage helper.
## Contract: deterministic, no crit, no PreDamage modifier.
## 仍走 HexBattleDamageUtils.apply_damage / broadcast_post_damage,
## 因此 ShieldComponent / death / post-damage thorns 都正常生效。
##
## alive_actor_ids 在每次调用时重新拉取: 第一次 broadcast 可能击杀 target,
## 第二次 (blocker damage) 不能用 stale list, 否则 thorns / post-death 监听器漏触发。
func _push_collision_damage(
	target_id: String,
	amount: float,
	source_caster_id: String,
	ctx: ExecutionContext,
	battle: HexWorldGameplayInstance,
) -> Array[Dictionary]:
	var alive_actor_ids := battle.get_alive_actor_ids()
	var damage_event := BattleEvents.DamageEvent.create(
		target_id,
		amount,
		BattleEvents.DamageType.PHYSICAL,
		source_caster_id,
		false,  # is_critical
		false   # is_reflected
	)
	var damage_result := HexBattleDamageUtils.apply_damage(
		damage_event, alive_actor_ids, ctx, battle
	)
	HexBattleDamageUtils.broadcast_post_damage(
		damage_result.damage_event_dict, alive_actor_ids, battle
	)
	return damage_result.all_events
