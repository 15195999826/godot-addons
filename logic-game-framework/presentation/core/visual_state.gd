## VisualState - 账本
##
## 表演层的当前状态：每个进入过表演的逻辑 actor 一条 ActorVisualState、移动中的在飞插值、
## 一次性效果（飘字 / 攻击特效 / 投射物 / 项目私有种类）、程序化效果与震屏、账本时间。
## 台面两种来源：录像回放 initialize_from_replay + 事件直改 spawn_actor；live 场景没有录像，
## 走 seed_actor / despawn_actor / set_actor_position 直接操作账本。
##
## 职责分离：
## - ActionStepper 管"时序"（卡片走到什么进度）
## - VisualUpdater 管"记账规则"（某张卡片在某进度该改账本哪一格）
## - VisualState 只持数据、提供记账原语、发信号；不认识任何卡片种类
##
## 位置只讲逻辑平面坐标（Vector2）：账本 / 卡片 / 信号 payload 里没有像素与 3D，
## 棋盘几何与投影归项目 view 层。
class_name VisualState
extends RefCounted


# ========== 信号 ==========

## 角色状态变化信号
signal actor_state_changed(actor_id: String, state: ActorVisualState)

## 中途入账（录像里的 actor_spawned 事件 / live 的 seed）时创建角色状态
signal actor_spawned(actor_id: String, state: ActorVisualState)

## 角色死亡信号（transition-only：alive 真正 true→false 那一刻发一次）
signal actor_died(actor_id: String)

## 角色出账（live 场景 despawn；录像回放里的 actor_destroyed 只改状态不出账）
signal actor_despawned(actor_id: String)

## 一次性效果入账（kind = 效果种类；内置种类的 payload 见 VisualEffectPayload，项目私有种类自定义）
signal effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect)

## 一次性效果随进度更新（payload 是账本里那条记录，当前值已写入）
signal effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect)

## 一次性效果显式移除（由 handler 在完成时调 remove_effect；到期静默忘记的不发）
signal effect_removed(kind: StringName, effect_id: String)


# ========== 内部状态 ==========

## Actor 状态 Map（actor_id -> ActorVisualState）
var _actors: Dictionary = {}

## 插值位置 Map（actor_id -> Vector2）用于移动动画
var _interpolated_positions: Dictionary = {}

## 一次性效果簿：kind -> {effect_id -> VisualEffectPayload.Effect}
var _effects: Dictionary = {}

## 活跃的程序化特效（闪白 / 震屏 / 染色的寿命簿）
var _procedural_effects: Array[VisualEffectPayload.ProceduralEffect] = []

## 震屏状态
var _screen_shake: VisualEffectPayload.ScreenShake = VisualEffectPayload.ScreenShake.new()

## 动画配置
var _animation_config: AnimationConfig

## 账本时间（毫秒）
var _time_ms: int = 0

## 脏标记 Map（actor_id -> bool）用于批量触发信号
var _dirty_actors: Dictionary = {}


# ========== 构造函数 ==========

func _init(
	animation_config: AnimationConfig = null
) -> void:
	_animation_config = animation_config if animation_config != null else AnimationConfig.create_default()


# ========== 台面 ==========

## 从录像的开战台面重建账本；建完对每个 actor 广播一次 actor_state_changed
func initialize_from_replay(record: PlaybackData.BattleRecord) -> void:
	_actors.clear()
	_interpolated_positions.clear()
	_effects.clear()
	_procedural_effects.clear()
	_screen_shake = VisualEffectPayload.ScreenShake.new()
	_dirty_actors.clear()

	Log.assert_crash(record.world_snapshot != null, "VisualState",
		"录像缺 world_snapshot —— 无法重建开战台面")

	for actor_init: PlaybackData.ActorInitData in record.world_snapshot.actors:
		_add_actor(actor_init)

	for actor_id in _actors.keys():
		actor_state_changed.emit(actor_id, _actors[actor_id])


## 重置到录像的开战台面（账本时间归零）
func reset_to(record: PlaybackData.BattleRecord) -> void:
	_time_ms = 0
	initialize_from_replay(record)


## 中途入账一个 actor（录像里的 actor_spawned 事件）：入账并广播 actor_spawned + actor_state_changed。
## 空 id / 已在账上返回 null，不广播。
func spawn_actor(actor_init: PlaybackData.ActorInitData) -> ActorVisualState:
	if actor_init.id.is_empty() or _actors.has(actor_init.id):
		return null
	var actor := _add_actor(actor_init)
	if actor == null:
		return null
	actor_spawned.emit(actor.id, actor)
	actor_state_changed.emit(actor.id, actor)
	return actor


