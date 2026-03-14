class_name RecordingContext
## 录像上下文：替代原有的 ctx Dictionary
##
## 持有 BattleRecorder 引用，通过直接访问 recorder 属性来获取实时状态，
## 避免了原有 Dictionary + 闭包方案中值类型（is_recording/current_frame）被快照拷贝的问题。

var actor_id: String
var _recorder: BattleRecorder


func _init(p_actor_id: String, recorder: BattleRecorder) -> void:
	actor_id = p_actor_id
	_recorder = recorder


## 推送录像事件
## 只有在录像进行中时才会实际推送
func push_event(event: Dictionary) -> void:
	if _recorder.is_recording:
		_recorder.pending_events.append(event)
