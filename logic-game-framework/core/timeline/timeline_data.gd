class_name TimelineData
extends RefCounted

## Timeline 时间轴数据类
##
## 描述技能执行的时间轴，定义各个动作点（Tag）的时间。

var id: String
var total_duration: float
var tags: Dictionary  # String -> float

## 循环配置：loop=true 表示 timeline 跑完后重启；max_loops 限制总轮数（-1 = 无限）
var loop: bool = false
var max_loops: int = -1


func _init(p_id: String, p_total_duration: float, p_tags: Dictionary = {}) -> void:
	id = p_id
	total_duration = p_total_duration
	tags = p_tags


## 创建周期性 Timeline（用于 DOT/HOT 等每 N ms 触发一次的场景）
##
## 产出：total_duration=interval_ms, tags={tick_tag: 0.0}, loop=true。
## 注意：tag_time=0.0 的 keyframe 是 timeline "异步时间点" 概念里的 0ms 位置；
## 真正的同步触发用 on_timeline_start/end，不走 tag 机制。
static func periodic(p_id: String, p_interval_ms: float, p_tick_tag: String = "tick") -> TimelineData:
	var t := TimelineData.new(p_id, p_interval_ms, {p_tick_tag: 0.0})
	t.loop = true
	return t


## 获取 tag 时间，未找到返回 -1.0
func get_tag_time(tag_name: String) -> float:
	return float(tags[tag_name]) if tags.has(tag_name) else -1.0


## 获取所有 tag 名称
func get_tag_names() -> Array[String]:
	var result: Array[String] = []
	result.assign(tags.keys())
	return result


## 获取按时间排序的 tags
func get_sorted_tags() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tag_name in tags.keys():
		result.append({
			"name": tag_name,
			"time": float(tags[tag_name])
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a["time"] < b["time"])
	return result


## 验证 Timeline 数据合法性
func validate() -> Array[String]:
	var errors: Array[String] = []
	
	if id == "":
		errors.append("Timeline id is required")
	
	if total_duration <= 0.0:
		errors.append("Timeline totalDuration must be positive")
	
	for tag_name in tags.keys():
		var time_value := float(tags[tag_name])
		if time_value < 0.0:
			errors.append("Tag \"%s\" has negative time: %s" % [tag_name, time_value])
		elif time_value > total_duration:
			errors.append("Tag \"%s\" time (%s) exceeds totalDuration (%s)" % [tag_name, time_value, total_duration])
	
	return errors


## 序列化为 Dictionary（用于保存/网络传输）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"totalDuration": total_duration,
		"tags": tags,
		"loop": loop,
		"maxLoops": max_loops,
	}


## 从 Dictionary 反序列化（用于加载）
static func from_dict(data: Dictionary) -> TimelineData:
	var t := TimelineData.new(
		data.get("id", ""),
		data.get("totalDuration", 0.0),
		data.get("tags", {})
	)
	t.loop = data.get("loop", false)
	t.max_loops = data.get("maxLoops", -1)
	return t
