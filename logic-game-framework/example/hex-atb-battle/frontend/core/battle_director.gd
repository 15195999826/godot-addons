## BattleDirector - hex 战斗回放表演实例（帧时钟 + 共享 tick 体）
##
## 整合 TranslatorRegistry、ActionStepper、VisualState、VisualUpdater，
## 提供完整的战斗回放控制能力。
##
## 作为 Node 实现，负责：
## - _process(delta) 驱动 tick
## - 只发信号，不持 view（账本的 7 条信号原样转发）
## - 接收输入（play/pause）
class_name FrontendBattleDirector
extends Node


# ========== 信号 ==========

## 播放状态变化
signal playback_state_changed(is_playing: bool)

## 帧变化
signal frame_changed(current_frame: int, total_frames: int)

## 播放结束
signal playback_ended()

## 以下 7 条转发自 VisualState
signal actor_state_changed(actor_id: String, state: ActorVisualState)
signal actor_spawned(actor_id: String, state: ActorVisualState)
signal actor_died(actor_id: String)
signal actor_despawned(actor_id: String)
signal effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect)
signal effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect)
signal effect_removed(kind: StringName, effect_id: String)


# ========== 常量 ==========

## 逻辑帧间隔（毫秒）
const LOGIC_TICK_MS: float = 100.0
const FRAME_DELTA_WARN_MS: float = 50.0
const TICK_COST_WARN_MS: float = 8.0


# ========== 导出属性 ==========

## 初始播放速度
@export var initial_speed: float = 1.0

## 是否自动播放
@export var auto_play: bool = false


# ========== 核心组件 ==========

## 翻译员注册表
var _registry: TranslatorRegistry

## 步进器
var _stepper: ActionStepper

## 账本
var _state: VisualState

## 更新器（记账规则）；项目私有卡片在建好 Director 后 updater.register_handler 挂进来
var updater: VisualUpdater


# ========== 状态 ==========

## 回放数据
var _replay_data: PlaybackData.BattleRecord

## 帧数据 Map（frame -> events）
var _frame_data_map: Dictionary = {}

## 是否正在播放
var _is_playing: bool = false

## 当前播放速度
var _speed: float = 1.0

## 当前逻辑帧
var _current_frame: int = 0

## 总帧数
var _total_frames: int = 0

## 逻辑帧累积时间
var _logic_accumulator: float = 0.0


# ========== 生命周期 ==========

func _ready() -> void:
	_speed = initial_speed

	# 初始化核心组件
	_registry = FrontendDefaultRegistry.create()
	_stepper = ActionStepper.new()
	_state = VisualState.new()
	updater = VisualUpdater.new()

	# 连接账本信号
	_state.actor_state_changed.connect(_on_actor_state_changed)
	_state.actor_spawned.connect(_on_actor_spawned)
	_state.actor_died.connect(_on_actor_died)
	_state.actor_despawned.connect(_on_actor_despawned)
	_state.effect_spawned.connect(_on_effect_spawned)
	_state.effect_updated.connect(_on_effect_updated)
	_state.effect_removed.connect(_on_effect_removed)

	if auto_play and not _replay_data.is_empty():
		play()


func _exit_tree() -> void:
	# 断开账本信号连接
	if _state:
		_state.actor_state_changed.disconnect(_on_actor_state_changed)
		_state.actor_spawned.disconnect(_on_actor_spawned)
		_state.actor_died.disconnect(_on_actor_died)
		_state.actor_despawned.disconnect(_on_actor_despawned)
		_state.effect_spawned.disconnect(_on_effect_spawned)
		_state.effect_updated.disconnect(_on_effect_updated)
		_state.effect_removed.disconnect(_on_effect_removed)

	# 清空 RefCounted 引用，打破循环引用
	_state = null
	_stepper = null
	_registry = null
	updater = null


func _process(delta: float) -> void:
	if not _is_playing:
		return

	# delta 是 Godot _process(delta) 传入的，单位是秒（比如 60fps 时 ≈ 0.0167 秒）。
	# 整个表演层内部的时间单位统一用毫秒（duration、delay、elapsed 全是 ms）。
	# 转为毫秒后再乘以播放速度。
	var real_delta_ms := delta * 1000.0
	var playback_delta_ms := real_delta_ms * _speed
	if real_delta_ms >= FRAME_DELTA_WARN_MS:
		print("[Frontend:FrameDiag] long_process_delta frame=%d real_delta_ms=%.2f playback_delta_ms=%.2f speed=%.2f active_actions=%d" % [
			_current_frame,
			real_delta_ms,
			playback_delta_ms,
			_speed,
			_stepper.get_action_count(),
		])
	var start_usec := Time.get_ticks_usec()
	_tick(playback_delta_ms)
	var tick_cost_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	if tick_cost_ms >= TICK_COST_WARN_MS:
		print("[Frontend:FrameDiag] tick_cost frame=%d input_delta_ms=%.2f cost_ms=%.2f active_actions=%d" % [
			_current_frame,
			playback_delta_ms,
			tick_cost_ms,
			_stepper.get_action_count(),
		])


