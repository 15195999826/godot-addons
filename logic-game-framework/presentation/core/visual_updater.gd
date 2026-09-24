## VisualUpdater - 更新器（记账规则）
##
## 三类输入三个入口：
## - apply_actions(state, active)：卡片 × 进度 → 按 kind 查 handler 改账本
## - apply_event(state, event)：事件直改（actor_spawned / actor_destroyed / max_hp），必须在翻译前落账本
## - tick_time(state, delta_ms)：时间驱动（到期效果清理 + visual_hp 追赶）
##
## handler 表 kind -> Callable，内置 11 种默认注册；项目私有卡片 register_handler(kind, callable) 加进来，
## 不改框架。handler 签名：static func (state: VisualState, action: VisualAction, progress: float,
## action_id: String) -> void。除 handler 表外无状态。
class_name VisualUpdater
extends RefCounted


## kind -> Callable
var _handlers: Dictionary = {}


func _init() -> void:
	register_handler(VisualAction.KIND_MOVE, apply_move)
	register_handler(VisualAction.KIND_HP_DELTA, apply_hp_delta)
	register_handler(VisualAction.KIND_FLOATING_TEXT, apply_floating_text)
	register_handler(VisualAction.KIND_PROCEDURAL_VFX, apply_procedural_vfx)
	register_handler(VisualAction.KIND_DEATH, apply_death)
	register_handler(VisualAction.KIND_ATTACK_VFX, apply_attack_vfx)
	register_handler(VisualAction.KIND_PROJECTILE, apply_projectile)
	register_handler(VisualAction.KIND_BUFF_STATE, apply_buff_state)
	register_handler(VisualAction.KIND_SHIELD_STATE, apply_shield_state)
	register_handler(VisualAction.KIND_BUMP, apply_bump)
	register_handler(VisualAction.KIND_FACING_STATE, apply_facing_state)


# ========== handler 表 ==========

## 登记 / 覆盖某种卡片的记账函数
func register_handler(kind: StringName, handler: Callable) -> void:
	_handlers[kind] = handler


func has_handler(kind: StringName) -> bool:
	return _handlers.has(kind)


# ========== 卡片 × 进度 ==========

## 把活跃卡片应用到账本；延迟中的跳过
func apply_actions(state: VisualState, active_actions: Array[ActionStepper.ActiveAction]) -> void:
	for active_action: ActionStepper.ActiveAction in active_actions:
		if active_action.is_delaying:
			continue
		var action := active_action.action
		var handler: Callable = _handlers.get(action.kind, Callable())
		Log.assert_crash(handler.is_valid(), "VisualUpdater",
			"卡片 kind '%s' 没有登记记账 handler（项目私有种类要 register_handler）" % action.kind)
		if not handler.is_valid():
			continue
		handler.call(state, action, active_action.progress, active_action.id)


# ========== 事件直改 ==========

