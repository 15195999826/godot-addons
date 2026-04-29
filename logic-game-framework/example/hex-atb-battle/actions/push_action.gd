## PushAction - 击退 / 推开 Action
##
## ========== 设计原则 ==========
##
## 数据驱动的 forced displacement: 沿 caster→target 方向尝试推进 N 格,
## 沿途遇到 occupant / 地图边界则停下并按 CollisionProfile 结算碰撞伤害。
## 不是物理引擎: 只是数据结算表 (CollisionProfile 字段) + 一段 raycast。
##
## ========== 推进算法 (N>=1) ==========
##
## final_pos = target.hex_position
## for step in 1..N:
##   next = final_pos.neighbor(dir)
##   if !grid.has_tile(next):     blocked_by = "edge"; break
##   if grid.get_occupant(next):   blocked_by = "actor"; blocker = occ; break
##   final_pos = next             ← 这一步空, 推进
##
## V1 默认 N=1, 但循环已支持 N>1。未来 wind_torrent / chain push 传更大 distance 即可。
##
## ========== 事件 ==========
##
## - ActorDisplacedEvent: 仅当 final_pos != original_pos 时 push (target 真的移动了)
## - PushBlockedEvent:    仅当 blocked_by != "none" 时 push (含撞 edge / 撞 actor)
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


## 击退距离 (格数). V1 在 KnockbackPunch 用 N=1。
var _distance: int

## 位移类型字符串, 写入 ActorDisplacedEvent.displacement_kind。
## 当前可选 "knockback"; 未来 "pull" / "scatter" 等扩展。
var _displacement_kind: String


## @param target_selector: 被推目标 (用 current_target 选 ability 的 target)
## @param distance:        推开格数 (默认 1)
## @param displacement_kind: 写入 ActorDisplacedEvent 的语义标签 (默认 "knockback")
func _init(
	target_selector: TargetSelector,
	distance: int = 1,
	displacement_kind: String = "knockback"
) -> void:
	super._init(target_selector)
	type = "push"
	_distance = distance
	_displacement_kind = displacement_kind


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var caster := battle.get_actor(caster_id)
	if caster == null:
		return ActionResult.create_success_result([], { "skipped": "no caster" })

	var targets := get_targets(ctx)
	if targets.is_empty():
		return ActionResult.create_success_result([], { "skipped": "no target" })

	var target_id := targets[0]
	var target := battle.get_actor(target_id)
	if target == null:
		return ActionResult.create_success_result([], { "skipped": "target not found" })

	# Case 6: base damage 已经击杀 target → 整段 push 跳过
	if target.is_dead():
		return ActionResult.create_success_result([], { "skipped": "target dead" })

	var caster_pos := caster.hex_position
	var target_pos := target.hex_position
	if not caster_pos.is_valid() or not target_pos.is_valid():
		return ActionResult.create_success_result([], { "skipped": "invalid position" })

	var dir := caster_pos.direction_to_neighbor(target_pos)
	if dir < 0:
		push_warning("[PushAction] caster and target not adjacent: caster=%s target=%s" % [
			caster_pos, target_pos
		])
		return ActionResult.create_success_result([], { "skipped": "not adjacent" })

	# ========== Raycast 推进 ==========
	var original_pos := target_pos
	var final_pos := target_pos
	var blocked_by := "none"
	var blocker: HexBattleActor = null

	for _step in range(_distance):
		var next := final_pos.neighbor(dir)
		if not battle.grid.has_tile(next):
			blocked_by = "edge"
			break
		var occupant_var: Variant = battle.grid.get_occupant(next)
		if occupant_var != null:
			blocked_by = "actor"
			if occupant_var is HexBattleActor:
				blocker = occupant_var as HexBattleActor
			break
		final_pos = next

	var all_events: Array[Dictionary] = []

	# ========== 实际移动 + ActorDisplacedEvent ==========
	if not final_pos.equals(original_pos):
		var moved := battle.grid.move_occupant(original_pos, final_pos)
		if moved:
			target.hex_position = final_pos.duplicate()
			var displaced_event := BattleEvents.ActorDisplacedEvent.create(
				target_id,
				original_pos.to_dict(),
				final_pos.to_dict(),
				_displacement_kind,
				caster_id,
			)
			all_events.append(ctx.event_collector.push(displaced_event.to_dict()))
		else:
			push_warning("[PushAction] grid.move_occupant failed: %s -> %s" % [
				original_pos, final_pos
			])

	# ========== 阻挡 + 碰撞伤害 ==========
	if blocked_by != "none":
		# 推算被挡的目标格 (即下一个从 final_pos 出发的格)
		var attempted_to := final_pos.neighbor(dir)
		var blocker_id := blocker.get_id() if blocker != null else ""
		var blocked_event := BattleEvents.PushBlockedEvent.create(
			target_id,
			final_pos.to_dict(),
			attempted_to.to_dict(),
			blocked_by,
			blocker_id,
			caster_id,
		)
		all_events.append(ctx.event_collector.push(blocked_event.to_dict()))

		# 碰撞伤害结算: 用 blocker 的 profile, 撞 edge 用 default_wall。
		var alive_actor_ids := battle.get_alive_actor_ids()
		var blocker_profile: CollisionProfile = (
			blocker.collision_profile
			if blocker != null and blocker.collision_profile != null
			else CollisionProfile.default_wall()
		)

		# target 受 dealt_to_pusher (字段定义: 撞我的人受多少)
		var target_dmg := blocker_profile.damage_dealt_to_pusher
		if target_dmg > 0.0 and not target.is_dead():
			all_events.append_array(
				_push_collision_damage(target_id, target_dmg, caster_id, ctx, battle, alive_actor_ids)
			)

		# blocker 受 taken_on_blocked_push (仅当撞的是 actor, edge 不结算)
		if blocker != null and not blocker.is_dead():
			var blocker_dmg := blocker_profile.damage_taken_on_blocked_push
			if blocker_dmg > 0.0:
				all_events.append_array(
					_push_collision_damage(
						blocker.get_id(), blocker_dmg, caster_id, ctx, battle, alive_actor_ids
					)
				)

	return ActionResult.create_success_result(all_events, {
		"displaced": not final_pos.equals(original_pos),
		"blocked_by": blocked_by,
	})


## inline collision damage helper.
## Contract: deterministic, no crit, no PreDamage modifier.
## 仍走 HexBattleDamageUtils.apply_damage / broadcast_post_damage,
## 因此 ShieldComponent / death / post-damage thorns 都正常生效。
func _push_collision_damage(
	target_id: String,
	amount: float,
	source_caster_id: String,
	ctx: ExecutionContext,
	battle: HexWorldGameplayInstance,
	alive_actor_ids: Array[String]
) -> Array[Dictionary]:
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
