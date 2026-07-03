class_name ReplayData
extends RefCounted
## ReplayData - 录像数据强类型类
##
## 提供 BattleRecord, BattleMeta, FrameData, ActorInitData 四个内部类
## 每个类实现 to_dict() 和 from_dict() 方法，支持序列化/反序列化

const PROTOCOL_VERSION = "2.0"


class BattleRecord:
	var version: String = PROTOCOL_VERSION
	var meta: BattleMeta
	var configs: Dictionary = {}
	var map_config: Dictionary = {}  # 保持 Dictionary，兼容不同地图类型
	var initial_actors: Array[ActorInitData] = []
	var timeline: Array[FrameData] = []
	
	func to_dict() -> Dictionary:
		var actors_arr: Array[Dictionary] = []
		for a in initial_actors:
			actors_arr.append(a.to_dict() if a is ActorInitData else a)
		var timeline_arr: Array[Dictionary] = []
		for f in timeline:
			timeline_arr.append(f.to_dict() if f is FrameData else f)
		return {
			"version": version,
			"meta": meta.to_dict() if meta else {},
			"configs": configs,
			"mapConfig": map_config,
			"initialActors": actors_arr,
			"timeline": timeline_arr,
		}
	
	static func from_dict(d: Dictionary) -> BattleRecord:
		var record := BattleRecord.new()
		record.version = d.get("version", PROTOCOL_VERSION)
		record.meta = BattleMeta.from_dict(d.get("meta", {}))
		record.configs = d.get("configs", {})
		record.map_config = d.get("mapConfig", {})
		record.initial_actors = []
		for a in d.get("initialActors", []):
			record.initial_actors.append(ActorInitData.from_dict(a))
		record.timeline = []
		for f in d.get("timeline", []):
			record.timeline.append(FrameData.from_dict(f))
		return record


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


class ActorInitData:
	var id: String = ""
	var type: String = ""
	var config_id: String = ""
	var display_name: String = ""
	var team: int = 0
	var position: Array = []  # 元素可能是 int/float，保持无类型
	var attributes: Dictionary = {}
	var abilities: Array[Dictionary] = []
	var tags: Dictionary = {}
	
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
		data.abilities = actor.get_ability_snapshot()
		data.tags = actor.get_tag_snapshot()
		return data
	
	func to_dict() -> Dictionary:
		return {
			"id": id, "type": type, "configId": config_id,
			"displayName": display_name, "team": team,
			"position": position, "attributes": attributes,
			"abilities": abilities, "tags": tags,
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
		data.abilities = d.get("abilities", [])
		data.tags = d.get("tags", {})
		return data
