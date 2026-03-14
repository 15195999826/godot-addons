## WaitGroup - 多任务同步工具
##
## 类似 Go 的 WaitGroup，用于等待多个异步任务完成
## 注意：非线程安全，仅适用于主线程任务同步
class_name LomoWaitGroup
extends RefCounted

## 所有任务完成时触发（传递 WaitGroup ID）
signal completed(wg_id: int)

## WaitGroup 唯一 ID
var id: int = -1

## 调试名称
var debug_name: StringName = &""

## 任务计数器
var _counter: int = 0

## 是否已取消
var _is_cancelled: bool = false

## 待执行的回调函数
var _pending_callback: Callable


func _init(wg_id: int) -> void:
	id = wg_id


## 设置调试名称
func set_debug_name(name: StringName) -> void:
	debug_name = name


## 获取调试名称
func get_debug_name() -> StringName:
	return debug_name


## 增加等待计数
## [param delta] 增加的数量（默认为 1）
func add(delta: int = 1) -> void:
	_counter += delta


## 标记一个任务完成
## [param task_name] 任务名称（用于调试）
## [param enable_log] 是否打印日志
func done(task_name: StringName = &"", enable_log: bool = true) -> void:
	if enable_log:
		Log.debug("WaitGroup", "[%s] Done ID:%d, Task:%s, Counter:%d" % [
			debug_name, id, task_name, _counter
		])

	_counter -= 1

	if _counter == 0:
		# 触发完成事件
		completed.emit(id)

		# 执行待处理的回调
		if _pending_callback.is_valid() and not _is_cancelled:
			_pending_callback.call()


## 等待所有任务完成（协程方式）
## [br]用法: [code]await wg.wait()[/code]
func wait() -> void:
	if _counter <= 0:
		return

	await completed


## 所有任务完成后执行回调（链式调用）
## [br]用法: [code]wg.next(func(): print("All done!"))[/code]
## [param callback] 完成后执行的函数
func next(callback: Callable) -> void:
	if _counter <= 0:
		if not _is_cancelled:
			callback.call()
		return

	_pending_callback = callback
	await completed


## 标记为已取消（不会执行 next 回调）
func set_cancelled() -> void:
	_is_cancelled = true


## 获取当前计数器值
func get_counter() -> int:
	return _counter


## 是否已完成
func is_completed() -> bool:
	return _counter <= 0
