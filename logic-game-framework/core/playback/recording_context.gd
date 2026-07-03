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
##
## 走 GameWorld.event_collector，与 Action 主动 push 的事件共用同一个 buffer。
## 这样 callback(AbilityGranted/AttributeChanged/...)与 Action push(damage/...)
## 在调用栈穿插发生时,真实时序被自然保留 —— battle_procedure 帧末 flush()
## 一次性拿到的就是按发生顺序排列的事件流。
##
## is_recording guard 保留:防 stop_recording 与 unsubscribe 之间的 callback 残响
## 把脏事件灌进 collector(此时 collector 仍在被复用,无录像消费)。
func push_event(event: Dictionary) -> void:
	if _recorder.is_recording:
		GameWorld.event_collector.push(event)
