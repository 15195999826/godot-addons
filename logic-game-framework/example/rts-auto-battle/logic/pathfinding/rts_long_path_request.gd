## RtsLongPathRequest - LongPath 寻路请求 (M5)
##
## 0 A.D. `LongPathRequest` (helpers/Pathfinding.h:213) 的 GDScript 复刻。把寻路调用的入参
## 打包成单一 RefCounted 对象,M5 阶段还是同步调用,但 data class 提前对齐 M7+ async 时
## 直接接 BattleProcedure command queue。
##
## **字段语义**:
##   - `ticket` 0 = 无效 / 未注册;> 0 = caller 跟踪用的递增 id(M7 async 时给 notify 配对);
##     M5 阶段所有 caller 暂传 0 即可
##   - `start` 起点世界坐标(像素);facade 内部转 navcell index
##   - `goal` RtsPathGoal POINT/CIRCLE/SQUARE,facade 调 make_goal_reachable canonicalize
##     之后 LongPathfinder 期望 POINT
##   - `pass_mask` `RtsPassabilityClassRegistry.get_mask("default" | "air")` 单 mask
##     (跨 class 同时寻路是 M7 motion 的事,M5 一次一个 class)
##   - `notify_entity` actor id;M7 async 时 path computed 后 publish 给该 actor;M5 同步
##     不用,留字段
##
## **决策来源**: data-structures.md §6.1 (LongPathRequest 字段表)
class_name RtsLongPathRequest
extends RefCounted


# ========== 字段 ==========

## Caller 跟踪用的递增 id;M5 同步阶段保留字段不消费,M7 async 时 facade 分配。
var ticket: int = 0

## 起点世界坐标(像素)。
var start: Vector2 = Vector2.ZERO

## 目标 PathGoal(POINT 推荐;facade 调 make_goal_reachable 后总是 POINT)。
var goal: RtsPathGoal = null

## 单 passability class mask(`default` 或 `air`)。
var pass_mask: int = 0

## Notify entity actor id;M5 同步阶段保留字段,M7 async 时 facade 用它 publish "path_computed"。
var notify_entity: String = ""


# ========== 初始化 ==========

func _init(
	p_start: Vector2 = Vector2.ZERO,
	p_goal: RtsPathGoal = null,
	p_pass_mask: int = 0,
	p_notify_entity: String = "",
	p_ticket: int = 0,
) -> void:
	start = p_start
	goal = p_goal
	pass_mask = p_pass_mask
	notify_entity = p_notify_entity
	ticket = p_ticket
