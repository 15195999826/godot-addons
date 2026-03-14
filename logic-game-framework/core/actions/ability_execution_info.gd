class_name AbilityExecutionInfo
extends RefCounted

## Ability 执行实例信息
##
## 当 Action 由 AbilityExecutionInstance 触发时存在。
## 包含 Timeline 执行相关的上下文信息。

## 执行实例 ID
var id: String

## Timeline ID
var timeline_id: String

## 已执行时间（秒）
var elapsed: float

## 当前触发的 Tag 名称
var current_tag: String


func _init(
	p_id: String = "",
	p_timeline_id: String = "",
	p_elapsed: float = 0.0,
	p_current_tag: String = ""
) -> void:
	id = p_id
	timeline_id = p_timeline_id
	elapsed = p_elapsed
	current_tag = p_current_tag


## 创建 AbilityExecutionInfo
static func create(
	p_id: String,
	p_timeline_id: String,
	p_elapsed: float,
	p_current_tag: String
) -> AbilityExecutionInfo:
	return AbilityExecutionInfo.new(p_id, p_timeline_id, p_elapsed, p_current_tag)


## 序列化为 Dictionary
func to_dict() -> Dictionary:
	return {
		"id": id,
		"timelineId": timeline_id,
		"elapsed": elapsed,
		"currentTag": current_tag,
	}


## 从 Dictionary 反序列化
static func from_dict(d: Dictionary) -> AbilityExecutionInfo:
	return AbilityExecutionInfo.new(
		d.get("id", ""),
		d.get("timelineId", ""),
		d.get("elapsed", 0.0),
		d.get("currentTag", "")
	)