## 从录像 ActorInitData 建一条账（不广播）；空 id 跳过
func _add_actor(actor_init: PlaybackData.ActorInitData) -> ActorVisualState:
	if actor_init.id.is_empty():
		return null

	var position := _parse_position(actor_init)

	var actor_state := ActorVisualState.new()
	actor_state.id = actor_init.id
	actor_state.type = actor_init.type
	actor_state.config_id = actor_init.config_id
	actor_state.display_name = actor_init.display_name
	actor_state.team = actor_init.team
	actor_state.position = position
	actor_state.visual_hp = actor_init.attributes.get("hp", 100.0) as float
	actor_state.target_hp = actor_state.visual_hp
	actor_state.max_hp = actor_init.attributes.get("max_hp", 100.0) as float
	actor_state.is_alive = true
	actor_state.flash_progress = 0.0
	actor_state.tint_color = Color.WHITE
	# 朝向从 init data 重建；没有这个属性的 actor 默认 0，显示与否由项目 view 自查 actor type
	actor_state.facing_direction = int(actor_init.attributes.get("facing_direction", 0))

	_actors[actor_init.id] = actor_state
	_interpolated_positions[actor_init.id] = position
	return actor_state


## 录像 position 数组 → 逻辑平面坐标：默认取前两分量（hex 录像是 [q, r, 0]，连续世界是 [x, y, ...]）。
## 录像格式与逻辑坐标不是这个关系的项目覆盖这一处。
func _parse_position(actor_init: PlaybackData.ActorInitData) -> Vector2:
	var position_arr: Array = actor_init.position  # 元素可能是 int/float，保持无类型
	var x := float(position_arr[0]) if position_arr.size() > 0 else 0.0
	var y := float(position_arr[1]) if position_arr.size() > 1 else 0.0
	return Vector2(x, y)


# ========== 读 ==========

## 账本上的活对象（记账用；未知 actor 返回 null）。只读快照走 get_actors_snapshot
func get_actor(actor_id: String) -> ActorVisualState:
	return _actors.get(actor_id)


func has_actor(actor_id: String) -> bool:
	return _actors.has(actor_id)


## 账本上全部 actor id（新数组，可边遍历边改账）
func get_actor_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _actors.keys():
		ids.append(key as String)
	return ids


## 获取 Actor 状态的深拷贝 Map（actor_id -> ActorVisualState）
func get_actors_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for actor_id: String in _actors.keys():
		var actor: ActorVisualState = _actors[actor_id]
		snapshot[actor_id] = actor.duplicate()
	return snapshot


## 创建只读视图（翻译员用）
func as_query() -> VisualStateQuery:
	return VisualStateQuery.new(
		_actors,
		_interpolated_positions,
		_animation_config
	)


## 获取角色当前逻辑平面坐标（含移动中的在飞插值）；view 层投影后定位节点。
## 未知 actor 返回 ZERO。
func get_actor_position(actor_id: String) -> Vector2:
	if _interpolated_positions.has(actor_id):
		return _interpolated_positions[actor_id]
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor == null:
		return Vector2.ZERO
	return actor.position


func get_animation_config() -> AnimationConfig:
	return _animation_config


## 获取震屏偏移
func get_screen_shake_offset() -> Vector2:
	return _screen_shake.to_vector2()


## 账本时间（毫秒）
func get_time_ms() -> int:
	return _time_ms


## 推进账本时间
func advance_time(delta_ms: int) -> void:
	_time_ms += delta_ms


# ========== 记账原语（规则在 VisualUpdater） ==========

## 写移动中的在飞插值位置
func set_interpolated_position(actor_id: String, position: Vector2) -> void:
	_interpolated_positions[actor_id] = position


## 标脏：flush_dirty_actors 时广播一次 actor_state_changed
func mark_dirty(actor_id: String) -> void:
	_dirty_actors[actor_id] = true


## 当场广播 actor_state_changed（不等 flush）；未知 actor 忽略
func emit_actor_state_changed(actor_id: String) -> void:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor != null:
		actor_state_changed.emit(actor_id, actor)


## 收口所有 is_alive 写入,在 alive 真正 true→false 那一刻 emit 一次 actor_died。
## 重复设 false / 设回 true 不会再触发 — actor_died 是 transition-only event。
## 战斗内复活语义未来落地时再加 actor_revived(同样 transition-only)。
func set_actor_alive(actor: ActorVisualState, alive: bool) -> void:
	var was_alive := actor.is_alive
	actor.is_alive = alive
	if was_alive and not alive:
		actor_died.emit(actor.id)


## 批量触发脏标记的 Actor 状态变化信号
func flush_dirty_actors() -> void:
	for actor_id: String in _dirty_actors.keys():
		if _actors.has(actor_id):
			actor_state_changed.emit(actor_id, _actors[actor_id])
	_dirty_actors.clear()


# ========== 一次性效果 ==========

func has_effect(kind: StringName, effect_id: String) -> bool:
	var by_id: Dictionary = _effects.get(kind, {})
	return by_id.has(effect_id)


