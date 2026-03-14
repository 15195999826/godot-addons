extends Node

var _timelines: Dictionary = {}

func register(timeline: TimelineData) -> void:
	if timeline.id == "":
		return
	_timelines[timeline.id] = timeline

func register_all(timelines: Array[TimelineData]) -> void:
	for timeline in timelines:
		register(timeline)

func get_timeline(timeline_id: String) -> TimelineData:
	return _timelines.get(timeline_id, null)

func has(timeline_id: String) -> bool:
	return _timelines.has(timeline_id)

func get_all_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_timelines.keys())
	return result

func reset() -> void:
	_timelines = {}
