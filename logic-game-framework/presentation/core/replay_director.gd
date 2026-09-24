## ReplayDirector - 录像回放表演实例
##
## 在 VisualDirector 上加帧时钟：load_playback 把录像 timeline 摊成帧表，_process / step 攒 delta，
## 每满一个逻辑帧（tick_ms 取录像 meta.tick_interval，≤ 0 退回 100）推进一帧、把那帧的事件交给 pump。
## 帧 0 是开战台面（账本由 world_snapshot 重建），事件从帧 1 起处理。
## 录像帧播完不立即结束：继续 pump 到步进器排空（所有卡片完成）才发 playback_ended。
class_name ReplayDirector
extends VisualDirector


# ========== 信号 ==========

signal playback_state_changed(is_playing: bool)
signal frame_changed(current_frame: int, total_frames: int)
signal playback_ended()


# ========== 常量 ==========

## 录像没给 tick_interval 时的逻辑帧间隔（毫秒）
const DEFAULT_TICK_MS: float = 100.0
const FRAME_DELTA_WARN_MS: float = 50.0
const TICK_COST_WARN_MS: float = 8.0


# ========== 状态 ==========

var _record: PlaybackData.BattleRecord

## 帧表（frame -> FrameData）
var _frame_data_map: Dictionary = {}

## 逻辑帧间隔（毫秒），随录像 load 更新
var _tick_ms: float = DEFAULT_TICK_MS

var _is_playing: bool = false
var _speed: float = 1.0
var _current_frame: int = 0
var _total_frames: int = 0

## 逻辑帧累积时间（毫秒）
var _accumulator: float = 0.0


# ========== 生命周期 ==========

func _exit_tree() -> void:
	_frame_data_map.clear()
	_record = null
	super()


func _process(delta: float) -> void:
	if not _is_playing:
		return

	# delta 是秒；表演层内部一律毫秒，乘播放速度后推进
	var real_delta_ms := delta * 1000.0
	var playback_delta_ms := real_delta_ms * _speed
	if real_delta_ms >= FRAME_DELTA_WARN_MS:
		print("[Presentation:ReplayDirector] long_process_delta frame=%d real_delta_ms=%.2f playback_delta_ms=%.2f speed=%.2f active_actions=%d" % [
			_current_frame,
			real_delta_ms,
			playback_delta_ms,
			_speed,
			get_action_count(),
		])
	var start_usec := Time.get_ticks_usec()
	_advance(playback_delta_ms)
	var tick_cost_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	if tick_cost_ms >= TICK_COST_WARN_MS:
		print("[Presentation:ReplayDirector] tick_cost frame=%d input_delta_ms=%.2f cost_ms=%.2f active_actions=%d" % [
			_current_frame,
			playback_delta_ms,
			tick_cost_ms,
			get_action_count(),
		])


# ========== 公共方法 ==========

## 加载录像：建帧表、账本重建到开战台面、帧归 0；反复调用 = 换片（在飞卡片清空）。播放态不变。
func load_playback(record: PlaybackData.BattleRecord) -> void:
	Log.assert_crash(record != null and record.meta != null, "ReplayDirector",
		"录像缺 meta —— 没有总帧数与帧间隔无法回放")
	_record = record
	_tick_ms = float(record.meta.tick_interval) if record.meta.tick_interval > 0 else DEFAULT_TICK_MS

	_frame_data_map.clear()
	for frame_data: PlaybackData.FrameData in record.timeline:
		_frame_data_map[frame_data.frame] = frame_data
	_total_frames = record.meta.total_frames

	_state.initialize_from_replay(record)
	_analyze_event_coverage()

	_current_frame = 0
	_accumulator = 0.0
	_stepper.cancel_all()

	frame_changed.emit(_current_frame, _total_frames)


## 开始播放；已结束的先自动 reset
func play() -> void:
	if _is_ended():
		reset()
	_is_playing = true
	playback_state_changed.emit(true)


func pause() -> void:
	_is_playing = false
	playback_state_changed.emit(false)


## 播放 / 暂停切换；已结束时无动作
func toggle() -> void:
	if _is_ended():
		return
	if _is_playing:
		pause()
	else:
		play()


## 停播、清步进器、账本回到开战台面、帧归 0
func reset() -> void:
	_is_playing = false
	playback_state_changed.emit(false)

	_stepper.cancel_all()
	_state.reset_to(_record)

	_current_frame = 0
	_accumulator = 0.0

	frame_changed.emit(_current_frame, _total_frames)


## 确定性手动推进：不经 _process / 不看播放态，按精确 delta_ms 走一趟。
## 供暂停后逐步进到目标帧、定格捕获瞬时效果；与正常播放同一条路径。
func step(delta_ms: float) -> void:
	if delta_ms > 0.0:
		_advance(delta_ms)


func set_speed(speed: float) -> void:
	_speed = speed


func get_speed() -> float:
	return _speed


func get_current_frame() -> int:
	return _current_frame


func get_total_frames() -> int:
	return _total_frames


func is_playing() -> bool:
	return _is_playing


func is_ended() -> bool:
	return _is_ended()


# ========== 帧时钟 ==========

## 攒 delta，每满一帧推进一帧并收下那帧的事件，本趟事件与 delta 一起交给 pump。
## 录像播完后不再推帧、只排空动画；步进器空了才算结束。
func _advance(delta_ms: float) -> void:
	_accumulator += delta_ms
	var events: Array[Dictionary] = []

	while _accumulator >= _tick_ms:
		_accumulator -= _tick_ms
		var next_frame := _current_frame + 1
		if next_frame > _total_frames:
			break
		_current_frame = next_frame

		var frame_data: PlaybackData.FrameData = _frame_data_map.get(next_frame)
		if frame_data != null and not frame_data.events.is_empty():
			Log.debug("ReplayDirector", "帧 %d: %d 个事件" % [next_frame, frame_data.events.size()])
			events.append_array(frame_data.events)

		frame_changed.emit(_current_frame, _total_frames)

	pump(delta_ms, events)

	if _is_ended():
		_is_playing = false
		playback_state_changed.emit(false)
		playback_ended.emit()


func _is_ended() -> bool:
	return _current_frame >= _total_frames and _stepper.get_action_count() == 0


## 加载时打印一次：录像里每种事件各多少条、由哪些翻译员处理、谁没人管
func _analyze_event_coverage() -> void:
	var all_event_kinds: Dictionary = {}  # kind -> count
	for frame_data: PlaybackData.FrameData in _record.timeline:
		for event: Dictionary in frame_data.events:
			var kind: String = event.get("kind", "unknown")
			all_event_kinds[kind] = all_event_kinds.get(kind, 0) + 1

	if all_event_kinds.is_empty():
		print("[Presentation:ReplayDirector] 事件覆盖分析: 无事件")
		return

	var covered: Array[String] = []
	var uncovered: Array[String] = []
	for kind: String in all_event_kinds.keys():
		var count: int = all_event_kinds[kind]
		var translators := _registry.get_translators_for(kind)
		if translators.size() > 0:
			covered.append("%s (%d) -> %s" % [kind, count, ", ".join(translators)])
		else:
			uncovered.append("%s (%d)" % [kind, count])

	print("[Presentation:ReplayDirector] 事件覆盖分析 (共 %d 种事件类型):" % all_event_kinds.size())
	if covered.size() > 0:
		print("  ✓ 已覆盖 (%d 种):" % covered.size())
		for item: String in covered:
			print("    - %s" % item)
	if uncovered.size() > 0:
		print("  ⚠ 未覆盖 (%d 种): %s" % [uncovered.size(), ", ".join(uncovered)])
