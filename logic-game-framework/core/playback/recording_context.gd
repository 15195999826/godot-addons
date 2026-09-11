class_name RecordingContext
## 录像上下文：BattleRecorder 订阅 actor 时为它建一个，交给录像回调推事件。
##
## 持有 BattleRecorder 引用，推事件时读 recorder 的实时 is_recording，不在构造时拷贝状态快照。

var actor_id: String
var _recorder: BattleRecorder
## recorder 注入的 event_collector，构造时取一次：属性变化是高频路径，push_event 直接推入它，只经 recorder 读 is_recording。
var _collector: EventCollector


func _init(p_actor_id: String, recorder: BattleRecorder) -> void:
	actor_id = p_actor_id
	_recorder = recorder
	_collector = recorder.get_event_collector()


## 推送录像事件
##
## 走 recorder 注入的 event_collector（所属 world 的 collector），与 Action 主动 push 的事件共用同一个 buffer。
## 这样 callback(AbilityGranted/AttributeChanged/...)与 Action push(damage/...)
## 在调用栈穿插发生时,真实时序被自然保留 —— battle_procedure 帧末 flush()
## 一次性拿到的就是按发生顺序排列的事件流。
##
## is_recording guard:防 stop_recording 与 unsubscribe 之间的 callback 残响
## 把脏事件灌进 collector(此时 collector 仍在被复用,无录像消费)。
func push_event(event: Dictionary) -> void:
	if _recorder.is_recording:
		_collector.push(event)
