extends Node

var _timelines: Dictionary = {}

## 三态注册: 新 id → 存; 同引用重注册 → 幂等 no-op; 同 id 异引用 → crash。
## 后者既防两处各造同名 timeline 静默互踩(旧行为 last-write-wins), 也焊死
## 「timeline 必须声明为 static 常量、禁止工厂函数内联 new」的惯例。
## 注册即冻结 tags(共享实例被多技能引用, 运行时篡改会污染所有共享者)。
func register(timeline: TimelineData) -> void:
	if timeline.id == "":
		return
	var existing: TimelineData = _timelines.get(timeline.id, null)
	if existing == timeline:
		return
	Log.assert_crash(existing == null, "TimelineRegistry",
		"timeline id 冲突: '%s' 已被另一实例注册; timeline 必须 static 声明全局唯一, 不许内联 new" % timeline.id)
	timeline.tags.make_read_only()
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