# ========== 公共方法 ==========

## 加载回放数据
func load_playback(record: PlaybackData.BattleRecord) -> void:
	_replay_data = record

	# 构建帧数据 Map
	_frame_data_map.clear()
	for frame_data: PlaybackData.FrameData in record.timeline:
		_frame_data_map[frame_data.frame] = frame_data

	# 获取总帧数
	_total_frames = record.meta.total_frames

	# 重建账本台面
	_state.initialize_from_replay(record)

	# 分析事件覆盖情况（只在加载时打印一次）
	_analyze_event_coverage()

	# 重置状态
	_current_frame = 0
	_logic_accumulator = 0.0
	_stepper.cancel_all()

	frame_changed.emit(_current_frame, _total_frames)


## 开始播放
func play() -> void:
	# 自动重置已结束的回放
	if _is_ended():
		reset()

	_is_playing = true
	playback_state_changed.emit(true)


## 暂停播放
func pause() -> void:
	_is_playing = false
	playback_state_changed.emit(false)


## 切换播放/暂停
func toggle() -> void:
	if _is_ended():
		return

	if _is_playing:
		pause()
	else:
		play()


## 重置到初始状态
func reset() -> void:
	# 停止播放
	_is_playing = false
	playback_state_changed.emit(false)

	# 清空步进器
	_stepper.cancel_all()

	# 重置账本
	_state.reset_to(_replay_data)

	# 重置帧状态
	_current_frame = 0
	_logic_accumulator = 0.0

	frame_changed.emit(_current_frame, _total_frames)


## 确定性手动推进:不经 _process / 不看 _is_playing,按精确 delta_ms 走一步。
## 供 DevAgent 暂停后逐步进到目标帧,定格捕获瞬时 VFX。复用 _tick 全部逻辑
## (帧推进 / 步进器 / 记账 / playback_ended),与正常播放同一路径。
func step(delta_ms: float) -> void:
	if delta_ms > 0.0:
		_tick(delta_ms)


## 设置播放速度
func set_speed(speed: float) -> void:
	_speed = speed


## 获取当前播放速度
func get_speed() -> float:
	return _speed


## 获取当前帧
func get_current_frame() -> int:
	return _current_frame


## 获取总帧数
func get_total_frames() -> int:
	return _total_frames


## 是否正在播放
func is_playing() -> bool:
	return _is_playing


## 是否已结束
func is_ended() -> bool:
	return _is_ended()


## 获取 Actor 状态快照（actor_id -> ActorVisualState）
func get_actors_snapshot() -> Dictionary:
	return _state.get_actors_snapshot()


## 获取角色逻辑平面坐标（含在飞插值）；像素 / 3D 投影由持有棋盘几何的 view 层做
func get_actor_position(actor_id: String) -> Vector2:
	return _state.get_actor_position(actor_id)


## 获取震屏偏移
func get_screen_shake_offset() -> Vector2:
	return _state.get_screen_shake_offset()


# ========== 内部方法 ==========

