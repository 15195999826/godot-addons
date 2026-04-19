## BattleProcedure - 战斗过程(抽象基类,非 Instance)
##
## 战斗是 *过程*, 不是 *实例*。WorldGameplayInstance 临时持有 BattleProcedure
## (`_active_battle`), 战斗结束即释放。Procedure 借用 world 里的 actor,
## tick 期间直接修改 actor 属性 = 直接写 world; 战斗结束后 world 已是终态。
##
## 基类只提供骨架(participants 管理、in_combat tag 钩子、recorder 生命周期),
## 具体 ATB / 回合 / 胜负判定由子类 override tick_once / should_end 实现。
##
## 详见 docs/design-notes/2026-04-19-world-as-single-instance.md
class_name BattleProcedure
extends RefCounted

const DEFAULT_TICK_INTERVAL: float = 100.0


# ========== 字段 ==========

var _world: WeakRef = null
var _participant_ids: Array[String] = []
var _ability_configs: Array = []
var _recorder: BattleRecorder = null
var _current_tick: int = 0
var _finished: bool = false
var _tick_interval: float = DEFAULT_TICK_INTERVAL


# ========== 初始化 ==========

func _init(world: WorldGameplayInstance, participants: Array[Actor], ability_configs: Array = []) -> void:
	if world != null:
		_world = weakref(world)
	for actor in participants:
		if actor != null:
			_participant_ids.append(actor.get_id())
	_ability_configs = ability_configs


# ========== 生命周期 ==========

## 开始战斗: 给参与者打 in_combat tag, 构造 recorder 并交给 _start_recorder() 钩子启动。
## 默认 _start_recorder() 调用 start_recording_events_only(), 子类可 override 以走
## 旧版 start_recording(actors, configs, map_config) 路径保持向后兼容。
func start() -> void:
	for pid in _participant_ids:
		_mark_in_combat(pid, true)
	_recorder = BattleRecorder.new({"tickInterval": int(_tick_interval)})
	_start_recorder()


## Recorder 启动钩子, 默认走 events-only 路径(无 initial_actors snapshot)。
## 子类可 override 以走旧版 start_recording() 保留 initial_actors / map_config。
func _start_recorder() -> void:
	if _recorder == null:
		return
	_recorder.start_recording_events_only()


## 推进一帧。基类仅 flush event + record, 子类覆盖做 ATB / timeline 推进等具体逻辑,
## super.tick_once() 或手动调 record_current_frame_events() 完成录像。
func tick_once() -> void:
	_current_tick += 1
	record_current_frame_events()


## 战斗是否应结束。默认看 _finished 标记, 子类按胜负条件 override。
func should_end() -> bool:
	return _finished


## 结束战斗: 清 in_combat tag, 停止 recorder, 返回 timeline。
## result 传给 recorder 作为战斗结果标签("battle_complete" / "left_win" / "timeout" 等)。
func finish(result: String = "battle_complete") -> Dictionary:
	for pid in _participant_ids:
		_mark_in_combat(pid, false)
	_finished = true
	if _recorder != null:
		return _recorder.stop_recording(result)
	return {}


# ========== 查询 ==========

func get_participant_ids() -> Array[String]:
	return _participant_ids


func get_current_tick() -> int:
	return _current_tick


func get_logic_time() -> float:
	return float(_current_tick) * _tick_interval


func get_recorder() -> BattleRecorder:
	return _recorder


func get_tick_interval() -> float:
	return _tick_interval


# ========== 受保护工具 ==========

## 收集当前帧 event_collector 累积的事件并写入录像。
func record_current_frame_events() -> void:
	var events := GameWorld.event_collector.flush()
	if _recorder != null:
		_recorder.record_frame(_current_tick, events)


## 标记结束; 子类判定胜负后调用以让 should_end() 返回 true。
func mark_finished() -> void:
	_finished = true


# ========== Virtual hooks ==========

## 标记/取消参与者的 in_combat 状态。基类默认 no-op(base Actor 无 tag 容器),
## 子类按 actor 实际 tag 容器 override。
func _mark_in_combat(_actor_id: String, _active: bool) -> void:
	pass


## 获取 world instance。world 已销毁时返回 null。
func _get_world() -> WorldGameplayInstance:
	if _world == null:
		return null
	return _world.get_ref() as WorldGameplayInstance


## 获取参与者 Actor。world 已销毁或 actor 不存在时返回 null。
func _get_actor(actor_id: String) -> Actor:
	var world := _get_world()
	if world == null:
		return null
	return world.get_actor(actor_id)
