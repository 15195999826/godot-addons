## RtsWaypointPath - 反向存储的 waypoint 列表 (M5)
##
## 0 A.D. `WaypointPath` (helpers/Pathfinding.h:127) 的 GDScript 复刻。**反向存储**:
##   - `waypoints[0]` = 终点(goal cell 中心)— 最后被消耗
##   - `waypoints[size-1]` = next step(start 旁边的下一个 navcell 中心)— 最先被消耗
##
## 调方约定: 每帧 `back()` 看下一个目标点,接近后 `pop_back()` 弹出消费。空 path = "已到目的"
## 或 "找不到路径"(语义由调方区分,facade 找不到时返回空 path 不报错)。
##
## **为什么反向存储**: 0 A.D. 的设计 — `pop_back` 是 PackedVector2Array 的 O(1) 操作
## (Godot 4.6: `remove_at(size-1)` 不需 memmove);`pop_front` 是 O(N)。同样道理我们这里
## 走反向存储 + back()/pop_back(),保持 hot path 都是 O(1)。
##
## **不变量**:
##   - waypoints 从 push_back 顺序填入,reconstruct 时按"goal → start"方向遍历
##   - 空 path 调方不应 back() / pop_back(assert_crash)
##
## **决策来源**: data-structures.md §6.2 (WaypointPath 反向存储语义)
class_name RtsWaypointPath
extends RefCounted


# ========== 字段 ==========

## Waypoint 列表(world 坐标);反向存储语义见类 docstring。
var waypoints: PackedVector2Array = PackedVector2Array()


# ========== 初始化 ==========

func _init() -> void:
	waypoints = PackedVector2Array()


# ========== 查询 ==========

func size() -> int:
	return waypoints.size()


func is_empty() -> bool:
	return waypoints.is_empty()


## 看下一个目标点(不消费);空 path 时 assert_crash。
func back() -> Vector2:
	Log.assert_crash(not waypoints.is_empty(), "RtsWaypointPath", "back() called on empty path")
	return waypoints[waypoints.size() - 1]


## 弹出下一个目标点(消费);空 path 时 assert_crash。
func pop_back() -> Vector2:
	Log.assert_crash(not waypoints.is_empty(), "RtsWaypointPath", "pop_back() called on empty path")
	var v: Vector2 = waypoints[waypoints.size() - 1]
	waypoints.remove_at(waypoints.size() - 1)
	return v


# ========== 写 ==========

## 追加 waypoint;reconstruct 时按 "goal → start" 顺序填,所以最先填的 goal 落在 [0],
## 最后填的 next-step 落在 [size-1] = back()。
func push_back(v: Vector2) -> void:
	waypoints.append(v)


func clear() -> void:
	waypoints = PackedVector2Array()
