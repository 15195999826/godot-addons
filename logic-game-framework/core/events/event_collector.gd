## EventCollector - 事件收集器
##
## ========== 核心职责 ==========
##
## 在逻辑执行过程中收集所有产生的事件。
## 收集的事件仅供录像/表演层消费，**不参与逻辑状态同步**。
##
## ========== 设计原则 ==========
##
## Action 内的状态变更是原子操作：
## - push(event) 只是记录事件，不触发任何状态变更
## - 状态变更（如 modify_hp）由 Action 自己完成
## - flush() 在帧结束时调用，将事件交给录像/表演层
##
## ========== 获取事件的两种方式 ==========
##
## | 方法       | 行为             | 适用场景                 |
## |------------|------------------|--------------------------|
## | collect()  | 返回副本，不清空 | 调试、日志、只读查询     |
## | flush()    | 返回原数组，清空 | 表演层消费、帧结束处理   |
##
## ========== 使用示例 ==========
##
## @example 在 Action 中发出事件
## ```gdscript
## var event := BattleEvents.DamageEvent.create(target.id, damage, damage_type, source_id)
## var damage_event: Dictionary = ctx.event_collector.push(event.to_dict())
## 
## # 立即应用状态（原子操作）
## target_actor.modify_hp(-damage)
## ```
##
## @example 在 tick 结束时收集事件
## ```gdscript
## # 收集本帧事件（仅用于录像，状态已在 Action 内同步）
## var frame_events: Array[Dictionary] = GameWorld.event_collector.flush()
## 
## # 录像记录
## if recorder != null:
##     recorder.record_frame(tick_count, frame_events)
## ```
class_name EventCollector
extends RefCounted

var _events: Array[Dictionary] = []

func push(event_dict: Dictionary) -> Dictionary:
	_events.append(event_dict)
	return event_dict

func collect() -> Array[Dictionary]:
	return _events.duplicate(true)

func flush() -> Array[Dictionary]:
	var events := _events
	_events = []
	return events

func clear() -> void:
	_events = []

func get_count() -> int:
	return _events.size()

func has_events() -> bool:
	return not _events.is_empty()

func filter_by_kind(kind: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for event_dict in _events:
		if event_dict.get("kind", "") == kind:
			filtered.append(event_dict)
	return filtered

func merge(other: EventCollector) -> void:
	_events.append_array(other._events)
