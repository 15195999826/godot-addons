class_name PlaybackData
extends RefCounted
## PlaybackData - 录像数据强类型类
##
## 提供 BattleRecord, BattleMeta, WorldSnapshot, FrameData, ActorInitData 五个内部类
## 每个类实现 to_dict() 和 from_dict() 方法，支持序列化/反序列化
##
## 录像文件形状:
##   { "meta": {...},
##     "world_snapshot": { "actors": [...], "mapConfig": {...}, "positionFormats": {...} },
##     "timeline": [ {"frame": N, "events": [...]}, ... ] }
##
## 无 version 字段 —— 单一底层架构、录像是短命数据（打完→播完→丢），不做多版本共存;
## 防呆走必需字段检查: from_dict 对缺失 world_snapshot / timeline 的 dict 直接 crash,
## 坏文件要炸得响, 不允许静默播空场。


class BattleRecord:
	var meta: BattleMeta
	var world_snapshot: WorldSnapshot = null
	var timeline: Array[FrameData] = []

	func to_dict() -> Dictionary:
		var timeline_arr: Array[Dictionary] = []
		for f in timeline:
			timeline_arr.append(f.to_dict() if f is FrameData else f)
		return {
			"meta": meta.to_dict() if meta else {},
			"world_snapshot": world_snapshot.to_dict() if world_snapshot else {},
			"timeline": timeline_arr,
		}

	static func from_dict(d: Dictionary) -> BattleRecord:
		Log.assert_crash(d.has("world_snapshot"), "PlaybackData",
			"录像 dict 缺 world_snapshot —— 坏文件或非录像数据, 拒绝静默播空场")
		Log.assert_crash(d.has("timeline"), "PlaybackData",
			"录像 dict 缺 timeline —— 坏文件或非录像数据")
		var record := BattleRecord.new()
		record.meta = BattleMeta.from_dict(d.get("meta", {}))
		record.world_snapshot = WorldSnapshot.from_dict(d.get("world_snapshot", {}))
		record.timeline = []
		for f in d.get("timeline", []):
			record.timeline.append(FrameData.from_dict(f))
		return record


## 开战时刻的世界侧状态切片。由 WorldGameplayInstance.capture_world_snapshot() 产出,
## recorder 只接收不自产。回放器按 positionFormats 解释各 actor 的 position 数组。
class WorldSnapshot:
	var actors: Array[ActorInitData] = []
	var map_config: Dictionary = {}
	var position_formats: Dictionary = {}

	func to_dict() -> Dictionary:
		var actors_arr: Array[Dictionary] = []
		for a in actors:
			actors_arr.append(a.to_dict() if a is ActorInitData else a)
		return {
			"actors": actors_arr,
			"mapConfig": map_config,
			"positionFormats": position_formats,
		}

	static func from_dict(d: Dictionary) -> WorldSnapshot:
		var snap := WorldSnapshot.new()
		for a in d.get("actors", []):
			snap.actors.append(ActorInitData.from_dict(a))
		snap.map_config = d.get("mapConfig", {})
		snap.position_formats = d.get("positionFormats", {})
		return snap


class BattleMeta:
	var battle_id: String = ""
	var recorded_at: int = 0
	var tick_interval: int = 100
	var total_frames: int = 0
	var result: String = ""

	func to_dict() -> Dictionary:
		return {
			"battleId": battle_id,
			"recordedAt": recorded_at,
			"tickInterval": tick_interval,
			"totalFrames": total_frames,
			"result": result,
		}

	static func from_dict(d: Dictionary) -> BattleMeta:
		var meta := BattleMeta.new()
		meta.battle_id = d.get("battleId", "")
		meta.recorded_at = d.get("recordedAt", 0)
		meta.tick_interval = d.get("tickInterval", 100)
		meta.total_frames = d.get("totalFrames", 0)
		meta.result = d.get("result", "")
		return meta


class FrameData:
	var frame: int = 0
	var events: Array[Dictionary] = []

	func to_dict() -> Dictionary:
		return { "frame": frame, "events": events }

	static func from_dict(d: Dictionary) -> FrameData:
		var fd := FrameData.new()
		fd.frame = d.get("frame", 0)
		fd.events = d.get("events", [])
		return fd


## 单个 actor 的回放自足快照 —— 只含视觉替身重建所需字段（回放不重建逻辑层,
## 见 docs/README.md 设计铁律"Playback 不重建逻辑层"）。attributes 含派生值
## (如 maxHp): 回放器没有规则引擎, 不能像存档那样读档重算。
class ActorInitData:
	var id: String = ""
	var type: String = ""
	var config_id: String = ""
	var display_name: String = ""
	var team: int = 0
	var position: Array = []  # 元素可能是 int/float，保持无类型
	var attributes: Dictionary = {}

	## 从 Actor 实例创建 ActorInitData（用于录像）
	static func create(actor: Actor) -> ActorInitData:
		var data := ActorInitData.new()
		data.id = actor.id
		data.type = actor.type
		data.config_id = actor.config_id
		data.display_name = actor.display_name
		data.team = actor.team
		data.position = actor.get_position_snapshot()  # 使用 Actor 的快照方法
		data.attributes = actor.get_attribute_snapshot()
		return data

	func to_dict() -> Dictionary:
		return {
			"id": id, "type": type, "configId": config_id,
			"displayName": display_name, "team": team,
			"position": position, "attributes": attributes,
		}

	static func from_dict(d: Dictionary) -> ActorInitData:
		var data := ActorInitData.new()
		data.id = d.get("id", "")
		data.type = d.get("type", "")
		data.config_id = d.get("configId", "")
		data.display_name = d.get("displayName", "")
		data.team = d.get("team", 0)
		data.position = d.get("position", [])
		data.attributes = d.get("attributes", {})
		return data
