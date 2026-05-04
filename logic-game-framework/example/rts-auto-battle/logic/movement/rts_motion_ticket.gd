## RtsMotionTicket - 异步寻路 ticket 跟踪 (M7 引入)
##
## 0 A.D. `CCmpUnitMotion::Ticket` (`CCmpUnitMotion.h:230-240`) 的 GDScript 复刻。M7 阶段
## facade 仍是同步寻路,但 motion 状态机里 `_expected_path_ticket` 字段保留 — 标记"我已发出
## 一次寻路请求,在结果回来前不重发"。
##
## **作用**:
##   - 同步寻路实现下,ticket 是"是否还有 active 请求"的开关(0 = 无,> 0 = 有)
##   - M7+ 改 async 时 facade 把 ticket 跟回调 path 配对,避免新请求覆盖旧请求结果
##
## **type 区分**:LONG_PATH / SHORT_PATH 两类 — motion 状态机 `_path_update_needed` 用
## type 决定下一步触发哪个 facade API。
##
## **同步阶段使用**:
##   - motion `_request_long_path` 时 `new(LONG_PATH, next_seq)` 标 active
##   - facade 同步调返回路径后立刻 `clear()` 标 inactive(下 tick 可重发)
##   - M7a 阶段仅写 data class,真实 ticket 分配在 M7b motion 状态机内做
##
## **决策来源**:
##   - data-structures.md §8.2 (Ticket 字段)
##   - milestones/M7-unit-motion.md §M7a.1
class_name RtsMotionTicket
extends RefCounted


# ========== 类型 ==========

enum Type {
	SHORT_PATH,  ## 短路径(VertexPath visibility graph)
	LONG_PATH,   ## 长路径(LongPath A* on navcell)
}


# ========== 字段 ==========

## 单调递增 id;0 = 无 active 请求,> 0 = 有。
var ticket: int = 0

## 请求类型(决定 motion 状态机收到 path 后该写 _short_path 还是 _long_path)。
var type: int = Type.SHORT_PATH


# ========== 初始化 ==========

func _init(p_type: int = Type.SHORT_PATH, p_ticket: int = 0) -> void:
	type = p_type
	ticket = p_ticket


# ========== 查询 / 写 ==========

## 当前是否有 active 请求(ticket > 0)。
func is_active() -> bool:
	return ticket > 0


## 标记请求已结束(同步阶段:facade 返回 path 后立刻调);ticket 归 0。
func clear() -> void:
	ticket = 0
