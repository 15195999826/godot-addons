## RtsBattleLogger - RTS 战斗事件捕获器
##
## 订阅 EventCollector(实际上是 procedure record_current_frame_events 走过的事件), 把
## attack_resolved / actor_died 事件累计到内存数组里, 给 smoke 在战斗结束后做兵种行为断言。
##
## 与 hex 例子的 HexBattleLogger 不同, 这里不写文件 / 不做实时 console 输出 (M0 仅断言用)。
class_name RtsBattleLogger
extends RefCounted


# ========== 字段 ==========

## 已记录的 attack_resolved 事件 list(每次 attack 一条)
var attack_events: Array[Dictionary] = []

## 已记录的 actor_died 事件 list
var death_events: Array[Dictionary] = []


# ========== 收集 ==========

## 接收一帧 events(由 procedure 在 record_current_frame_events 之前 mirror 过来)。
## 不消费 / 不修改原数组, 只复制感兴趣的事件。
func ingest_frame_events(events: Array[Dictionary]) -> void:
	for event in events:
		var kind: String = event.get("kind", "")
		if kind == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			attack_events.append(event)
		elif kind == RtsBattleEvents.ACTOR_DIED_EVENT:
			death_events.append(event)


# ========== 查询 ==========

## 抽 unit_class 对应的所有 attack 距离
func get_attack_distances_for_class(unit_class_int: int) -> Array[float]:
	var result: Array[float] = []
	for event in attack_events:
		if int(event.get("attacker_unit_class", -1)) == unit_class_int:
			result.append(float(event.get("distance", 0.0)))
	return result


func get_attack_count() -> int:
	return attack_events.size()


func get_death_count() -> int:
	return death_events.size()


## 抽某个 actor 的所有 attack 事件(按 attacker_id 过滤)
func get_attacks_by_actor(actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in attack_events:
		if event.get("source_actor_id", "") == actor_id:
			result.append(event)
	return result