## 翻译员只负责把事件翻成卡片；actor_spawned / actor_destroyed / max_hp 属于账本 lifecycle，
## 必须先落账本，翻译员才能用最新的只读视图。
func apply_event(state: VisualState, event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	match kind:
		GameEvent.ACTOR_SPAWNED_EVENT:
			_apply_actor_spawned_event(state, event)
		GameEvent.ACTOR_DESTROYED_EVENT:
			_apply_actor_destroyed_event(state, event)
		GameEvent.ATTRIBUTE_CHANGED_EVENT:
			_apply_attribute_changed_event(state, event)


static func _apply_actor_spawned_event(state: VisualState, event: Dictionary) -> void:
	var actor_data_variant: Variant = event.get("actor", {})
	if not (actor_data_variant is Dictionary):
		return
	var actor_data := actor_data_variant as Dictionary
	if actor_data.is_empty():
		return
	var actor_init := PlaybackData.ActorInitData.from_dict(actor_data)
	if actor_init.id.is_empty():
		actor_init.id = str(event.get("actor_id", ""))
	state.spawn_actor(actor_init)


## 销毁只改状态不出账：死亡 sticky + hp 归零，当场广播
static func _apply_actor_destroyed_event(state: VisualState, event: Dictionary) -> void:
	var actor_id := str(event.get("actor_id", ""))
	if actor_id.is_empty():
		return
	var actor := state.get_actor(actor_id)
	if actor == null:
		return
	state.set_actor_alive(actor, false)
	actor.visual_hp = 0.0
	actor.target_hp = 0.0
	state.emit_actor_state_changed(actor_id)


## 上限夹到 ≥ 0，visual / target 夹到新上限（回升不回血）；不判死；只标脏
static func _apply_attribute_changed_event(state: VisualState, event: Dictionary) -> void:
	var attribute := str(event.get("attribute", ""))
	if attribute != "max_hp":
		return
	var actor_id := str(event.get("actor_id", ""))
	if actor_id.is_empty():
		return
	var actor := state.get_actor(actor_id)
	if actor == null:
		return
	var new_max_hp := float(event.get("new_value", actor.max_hp))
	actor.max_hp = maxf(0.0, new_max_hp)
	actor.visual_hp = clampf(actor.visual_hp, 0.0, actor.max_hp)
	actor.target_hp = clampf(actor.target_hp, 0.0, actor.max_hp)
	state.mark_dirty(actor_id)


# ========== 时间驱动 ==========

## 每 tick 调用：到期的一次性 / 程序化效果出账，没有活跃程序化效果的 actor 闪白 / 染色归零、震屏归零，
## 再把所有 actor 的 visual_hp 朝 target_hp 收敛
func tick_time(state: VisualState, delta_ms: float) -> void:
	_expire(state)
	_lerp_hp(state, delta_ms)


static func _expire(state: VisualState) -> void:
	var now_ms := state.get_time_ms()
	state.expire_effects(now_ms)
	state.expire_procedural_effects(now_ms)

	var effects := state.get_procedural_effects()
	var has_active_shake := effects.any(func(e: VisualEffectPayload.ProceduralEffect) -> bool:
		return e.effect == VisualProceduralVfxAction.EffectType.SHAKE
	)
	if not has_active_shake:
		state.set_screen_shake(Vector2.ZERO)

	for actor_id: String in state.get_actor_ids():
		var actor := state.get_actor(actor_id)
		var has_active_flash := effects.any(func(e: VisualEffectPayload.ProceduralEffect) -> bool:
			return e.effect == VisualProceduralVfxAction.EffectType.HIT_FLASH and e.actor_id == actor_id
		)
		if not has_active_flash:
			actor.flash_progress = 0.0

		var has_active_tint := effects.any(func(e: VisualEffectPayload.ProceduralEffect) -> bool:
			return e.effect == VisualProceduralVfxAction.EffectType.COLOR_TINT and e.actor_id == actor_id
		)
		if not has_active_tint:
			actor.tint_color = Color.WHITE


## 指数衰减模型:进度 = 1 - exp(-rate * dt),rate 见 AnimationConfig.hp_lerp_rate(单位 1/秒)。
## 已贴近 target 时直接 snap 避免无限 lerp；收敛后不再标脏。
static func _lerp_hp(state: VisualState, delta_ms: float) -> void:
	var dt: float = delta_ms / 1000.0
	var rate: float = state.get_animation_config().hp_lerp_rate
	var t: float = 1.0 - exp(-rate * dt) if rate > 0.0 else 1.0
	for actor_id: String in state.get_actor_ids():
		var actor := state.get_actor(actor_id)
		if is_equal_approx(actor.visual_hp, actor.target_hp):
			continue
		var diff := actor.target_hp - actor.visual_hp
		if absf(diff) < 0.5:
			actor.visual_hp = actor.target_hp
		else:
			actor.visual_hp += diff * t
		state.mark_dirty(actor_id)


# ========== 内置 handler ==========

## 移动：中途只改在飞插值；progress 1 才落 actor.position 并当场广播
static func apply_move(state: VisualState, action: VisualAction, progress: float, _action_id: String) -> void:
	var move := action as VisualMoveAction
	state.set_interpolated_position(move.actor_id, move.get_interpolated_position(progress))
	if progress >= 1.0:
		var actor := state.get_actor(move.actor_id)
		if actor != null:
			actor.position = move.to_position
			state.emit_actor_state_changed(move.actor_id)


## hp delta(瞬时):把伤害 / 治疗的 delta 立刻累到 target_hp,visual_hp 由 tick_time 每帧朝它收敛。
## actor_died 在 target_hp 落到 ≤0 那一刻 emit(transition-only),不等 visual_hp lerp 完。
##
## 多次伤害的连续性靠「单一 target_hp + 持续 lerp」保证 — 不需要卡片互斥或 from-snapshot,
## 新 delta 只是把 target_hp 进一步拉低,visual_hp 始终从当前位置追赶。
static func apply_hp_delta(state: VisualState, action: VisualAction, _progress: float, _action_id: String) -> void:
	var hp_delta := action as VisualHpDeltaAction
	var actor := state.get_actor(hp_delta.actor_id)
	if actor == null:
		print("[Presentation:VisualUpdater] ⚠️ hp_delta 找不到 actor: %s" % hp_delta.actor_id)
		return
	actor.target_hp = clampf(actor.target_hp + hp_delta.delta, 0.0, actor.max_hp)
	# 死亡 sticky:只允许 alive→dead transition。dead→alive 复活语义未支持
	# (见 VisualState.set_actor_alive 注释), 否则同帧 death + heal 会把 view 翻回 alive,
	# 与逻辑层 is_dead sticky 漂出 view-logic mismatch。
	if actor.is_alive and actor.target_hp <= 0.0:
		state.set_actor_alive(actor, false)
	state.mark_dirty(hp_delta.actor_id)


## 飘字：按卡片 id 只入账一次；寿命到期由账本静默忘记（view 自管节点）
static func apply_floating_text(state: VisualState, action: VisualAction, _progress: float, action_id: String) -> void:
	if state.has_effect(VisualAction.KIND_FLOATING_TEXT, action_id):
		return
	var text := action as VisualFloatingTextAction

	print("[Presentation:VisualUpdater] 飘字: actor=%s text='%s' pos=%s" % [
		text.actor_id, text.text, text.position
	])

	var payload := VisualEffectPayload.FloatingText.new()
	payload.id = action_id
	payload.actor_id = text.actor_id
	payload.text = text.text
	payload.color = text.color
	payload.position = text.position
	payload.duration = text.duration
	payload.style = text.style
	state.spawn_effect(VisualAction.KIND_FLOATING_TEXT, payload)


## 程序化特效：闪白 / 染色写到 actor，震屏写到账本；寿命簿按卡片 id 只记一次
static func apply_procedural_vfx(state: VisualState, action: VisualAction, progress: float, action_id: String) -> void:
	var vfx := action as VisualProceduralVfxAction
	match vfx.effect:
		VisualProceduralVfxAction.EffectType.HIT_FLASH:
			if not vfx.actor_id.is_empty():
				var actor := state.get_actor(vfx.actor_id)
				if actor != null:
					actor.flash_progress = vfx.get_flash_intensity(progress)
					state.mark_dirty(vfx.actor_id)

		VisualProceduralVfxAction.EffectType.SHAKE:
			state.set_screen_shake(vfx.get_shake_offset(progress))

		VisualProceduralVfxAction.EffectType.COLOR_TINT:
			if not vfx.actor_id.is_empty():
				var actor := state.get_actor(vfx.actor_id)
				if actor != null:
					actor.tint_color = vfx.tint_color if progress < 1.0 else Color.WHITE
					state.mark_dirty(vfx.actor_id)

	if state.has_procedural_effect(action_id):
		return
	var effect := VisualEffectPayload.ProceduralEffect.new()
	effect.id = action_id
	effect.effect = vfx.effect
	effect.actor_id = vfx.actor_id
	effect.duration = vfx.duration
	effect.intensity = vfx.intensity
	effect.color = vfx.tint_color
	state.add_procedural_effect(effect)


## 死亡：立即 is_alive=false、hp 归零、death_progress 跟进度，当场广播
static func apply_death(state: VisualState, action: VisualAction, progress: float, _action_id: String) -> void:
	var death := action as VisualDeathAction
	var actor := state.get_actor(death.actor_id)
	if actor == null:
		print("[Presentation:VisualUpdater] ⚠️ death 找不到 actor: %s" % death.actor_id)
		return

	state.set_actor_alive(actor, false)
	actor.visual_hp = 0.0
	actor.target_hp = 0.0
	actor.death_progress = progress

	if progress >= 1.0:
		print("[Presentation:VisualUpdater] 死亡动画完成: actor=%s" % death.actor_id)

	state.emit_actor_state_changed(death.actor_id)


## 攻击特效：首次入账，每次 apply 更新缩放 / 透明度，完成移除
static func apply_attack_vfx(state: VisualState, action: VisualAction, progress: float, action_id: String) -> void:
	var vfx := action as VisualAttackVfxAction
	if not state.has_effect(VisualAction.KIND_ATTACK_VFX, action_id):
		var payload := VisualEffectPayload.AttackVfx.new()
		payload.id = action_id
		payload.source_actor_id = vfx.source_actor_id
		payload.target_actor_id = vfx.target_actor_id
		payload.source_position = vfx.source_position
		payload.target_position = vfx.target_position
		payload.vfx_type = vfx.vfx_type
		payload.vfx_color = vfx.vfx_color
		payload.is_critical = vfx.is_critical
		payload.duration = vfx.duration
		state.spawn_effect(VisualAction.KIND_ATTACK_VFX, payload)

	var record := state.get_effect(VisualAction.KIND_ATTACK_VFX, action_id) as VisualEffectPayload.AttackVfx
	record.scale_factor = vfx.get_vfx_scale(progress)
	record.alpha = vfx.get_vfx_alpha(progress)
	state.update_effect(VisualAction.KIND_ATTACK_VFX, action_id, progress)

	if progress >= 1.0:
		state.remove_effect(VisualAction.KIND_ATTACK_VFX, action_id)


## 投射物：首次入账，每次 apply 更新逻辑平面位置，完成移除
static func apply_projectile(state: VisualState, action: VisualAction, progress: float, action_id: String) -> void:
	var projectile := action as VisualProjectileAction
	if not state.has_effect(VisualAction.KIND_PROJECTILE, action_id):
		var payload := VisualEffectPayload.Projectile.new()
		payload.id = action_id
		payload.projectile_id = projectile.projectile_id
		payload.source_actor_id = projectile.source_actor_id
		payload.target_actor_id = projectile.target_actor_id
		payload.start_position = projectile.start_position
		payload.target_position = projectile.target_position
		payload.projectile_type = projectile.projectile_type
		payload.projectile_color = projectile.projectile_color
		payload.projectile_size = projectile.projectile_size
		payload.position = projectile.start_position
		payload.duration = projectile.duration
		state.spawn_effect(VisualAction.KIND_PROJECTILE, payload)

	var record := state.get_effect(VisualAction.KIND_PROJECTILE, action_id) as VisualEffectPayload.Projectile
	record.position = projectile.get_current_position(progress)
	state.update_effect(VisualAction.KIND_PROJECTILE, action_id, progress)

	if progress >= 1.0:
		state.remove_effect(VisualAction.KIND_PROJECTILE, action_id)


## buff 状态变化(瞬时):对 actor.buffs 数组做 ADD/UPDATE/REMOVE。
##
## 顺序契约:
##   - ADD: 若 buff_id 已存在则覆盖(防御性,正常路径不会出现);否则 append 到尾部,
##          顺序 = "首次 ADD 顺序",稳定不重排。
##   - UPDATE: 找到 buff_id 即覆盖 primary;找不到则忽略(常见于白名单不命中时)。
##   - REMOVE: 找到 buff_id 即移除;找不到 noop。
static func apply_buff_state(state: VisualState, action: VisualAction, _progress: float, _action_id: String) -> void:
	var buff := action as VisualBuffStateAction
	var actor := state.get_actor(buff.actor_id)
	if actor == null:
		return
	var idx := -1
	for i in range(actor.buffs.size()):
		if actor.buffs[i].id == buff.buff_id:
			idx = i
			break
	match buff.op:
		VisualBuffStateAction.Op.ADD:
			if buff.summary == null:
				return
			if idx >= 0:
				actor.buffs[idx] = buff.summary
			else:
				actor.buffs.append(buff.summary)
			state.mark_dirty(buff.actor_id)
		VisualBuffStateAction.Op.UPDATE:
			if idx < 0 or buff.summary == null:
				return
			# noop guard:primary 没变就不标脏,避免下游 actor_state_changed → view 整条链空跑。
			if is_equal_approx(actor.buffs[idx].primary, buff.summary.primary):
				return
			actor.buffs[idx].primary = buff.summary.primary
			state.mark_dirty(buff.actor_id)
		VisualBuffStateAction.Op.REMOVE:
			if idx < 0:
				return
			actor.buffs.remove_at(idx)
			state.mark_dirty(buff.actor_id)


## 护盾状态变化(瞬时):对 actor.shields 数组做 ADD/UPDATE/REMOVE。
##
## 与 apply_buff_state 对偶,语义完全一致(ADD 防御性覆盖、UPDATE 无变化时 noop guard、REMOVE 找不到 noop)。
##
## UPDATE 比较的是 current,因为吸收伤害时只有 current 变,capacity 是 ADD 时
## 一次定下不再改。这样 noop guard 才能挡住"伤害事件但当前 shield 没参与
## 消耗"那条 record(remaining 等于上一次 current)的空跑。
static func apply_shield_state(state: VisualState, action: VisualAction, _progress: float, _action_id: String) -> void:
	var shield := action as VisualShieldStateAction
	var actor := state.get_actor(shield.actor_id)
	if actor == null:
		return
	var idx := -1
	for i in range(actor.shields.size()):
		if actor.shields[i].id == shield.shield_id:
			idx = i
			break
	match shield.op:
		VisualShieldStateAction.Op.ADD:
			if shield.summary == null:
				return
			if idx >= 0:
				actor.shields[idx] = shield.summary
			else:
				actor.shields.append(shield.summary)
			state.mark_dirty(shield.actor_id)
		VisualShieldStateAction.Op.UPDATE:
			if idx < 0 or shield.summary == null:
				return
			if is_equal_approx(actor.shields[idx].current, shield.summary.current):
				return
			actor.shields[idx].current = shield.summary.current
			state.mark_dirty(shield.actor_id)
		VisualShieldStateAction.Op.REMOVE:
			if idx < 0:
				return
			actor.shields.remove_at(idx)
			state.mark_dirty(shield.actor_id)


## bump(撞墙 / 撞单位临时位移弹回)。view 层从 actor.bump_offset / bump_squish 读取,
## 偏移投影后叠加在位置上、挤压落到 mesh scale,逻辑位置不变。progress=1 时 snap 回零位,
## 避免下一段动画继承残留偏移。
static func apply_bump(state: VisualState, action: VisualAction, progress: float, _action_id: String) -> void:
	var bump := action as VisualBumpAction
	var actor := state.get_actor(bump.actor_id)
	if actor == null:
		return
	if progress >= 1.0:
		actor.bump_offset = Vector2.ZERO
		actor.bump_squish = Vector2.ONE
	else:
		actor.bump_offset = bump.get_offset(progress)
		actor.bump_squish = bump.get_squish(progress)
	state.mark_dirty(bump.actor_id)


## 朝向(瞬时, 无 lerp / turn speed): 立即把 new_direction 写入 actor.facing_direction, 只标脏。
## 未知 actor 忽略。
static func apply_facing_state(state: VisualState, action: VisualAction, _progress: float, _action_id: String) -> void:
	var facing := action as VisualFacingStateAction
	var actor := state.get_actor(facing.actor_id)
	if actor == null:
		return
	actor.facing_direction = facing.new_direction
	state.mark_dirty(facing.actor_id)