## 每帧更新：事件直改 → 翻译 → 入步进器 → 推进账本时间 → 步进 → 记账 → 到期清理 + hp 追赶 → flush
func _tick(delta_ms: float) -> void:
	# 累积时间
	_logic_accumulator += delta_ms

	# 检查是否需要推进逻辑帧
	while _logic_accumulator >= LOGIC_TICK_MS:
		_logic_accumulator -= LOGIC_TICK_MS

		# 推进逻辑帧
		var next_frame := _current_frame + 1

		# 检查是否已到达最后一帧
		if next_frame > _total_frames:
			# 不要在这里停止播放，让动画继续播放
			break

		_current_frame = next_frame

		# 查找该帧的事件
		if _frame_data_map.has(next_frame):
			var frame_data: PlaybackData.FrameData = _frame_data_map[next_frame]
			var events: Array[Dictionary] = frame_data.events

			if events.size() > 0:
				Log.debug("BattleDirector", "帧 %d: %d 个事件" % [next_frame, events.size()])

			# actor_spawned / actor_destroyed 先改账本，再用最新的只读视图翻译表演卡片。
			for event: Dictionary in events:
				_log_event_frame_diag(next_frame, event)
				updater.apply_event(_state, event)
				var query := _state.as_query()
				var actions := _registry.translate(event, query)
				_stepper.enqueue(actions)

		frame_changed.emit(_current_frame, _total_frames)

	# 推进账本时间
	_state.advance_time(int(delta_ms))

	# 步进器 tick（即使逻辑帧结束，也要继续推进动画）
	var result := _stepper.tick(delta_ms)

	# 记账
	if result.has_changes:
		# 先应用活跃卡片
		updater.apply_actions(_state, result.active_actions)
		# 再应用本帧完成的卡片（确保最终状态被应用）
		updater.apply_actions(_state, result.completed_this_tick)

	# 到期效果清理 + 血条 visual_hp 朝 target_hp 收敛(state 路径,每 tick 推进,
	# 与卡片系统解耦,即便没有任何卡片活跃也要 lerp)
	updater.tick_time(_state, delta_ms)

	# 批量触发状态变化信号
	_state.flush_dirty_actors()

	# 检查是否所有动画都已完成
	# NOTE: 逻辑帧播完后不会立即结束，会继续 tick 步进器直到所有表演卡片完成。
	# 因此无需额外填充帧数 —— _stepper.get_action_count() == 0 确保所有动画播放完毕。
	if _current_frame >= _total_frames and _stepper.get_action_count() == 0:
		_is_playing = false
		playback_state_changed.emit(false)
		playback_ended.emit()


func _log_event_frame_diag(replay_frame: int, event: Dictionary) -> void:
	var kind: String = event.get("kind", "")
	if kind == "actor_spawned":
		var actor: Dictionary = event.get("actor", {}) as Dictionary
		var config_id: String = actor.get("config_id", "") as String
		if config_id == "fire_tile":
			print("[Frontend:FrameDiag] fire_tile_actor_spawned replay_frame=%d actor_id=%s position=%s" % [
				replay_frame,
				event.get("actor_id", ""),
				actor.get("position", []),
			])


## 检查是否已结束
func _is_ended() -> bool:
	return _current_frame >= _total_frames and _stepper.get_action_count() == 0


## 分析事件覆盖情况
## 在表演开始时调用，打印一次事件类型与翻译员匹配摘要
func _analyze_event_coverage() -> void:
	var all_event_kinds: Dictionary = {}  # kind -> count

	# 收集所有事件类型及其出现次数
	for frame_data: PlaybackData.FrameData in _replay_data.timeline:
		for event: Dictionary in frame_data.events:
			var kind: String = event.get("kind", "unknown")
			all_event_kinds[kind] = all_event_kinds.get(kind, 0) + 1

	if all_event_kinds.is_empty():
		print("[Frontend:Director] 事件覆盖分析: 无事件")
		return

	# 分类：已覆盖 vs 未覆盖
	var covered: Array[String] = []
	var uncovered: Array[String] = []

	for kind: String in all_event_kinds.keys():
		var count: int = all_event_kinds[kind]
		var translators := _registry.get_translators_for(kind)

		if translators.size() > 0:
			covered.append("%s (%d) -> %s" % [kind, count, ", ".join(translators)])
		else:
			uncovered.append("%s (%d)" % [kind, count])

	# 打印摘要
	print("[Frontend:Director] 事件覆盖分析 (共 %d 种事件类型):" % all_event_kinds.size())

	if covered.size() > 0:
		print("  ✓ 已覆盖 (%d 种):" % covered.size())
		for item: String in covered:
			print("    - %s" % item)

	if uncovered.size() > 0:
		print("  ⚠ 未覆盖 (%d 种): %s" % [uncovered.size(), ", ".join(uncovered)])


# ========== 信号处理 ==========

func _on_actor_state_changed(actor_id: String, state: ActorVisualState) -> void:
	actor_state_changed.emit(actor_id, state)


func _on_actor_spawned(actor_id: String, state: ActorVisualState) -> void:
	actor_spawned.emit(actor_id, state)


func _on_actor_died(actor_id: String) -> void:
	actor_died.emit(actor_id)


func _on_actor_despawned(actor_id: String) -> void:
	actor_despawned.emit(actor_id)


func _on_effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect) -> void:
	effect_spawned.emit(kind, payload)


func _on_effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect) -> void:
	effect_updated.emit(kind, effect_id, progress, payload)


func _on_effect_removed(kind: StringName, effect_id: String) -> void:
	effect_removed.emit(kind, effect_id)
