class_name BattleRecorder
extends RefCounted
## 战斗录像器
##
## 录像事件有两个来源：
## 1. 主动事件（frame_events）：每帧 tick 中由 EventCollector.flush() 收集，如伤害、治疗等
## 2. 被动事件（pending_events）：由 RecordingContext 监听回调在 tick 过程中异步触发，
##    如属性变化、Tag 变化、Ability 获得/移除等
##
## record_frame() 调用时，将两种来源合并写入当前帧的 timeline。
## pending_events 作为帧间缓冲区，在合并后清空。
##
## 【已知问题：录像文件大小】
##
## 当前所有事件无差别录入 timeline，长时间战斗（>500帧）录像文件可能过大。
##
## 优化方案（按优先级）：
##
## 1. 事件过滤：在 record_frame() 中添加可配置的事件白名单/黑名单
##    - 表演层不需要的事件（如 attribute_changed 高频事件）可跳过录入
##    - 通过 recorder_config 传入 { "event_filter": ["damage", "heal", "death", ...] }
##
## 2. 高频事件节流：对同一 actor 的同类事件做帧间合并
##    - 例如连续 3 帧的 attribute_changed 只保留最后一帧的值
##    - 适用于 ATB 进度条等每帧变化的属性
##
## 3. 二进制格式：将 JSON 替换为 MessagePack 或自定义二进制格式
##    - 预期体积减少 50-70%
##    - 需要同步修改 Web 端解析器

var _record: ReplayData.BattleRecord
var _meta: ReplayData.BattleMeta
var is_recording: bool = false
var current_frame: int = 0
var actor_subscriptions: Dictionary = {}
## 帧间事件缓冲区：存放监听回调异步产生的事件，在 record_frame() 时合并并清空
var pending_events: Array[Dictionary] = []

func _init(recorder_config: Dictionary = {}) -> void:
	var battle_id := recorder_config.get("battleId", "") as String
	if battle_id.is_empty():
		battle_id = IdGenerator.generate("battle")

	_meta = ReplayData.BattleMeta.new()
	_meta.battle_id = battle_id
	_meta.tick_interval = recorder_config.get("tickInterval", 100) as int

func start_recording(actors: Array, configs_value: Dictionary = {}, map_config_value: Dictionary = {}) -> void:
	if is_recording:
		push_error("[BattleRecorder] Already recording")
		return

	is_recording = true
	_meta.recorded_at = Time.get_unix_time_from_system()
	current_frame = 0
	pending_events.clear()

	_record = ReplayData.BattleRecord.new()
	_record.meta = _meta
	_record.configs = configs_value
	_record.map_config = map_config_value
	_record.initial_actors = []
	_record.timeline = []

	for actor in actors:
		_record.initial_actors.append(ReplayData.ActorInitData.create(actor))
		_subscribe_actor(actor)


## 仅记录 event timeline, 不含 initial_actors snapshot。
##
## 用于"世界 owns 战斗"新架构: WorldGameplayInstance 已常驻持有 actor/grid,
## 战斗 procedure 无须再快照世界状态 —— 录像只需记录战斗期间的事件流。
## 录像回放时由 ReplayPlayer 从独立的 world_snapshot 字段恢复世界(或复用现有 world)。
##
## 与 start_recording() 的差别:
## - 不写 initial_actors
## - 不写 map_config(world_snapshot 承载)
## - 不订阅 actor 的属性/tag/ability 变化回调(这些由 event_collector 的事件承载)
func start_recording_events_only() -> void:
	if is_recording:
		push_error("[BattleRecorder] Already recording")
		return

	is_recording = true
	_meta.recorded_at = Time.get_unix_time_from_system()
	current_frame = 0
	pending_events.clear()

	_record = ReplayData.BattleRecord.new()
	_record.meta = _meta
	_record.configs = {}
	_record.map_config = {}
	_record.initial_actors = []
	_record.timeline = []

func record_frame(frame: int, events: Array[Dictionary]) -> void:
	if not is_recording:
		return

	current_frame = frame

	var all_events: Array[Dictionary] = []
	all_events.append_array(events)
	all_events.append_array(pending_events)
	pending_events.clear()

	if not all_events.is_empty():
		var frame_data := ReplayData.FrameData.new()
		frame_data.frame = frame
		frame_data.events = all_events
		_record.timeline.append(frame_data)

func stop_recording(result: String = "") -> Dictionary:
	if not is_recording:
		push_error("[BattleRecorder] Not recording")
		return {}

	for subscription in actor_subscriptions.values():
		for unsub in subscription.get("unsubscribes", []):
			if unsub is Callable:
				unsub.call()

	actor_subscriptions.clear()

	is_recording = false

	_meta.total_frames = current_frame
	_meta.result = result

	return _record.to_dict()

func export_json(result: String = "", pretty: bool = true) -> String:
	var record := stop_recording(result)
	return JSON.stringify(record, "\t" if pretty else "")

func get_is_recording() -> bool:
	return is_recording

func get_current_frame() -> int:
	return current_frame

func get_timeline() -> Array[Dictionary]:
	if _record == null:
		return []
	var result: Array[Dictionary] = []
	for f in _record.timeline:
		result.append(f.to_dict() if f is ReplayData.FrameData else f)
	return result

func register_actor(actor: Actor) -> void:
	if not is_recording:
		return

	var init_data := ReplayData.ActorInitData.create(actor)
	var event := GameEvent.ActorSpawned.create(actor.id, init_data.to_dict())
	pending_events.append(event.to_dict())

	_subscribe_actor(actor)

func unregister_actor(actor_id: String, reason: String = "") -> void:
	if not is_recording:
		return

	var event := GameEvent.ActorDestroyed.create(actor_id, reason)
	pending_events.append(event.to_dict())

	var subscription: Dictionary = actor_subscriptions.get(actor_id, {}) as Dictionary
	if not subscription.is_empty():
		for unsub in subscription.get("unsubscribes", []):
			if unsub is Callable:
				unsub.call()

		actor_subscriptions.erase(actor_id)

func _subscribe_actor(actor: Actor) -> void:
	var actor_id := actor.id

	if actor_subscriptions.has(actor_id):
		return

	var ctx := RecordingContext.new(actor_id, self)

	var unsubscribes: Array[Callable] = actor.setup_recording(ctx)

	if not unsubscribes.is_empty():
		actor_subscriptions[actor_id] = {
			"actorId": actor_id,
			"unsubscribes": unsubscribes,
		}
