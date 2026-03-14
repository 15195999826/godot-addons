class_name TimelineData
extends RefCounted

## Timeline 时间轴数据类
##
## 描述技能执行的时间轴，定义各个动作点（Tag）的时间。

var id: String
var total_duration: float
var tags: Dictionary  # String -> float


func _init(p_id: String, p_total_duration: float, p_tags: Dictionary = {}) -> void:
	id = p_id
	total_duration = p_total_duration
	tags = p_tags


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
		"tags": tags
	}


## 从 Dictionary 反序列化（用于加载）
static func from_dict(data: Dictionary) -> TimelineData:
	return TimelineData.new(
		data.get("id", ""),
		data.get("totalDuration", 0.0),
		data.get("tags", {})
	)
