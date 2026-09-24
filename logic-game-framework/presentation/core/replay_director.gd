## ReplayDirector - 录像回放表演实例
##
## 在 VisualDirector 上加帧时钟：load_playback 把录像 timeline 摊成帧表，_process / step 攒 delta，
## 每满一个逻辑帧（tick_ms 取录像 meta.tick_interval，≤ 0 退回 100）推进一帧、把那帧的事件交给 pump。
## 帧 0 是开战台面（账本由 world_snapshot 重建），事件从帧 1 起处理。
## 录像帧播完不立即结束：继续 pump 到步进器排空（所有卡片完成）才发 playback_ended，且只报一次。
## 没有录像时 play / reset / step 都无动作。
class_name ReplayDirector
extends VisualDirector


# ========== 信号 ==========

signal playback_state_changed(is_playing: bool)
signal frame_changed(current_frame: int, total_frames: int)
signal playback_ended()


# ========== 常量 ==========

## 录像没给 tick_interval 时的逻辑帧间隔（毫秒）
const DEFAULT_TICK_MS: float = 100.0


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

## playback_ended 已报过（load / reset 归 false）：结束后再 step 只是空转，不重发结束 / 停播。
## 判断式做不到——零帧录像从加载起就是 ended，没有可观察的翻转
var _ended_reported: bool = false


# ========== 生命周期 ==========

func _exit_tree() -> void:
	_frame_data_map.clear()
	_record = null
	super()


func _process(delta: float) -> void:
	if not _is_playing:
		return

	# delta 是秒；表演层内部一律毫秒，乘播放速度后推进
	_advance(delta * 1000.0 * _speed)


# ========== 公共方法 ==========

## 加载录像：建帧表、账本重建到开战台面（账本时间归零）、帧归 0；反复调用 = 换片（在飞卡片清空）。播放态不变。
func load_playback(record: PlaybackData.BattleRecord) -> void:
	Log.assert_crash(record != null and record.meta != null, "ReplayDirector",
		"录像缺 meta —— 没有总帧数与帧间隔无法回放")
	_record = record
	_tick_ms = float(record.meta.tick_interval) if record.meta.tick_interval > 0 else DEFAULT_TICK_MS

	_frame_data_map.clear()
	for frame_data: PlaybackData.FrameData in record.timeline:
		_frame_data_map[frame_data.frame] = frame_data
	_total_frames = record.meta.total_frames

	_state.reset_to(record)

	_current_frame = 0
	_accumulator = 0.0
	_ended_reported = false
	_stepper.cancel_all()

	frame_changed.emit(_current_frame, _total_frames)


## 开始播放；已结束的先自动 reset；没有录像时无动作
func play() -> void:
	if _record == null:
		return
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


## 停播、清步进器、账本回到开战台面、帧归 0；没有录像时无动作（没有台面可回）
func reset() -> void:
	if _record == null:
		return
	_is_playing = false
	playback_state_changed.emit(false)

	_stepper.cancel_all()
	_state.reset_to(_record)

	_current_frame = 0
	_accumulator = 0.0
	_ended_reported = false

	frame_changed.emit(_current_frame, _total_frames)


## 确定性手动推进：不经 _process / 不看播放态，按精确 delta_ms 走一趟。
## 供暂停后逐步进到目标帧、定格捕获瞬时效果；与正常播放同一条路径。
func step(delta_ms: float) -> void:
	if _record != null and delta_ms > 0.0:
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

	if _is_ended() and not _ended_reported:
		_ended_reported = true
		_is_playing = false
		playback_state_changed.emit(false)
		playback_ended.emit()


func _is_ended() -> bool:
	return _current_frame >= _total_frames and _stepper.get_action_count() == 0
