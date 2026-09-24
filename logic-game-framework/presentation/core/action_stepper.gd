## ActionStepper - 步进器
##
## 管理卡片（VisualAction）的生命周期和进度：入队后所有卡片并行推进，各自按 delay / duration
## 走 0→1，完成即出表。它只管「什么时候走到什么进度」，不管「执行什么」（那是 VisualUpdater 的事）。
##
## 设计特点：
## - 所有卡片并行执行，无阻塞
## - 支持 delay 延迟执行
## - 自动清理已完成的卡片
## - live 场景按 actor 撤销在飞卡片（cancel_for_actor，不补发完成）/ 查在飞（has_actor_action）
class_name ActionStepper
extends RefCounted


# ========== 活跃卡片数据结构 ==========

## 活跃卡片（运行时状态）
class ActiveAction:
	## 唯一标识
	var id: String
	## 原始卡片定义
	var action: VisualAction
	## 已执行时间（毫秒）
	var elapsed: float
	## 执行进度（0~1）
	var progress: float
	## 是否处于延迟等待中
	var is_delaying: bool

	func _init(p_id: String, p_action: VisualAction) -> void:
		id = p_id
		action = p_action
		elapsed = 0.0
		progress = 0.0
		is_delaying = p_action.delay > 0.0


# ========== Tick 结果数据结构 ==========

## tick 结果
class TickResult:
	## 当前活跃的卡片（带进度）
	var active_actions: Array[ActiveAction] = []
	## 本帧完成的卡片
	var completed_this_tick: Array[ActiveAction] = []
	## 是否有变化（用于优化渲染）
	var has_changes: bool = false


# ========== 属性 ==========

## 活跃卡片 Map（id -> ActiveAction）
var _active: Dictionary = {}

## 卡片 ID 计数器
var _next_id: int = 0


# ========== 公共方法 ==========

## 入队卡片
## 所有卡片立即并行执行（考虑 delay）
func enqueue(actions: Array[VisualAction]) -> void:
	for visual_action: VisualAction in actions:
		var id := "action_%d" % _next_id
		_next_id += 1

		var active_action := ActiveAction.new(id, visual_action)
		_active[id] = active_action


## 每帧更新
## 更新所有活跃卡片的进度，清理已完成的卡片
func tick(delta_ms: float) -> TickResult:
	var result := TickResult.new()
	var completed_ids: Array[String] = []

	for id in _active.keys():
		var active_action: ActiveAction = _active[id]
		var action := active_action.action
		var delay := action.delay

		# 更新已执行时间
		active_action.elapsed += delta_ms

		# 检查是否还在延迟中
		if active_action.elapsed < delay:
			active_action.is_delaying = true
			active_action.progress = 0.0
			result.has_changes = true
			continue

		# 延迟结束，开始执行
		active_action.is_delaying = false

		# 计算实际执行时间（减去延迟）
		var effective_elapsed := active_action.elapsed - delay

		# 计算进度（0~1）
		if action.duration > 0.0:
			active_action.progress = minf(1.0, effective_elapsed / action.duration)
		else:
			active_action.progress = 1.0

		result.has_changes = true

		# 检查是否完成
		if effective_elapsed >= action.duration:
			active_action.progress = 1.0  # 确保最终进度为 1
			result.completed_this_tick.append(active_action)
			completed_ids.append(id)

	# 清理已完成的卡片
	for id in completed_ids:
		_active.erase(id)

	# 收集活跃卡片
	for id in _active.keys():
		result.active_actions.append(_active[id])

	result.has_changes = result.has_changes or result.completed_this_tick.size() > 0

	return result


## 获取当前活跃卡片
func get_active_actions() -> Array[ActiveAction]:
	var actions: Array[ActiveAction] = []
	for id: String in _active.keys():
		actions.append(_active[id] as ActiveAction)
	return actions


## 取消所有卡片
## 用于重置播放器状态
func cancel_all() -> void:
	_active.clear()


## 撤掉某个 actor 的全部在飞卡片（含延迟中的），不补发完成。
## live 场景 latest-wins：新一步移动入队前先撤上一步
func cancel_for_actor(actor_id: String) -> void:
	var ids: Array[String] = []
	for id: String in _active.keys():
		if (_active[id] as ActiveAction).action.actor_id == actor_id:
			ids.append(id)
	for id in ids:
		_active.erase(id)


## 该 actor 是否有在飞卡片（live 场景「还在走格吗」）
func has_actor_action(actor_id: String) -> bool:
	for id: String in _active.keys():
		if (_active[id] as ActiveAction).action.actor_id == actor_id:
			return true
	return false


## 获取当前卡片数量
func get_action_count() -> int:
	return _active.size()
