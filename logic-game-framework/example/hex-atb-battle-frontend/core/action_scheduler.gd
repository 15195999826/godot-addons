## ActionScheduler - 动作调度器
##
## 管理 VisualAction 的生命周期和进度更新。
## 采用简化的 parallel 模式：所有动作入队后立即并行执行。
##
## 设计特点：
## - 所有动作并行执行，无阻塞
## - 支持 delay 延迟执行
## - 自动清理已完成的动作
class_name FrontendActionScheduler
extends RefCounted


# ========== 活跃动作数据结构 ==========

## 活跃动作（运行时状态）
class ActiveAction:
	## 唯一标识
	var id: String
	## 原始动作定义
	var action: FrontendVisualAction
	## 已执行时间（毫秒）
	var elapsed: float
	## 执行进度（0~1）
	var progress: float
	## 是否处于延迟等待中
	var is_delaying: bool
	
	func _init(p_id: String, p_action: FrontendVisualAction) -> void:
		id = p_id
		action = p_action
		elapsed = 0.0
		progress = 0.0
		is_delaying = p_action.delay > 0.0


# ========== Tick 结果数据结构 ==========

## Scheduler tick 结果
class TickResult:
	## 当前活跃的动作（带进度）
	var active_actions: Array[ActiveAction] = []
	## 本帧完成的动作
	var completed_this_tick: Array[ActiveAction] = []
	## 是否有变化（用于优化渲染）
	var has_changes: bool = false


# ========== 属性 ==========

## 活跃动作 Map（id -> ActiveAction）
var _active: Dictionary = {}

## 动作 ID 计数器
var _next_id: int = 0


# ========== 公共方法 ==========

## 添加动作到调度器
## 所有动作立即并行执行（考虑 delay）
func enqueue(actions: Array[FrontendVisualAction]) -> void:
	for visual_action: FrontendVisualAction in actions:
		var id := "action_%d" % _next_id
		_next_id += 1
		
		var active_action := ActiveAction.new(id, visual_action)
		_active[id] = active_action


## 每帧更新
## 更新所有活跃动作的进度，清理已完成的动作
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
	
	# 清理已完成的动作
	for id in completed_ids:
		_active.erase(id)
	
	# 收集活跃动作
	for id in _active.keys():
		result.active_actions.append(_active[id])
	
	result.has_changes = result.has_changes or result.completed_this_tick.size() > 0
	
	return result


## 获取当前活跃动作
func get_active_actions() -> Array[ActiveAction]:
	var actions: Array[ActiveAction] = []
	for id: String in _active.keys():
		actions.append(_active[id] as ActiveAction)
	return actions


## 取消所有动作
## 用于重置播放器状态
func cancel_all() -> void:
	_active.clear()


## 获取当前动作数量
func get_action_count() -> int:
	return _active.size()
