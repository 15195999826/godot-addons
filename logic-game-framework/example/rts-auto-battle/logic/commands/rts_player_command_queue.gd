## RtsPlayerCommandQueue - 玩家命令队列 (P2.6)
##
## 持 pending RtsPlayerCommand 列表, 按 tick_stamp 排序; procedure 每 tick step 2 调
## apply_due(procedure, world, current_tick) 把 tick_stamp ≤ current_tick 的命令应用,
## 已应用的 (无论成功失败) 都从 pending 移除, 写入 history (给 replay / UI 反馈)。
##
## 不变量:
##   - apply_due 内迭代顺序 = tick_stamp 升序; 同 tick 的命令按 enqueue 顺序 (insertion-order)
##     → 决定性: 同 seed + 同 player_commands 序列 → 同 apply 顺序 → 同事件流
##   - history 持续 append, 不清空; 战斗结束 procedure.finish 后调方可读全部历史
##   - failed 命令进 history.failed_commands (含失败原因)
##
## 决策来源: phase-2-core-systems.md §P2.6 "RtsPlayerCommandQueue (持 pending commands,
## 按 tick stamp 应用)"
class_name RtsPlayerCommandQueue
extends RefCounted


# ========== 字段 ==========

## 待应用命令; insertion-order; apply_due 时按 tick_stamp 取出
var _pending: Array[RtsPlayerCommand] = []

## 已应用历史 (含成功 / 失败); apply_due 时 append
## 单个 entry: { "command": RtsPlayerCommand, "result": Dictionary, "applied_tick": int }
var _history: Array[Dictionary] = []


# ========== Enqueue ==========

## 把命令加入队列。允许 tick_stamp 早于当前 tick — apply_due 会立即应用 (overdue 命令也算 due)。
##
## 同 tick_stamp 的多条命令保留 enqueue 顺序 (决定性来源)。
func enqueue(command: RtsPlayerCommand) -> void:
	if command == null:
		return
	_pending.append(command)


# ========== Apply ==========

## 应用所有 tick_stamp ≤ current_tick 的命令; 已应用 (含失败) 从 pending 移除。
## 返回 result list (调方可写入 procedure 录像 player_commands 字段)。
##
## 决定性: 取出顺序 = tick_stamp 升序; 同 tick 取 insertion-order 不破。
func apply_due(procedure, world, current_tick: int) -> Array[Dictionary]:
	var due: Array[RtsPlayerCommand] = []
	var remaining: Array[RtsPlayerCommand] = []
	for cmd in _pending:
		if cmd.tick_stamp <= current_tick:
			due.append(cmd)
		else:
			remaining.append(cmd)
	_pending = remaining

	# 同 tick 内保 enqueue 顺序; 跨 tick 按 tick_stamp 升序 (stable sort)
	due.sort_custom(func(a, b): return a.tick_stamp < b.tick_stamp)

	var results: Array[Dictionary] = []
	for cmd in due:
		var result: Dictionary = cmd.apply(procedure, world)
		_history.append({
			"command": cmd,
			"result": result,
			"applied_tick": current_tick,
		})
		results.append({
			"command": cmd.serialize(),
			"result": result,
			"applied_tick": current_tick,
		})
	return results


# ========== 查询 ==========

func pending_count() -> int:
	return _pending.size()


func history_count() -> int:
	return _history.size()


## 仅返回失败命令的 history entry — replay 检查 / smoke debug 用。
func get_failed_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _history:
		var entry_result: Dictionary = entry.get("result", {})
		if not entry_result.get("success", false):
			result.append(entry)
	return result


## 全部 history (成功 + 失败) — replay 重建 player_commands 流式录像用。
func get_history() -> Array[Dictionary]:
	return _history.duplicate()


## 清空 history (单测时复用 queue 实例)
func clear_history() -> void:
	_history.clear()