## 账本里那条效果记录（未知返回 null）
func get_effect(kind: StringName, effect_id: String) -> VisualEffectPayload.Effect:
	var by_id: Dictionary = _effects.get(kind, {})
	return by_id.get(effect_id)


## 入账并广播 effect_spawned；id 取 payload.id，入账时间盖到 payload.start_time
func spawn_effect(kind: StringName, payload: VisualEffectPayload.Effect) -> void:
	payload.start_time = _time_ms
	if not _effects.has(kind):
		_effects[kind] = {}
	_effects[kind][payload.id] = payload
	effect_spawned.emit(kind, payload)


## 广播 effect_updated（payload 是账本里那条记录，调用方已把当前值写进去）；未知效果忽略
func update_effect(kind: StringName, effect_id: String, progress: float) -> void:
	var payload := get_effect(kind, effect_id)
	if payload == null:
		return
	effect_updated.emit(kind, effect_id, progress, payload)


## 出账并广播 effect_removed；未知效果忽略
func remove_effect(kind: StringName, effect_id: String) -> void:
	if not has_effect(kind, effect_id):
		return
	_effects[kind].erase(effect_id)
	effect_removed.emit(kind, effect_id)


## 到期的一次性效果静默出账（view 自管寿命，不发 effect_removed）。
## progress 驱动的效果（攻击特效 / 投射物）总在到期前被 handler 显式移除，这里对它们只是兜底。
func expire_effects(now_ms: int) -> void:
	for kind_variant in _effects.keys():
		var by_id: Dictionary = _effects[kind_variant]
		for effect_id_variant in by_id.keys():
			var payload: VisualEffectPayload.Effect = by_id[effect_id_variant]
			if now_ms - payload.start_time >= payload.duration:
				by_id.erase(effect_id_variant)


# ========== 程序化效果 / 震屏 ==========

func has_procedural_effect(effect_id: String) -> bool:
	for effect in _procedural_effects:
		if effect.id == effect_id:
			return true
	return false


## 入账一条程序化效果（寿命簿；入账时间盖到 start_time）
func add_procedural_effect(effect: VisualEffectPayload.ProceduralEffect) -> void:
	effect.start_time = _time_ms
	_procedural_effects.append(effect)


## 活跃的程序化效果（账本里的数组本身，只读）
func get_procedural_effects() -> Array[VisualEffectPayload.ProceduralEffect]:
	return _procedural_effects


## 到期的程序化效果出账
func expire_procedural_effects(now_ms: int) -> void:
	_procedural_effects = _procedural_effects.filter(func(effect: VisualEffectPayload.ProceduralEffect) -> bool:
		return now_ms - effect.start_time < effect.duration
	)


func set_screen_shake(offset: Vector2) -> void:
	_screen_shake = VisualEffectPayload.ScreenShake.new()
	_screen_shake.offset_x = offset.x
	_screen_shake.offset_y = offset.y


# ========== live 入口 ==========

## live 场景直接入账一个 actor（没有录像 ActorInitData）：hp 缺省等于 max_hp，max_hp 缺省 1（dormant 血条）；
## 入账并广播 actor_spawned + actor_state_changed。空 id / 已在账上返回 null、不广播（与 spawn_actor 同口径：
## 要改位置走 set_actor_position，要重建先 despawn_actor）
func seed_actor(actor_id: String, display_name: String, position: Vector2, hp: float = NAN, max_hp: float = NAN) -> ActorVisualState:
	if actor_id.is_empty() or _actors.has(actor_id):
		return null
	var actor := ActorVisualState.new()
	actor.id = actor_id
	actor.display_name = display_name
	actor.position = position
	actor.max_hp = max_hp if not is_nan(max_hp) else 1.0
	actor.target_hp = hp if not is_nan(hp) else actor.max_hp
	actor.visual_hp = actor.target_hp
	actor.is_alive = true
	_actors[actor_id] = actor
	_interpolated_positions[actor_id] = position
	actor_spawned.emit(actor_id, actor)
	actor_state_changed.emit(actor_id, actor)
	return actor


## live 场景出账一个 actor：账本 / 在飞插值 / 脏标记一并抹掉，广播 actor_despawned；未知 id 忽略。
## 它在步进器里的在飞卡片账本管不着，调用方先 ActionStepper.cancel_for_actor
func despawn_actor(actor_id: String) -> void:
	if not _actors.has(actor_id):
		return
	_actors.erase(actor_id)
	_interpolated_positions.erase(actor_id)
	_dirty_actors.erase(actor_id)
	actor_despawned.emit(actor_id)


## 直接定位（无动画）：账本位置与在飞插值一起写，当场广播；未知 actor 忽略。
## live 场景的 snap = ActionStepper.cancel_for_actor + 这一步
func set_actor_position(actor_id: String, position: Vector2) -> void:
	var actor: ActorVisualState = _actors.get(actor_id)
	if actor != null:
		actor.position = position
		_interpolated_positions[actor_id] = position
		actor_state_changed.emit(actor_id, actor)
