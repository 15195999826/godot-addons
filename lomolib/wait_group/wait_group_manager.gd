## WaitGroup 全局管理器
##
## 负责创建和管理所有 WaitGroup 的生命周期
## 作为 AutoLoad 单例使用
extends Node

## 空 ID 常量
const EMPTY_ID: int = -1

## 下一个 WaitGroup ID
var _next_wg_id: int = 0

## 活跃的 WaitGroup 映射 (ID -> WaitGroup)
var _active_wait_groups: Dictionary = {}


## 创建新的 WaitGroup
## [param wg_name] WaitGroup 调试名称
## [return] 返回 [int, LomoWaitGroup] 元组（使用数组表示）
func create_wait_group(wg_name: StringName = &"") -> Array:
	var current_id := _next_wg_id
	_next_wg_id += 1

	var new_wg := LomoWaitGroup.new(current_id)
	new_wg.set_debug_name(wg_name)

	_active_wait_groups[current_id] = new_wg

	# 设置完成回调
	new_wg.completed.connect(_on_wait_group_completed)

	return [current_id, new_wg]


## 查找 WaitGroup
## [param wg_id] WaitGroup ID
## [return] 找到的 WaitGroup，未找到返回 null
func find_wait_group(wg_id: int) -> LomoWaitGroup:
	if _active_wait_groups.has(wg_id):
		return _active_wait_groups[wg_id]

	Log.warning("WaitGroupManager", "WaitGroup ID:%d 未找到" % wg_id)
	return null


## WaitGroup 完成时的回调
func _on_wait_group_completed(wg_id: int) -> void:
	if _active_wait_groups.has(wg_id):
		_active_wait_groups.erase(wg_id)
	else:
		Log.warning("WaitGroupManager", "WaitGroup ID:%d 已不在活跃列表中" % wg_id)


## 清理所有活跃的 WaitGroup
func cleanup_all_wait_groups() -> void:
	if _active_wait_groups.is_empty():
		return

	Log.warning("WaitGroupManager", "清理 %d 个活跃的 WaitGroup" % _active_wait_groups.size())

	# 1. 解绑所有完成回调
	for wg_id in _active_wait_groups:
		var wg: LomoWaitGroup = _active_wait_groups[wg_id]
		wg.completed.disconnect(_on_wait_group_completed)

	# 2. 强制完成所有 WaitGroup
	for wg_id in _active_wait_groups:
		var wg: LomoWaitGroup = _active_wait_groups[wg_id]
		Log.warning("WaitGroupManager", "强制结束 WaitGroup ID:%d, Name:%s" % [
			wg_id, wg.get_debug_name()
		])
		wg.set_cancelled()
		wg._counter = 1
		wg.done(&"ForceCleanup", false)

	# 3. 清空容器
	_active_wait_groups.clear()


## 节点退出时清理
func _exit_tree() -> void:
	cleanup_all_wait_groups()
