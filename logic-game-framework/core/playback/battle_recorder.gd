class_name BattleRecorder
extends RefCounted
## 战斗录像器
##
## 职责：管理一次战斗 session 的录像（meta + world_snapshot + timeline + actor 订阅生命周期）。
## 不持有事件 buffer —— 所有事件统一走 GameWorld.event_collector，保证调用栈穿插时真实时序自然成立。
##
## world_snapshot 由世界侧（WorldGameplayInstance.capture_world_snapshot）产出后注入,
## recorder 只管战斗过程（事件流）, 不伸手进世界抄状态。快照是回放的必需品:
## 战斗 blocking 跑完后世界已是终态, 回放要从开战初态播, 初态只存在于快照里
## ——"回放时复用现有 world"对战后回放不成立。
##
## actor 订阅（setup_recording 回调）不可省: attributeChanged 等事件的唯一产生管道
## 就是这些订阅（inkmon render2d 回放消费 attributeChanged 更新属性状态）。
##
## 事件流：
##   Action.execute() ──┐
##                      ├─→ GameWorld.event_collector ──flush()──→ record_frame(events)
##   ability/attr CB ───┘    (按调用栈真实顺序入队)
##
## record_frame(events) 由外部（battle_procedure）每帧调用，传入 flush 出的事件数组写入 timeline。
## register_actor / unregister_actor 也把 ActorSpawned/Destroyed 推到同一个 collector，
## 等下次 record_frame 一并归档。
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

var _record: PlaybackData.BattleRecord
var _meta: PlaybackData.BattleMeta
var is_recording: bool = false
var current_frame: int = 0
var actor_subscriptions: Dictionary = {}

func _init(recorder_config: Dictionary = {}) -> void:
	var battle_id := recorder_config.get("battleId", "") as String
	if battle_id.is_empty():
		battle_id = IdGenerator.generate("battle")

	_meta = PlaybackData.BattleMeta.new()
	_meta.battle_id = battle_id
	_meta.tick_interval = recorder_config.get("tickInterval", 100) as int

## 开始录像。world_snapshot 必传 —— 每场可回放的战斗必须有开战快照（§见头注释）;
## 不录像的战斗不该建 recorder。actors = 需订阅变化回调的 actor（通常 = 快照时的
## 全体 registry actor）; 中途 spawn 的走 register_actor 补订阅。
func start_recording(world_snapshot: PlaybackData.WorldSnapshot, actors: Array[Actor]) -> void:
	if is_recording:
		push_error("[BattleRecorder] Already recording")
		return

	is_recording = true
	_meta.recorded_at = Time.get_unix_time_from_system()
	current_frame = 0

	_record = PlaybackData.BattleRecord.new()
	_record.meta = _meta
	_record.world_snapshot = world_snapshot
	_record.timeline = []

	for actor in actors:
		_subscribe_actor(actor)

func record_frame(frame: int, events: Array[Dictionary]) -> void:
	if not is_recording:
		return

	current_frame = frame

	if not events.is_empty():
		var frame_data := PlaybackData.FrameData.new()
		frame_data.frame = frame
		frame_data.events = events
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
		result.append(f.to_dict() if f is PlaybackData.FrameData else f)
	return result

func register_actor(actor: Actor) -> void:
	if not is_recording:
		return
	if actor_subscriptions.has(actor.id):
		return

	var init_data := PlaybackData.ActorInitData.create(actor)
	var event := GameEvent.ActorSpawned.create(actor.id, init_data.to_dict())
	GameWorld.event_collector.push(event.to_dict())

	_subscribe_actor(actor)
	_record_existing_actor_abilities(actor)

func unregister_actor(actor_id: String, reason: String = "") -> void:
	if not is_recording:
		return

	var event := GameEvent.ActorDestroyed.create(actor_id, reason)
	GameWorld.event_collector.push(event.to_dict())

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


func _record_existing_actor_abilities(actor: Actor) -> void:
	var ability_set := IAbilitySetOwner.get_ability_set(actor)
	if ability_set == null:
		return
	for ability in ability_set.get_abilities():
		if ability.is_expired():
			continue
		var granted_payload := ability.serialize()
		granted_payload["instanceId"] = ability.id
		GameWorld.event_collector.push(
			GameEvent.AbilityGranted.create(actor.id, granted_payload).to_dict()
		)
		for instance in ability.get_executing_instances():
			GameWorld.event_collector.push(
				GameEvent.ExecutionActivated.create(
					actor.id,
					ability.id,
					ability.config_id,
					instance.id,
					instance.timeline_id,
				).to_dict()
			)
