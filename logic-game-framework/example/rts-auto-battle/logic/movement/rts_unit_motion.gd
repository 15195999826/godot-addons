## RtsUnitMotion - 单位移动核心(0 A.D. CCmpUnitMotion 复刻;M7 引入)
##
## 0 A.D. `CCmpUnitMotion`(`CCmpUnitMotion.h` + `_System.cpp`)的 GDScript 复刻;替换现有
## `RtsNavAgent` + `RtsUnitSteering` 双类。把 long+short 双轨整合到统一 motion update tick。
##
## **本 milestone 拆 4 sub-phase**:
##   - **M7a (本文件)**:Path Storage — 字段 + 公开 API + path 双持(state-only,不 tick)
##   - M7b:Lifecycle — `tick()` 状态机 + `_failed_movements` 累计 + KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN 触发 long retry
##   - M7c:Movement + Obstruction sync — `_step()` per tick + `move_shape` + `set_unit_moving_flag`
##   - M7d:Activity 集成 — `RtsActivity` 子类全走 motion API + emit MoveFailed 事件
##
## **M7a 范围**:本文件仅持双 path + 暴露 move_to / move_to_entity / move_with_offset / stop /
## has_target / get_clearance / set_clearance。`tick()` / `_step()` / `_request_*` 等状态机
## API 留到 M7b/c 按 sub-phase 加。
##
## **核心数据**:
##   - `_move_request` — 当前移动请求(NONE / POINT / ENTITY / OFFSET)
##   - `_long_path` — 长路径,LongPath A* on navcell 给的 32 px 阶梯路径
##   - `_short_path` — 短路径,VertexPath visibility graph 给的任意角度直线段路径(贴 OBB / unit 边)
##   - `_expected_path_ticket` — 当前 active 寻路 ticket(同步阶段:发请求时 set,facade 返回后立刻 clear)
##
## **状态机契约**(M7b 启用):
##   - 跟随时优先消费 `_short_path`(若有);next short 走完触发 long advance(从 `_long_path` pop 一个 waypoint 作下一目标)
##   - `_failed_movements` 累 ≥ MAX_FAILED_MOVEMENTS(35) → activity 收到 MoveFailed 事件 abort
##   - `_follow_known_imperfect_path_countdown`(12 ticks)在 best-so-far short path 完后触发 long retry
##
## **API 调方**:M7c 起 RtsMotionComponent 在 actor 上挂 motion + 在 set_clearance 时同步
## obstr_mgr.unit_shape.clearance 字段(D2 不变量:clearance ≡ obstruction.radius)。M7a
## 阶段 set_clearance 仅更新 _clearance 字段,obstr 同步逻辑由 component 层负责(M7c 接)。
##
## **决策来源**:
##   - data-structures.md §8.3 (RtsUnitMotion 字段表)
##   - milestones/M7-unit-motion.md §M7a (sub-phase 拆分 + AC)
##   - 0 A.D. CCmpUnitMotion.h:130-260
class_name RtsUnitMotion
extends RefCounted


# ========== 常量 ==========

## 失败 movement 累计阈值;activity 收到 MoveFailed 事件后 abort(M7b 启用)。
const MAX_FAILED_MOVEMENTS: int = 35

## best-so-far short path 走完后等多少 tick 触发 long retry(M7b 启用)。
const KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN: int = 12


# ========== 字段:模板(unit_kind config 读) ==========

## Template walk speed (px/sec);从 unit_kind config 读。
var _template_walk_speed: float = 80.0

## Passability class config(`default` / `air`);从 unit_kind config 读。
var _pass_class: RtsPassabilityClassConfig = null


# ========== 字段:动态身体属性 ==========

## 单位避让半径(px)— 必须 ≡ obstruction shape.clearance(D2 不变量,M7c 由 component 同步)。
var _clearance: float = 14.0

## 当前 walk speed(可被 buff / slow 修改);初始 = _template_walk_speed。
var _walk_speed: float = 80.0

## 是否阻挡其他单位移动(false 时 push 不到 unit);死者 / spawn 中 / 飞行单位可设 false。
var _block_movement: bool = true


# ========== 字段:反馈计数 ==========

## 累计失败 movement 数;move_to / move_to_entity / stop 调用时清零(M7b 启用)。
var _failed_movements: int = 0

## best-so-far short path 走完后倒数 N tick 触发 long retry(M7b 启用)。
var _follow_known_imperfect_path_countdown: int = 0


# ========== 字段:当前请求 + 异步 ticket ==========

## 当前移动请求(NONE = 无目标 / POINT / ENTITY / OFFSET)。
var _move_request: RtsMoveRequest = null

## Active 寻路请求 ticket(同步阶段:发请求时 set,facade 返回后立刻 clear)。
var _expected_path_ticket: RtsMotionTicket = null


# ========== 字段:双 path 持有 ==========

## Long path — LongPath A* on navcell 给的 32 px 阶梯路径(全图)。
var _long_path: RtsWaypointPath = null

## Short path — VertexPath visibility graph 给的任意角度直线段路径(贴 OBB / unit 边)。
var _short_path: RtsWaypointPath = null


# ========== 初始化 ==========

func _init(p_pass_class: RtsPassabilityClassConfig = null, p_template_walk_speed: float = 80.0) -> void:
	_pass_class = p_pass_class
	_template_walk_speed = p_template_walk_speed
	_walk_speed = p_template_walk_speed
	# WHY: motion 创建后处于 NONE / 无 path 状态,等 activity / player command 调 move_to_* 触发请求
	_move_request = RtsMoveRequest.new()
	_long_path = RtsWaypointPath.new()
	_short_path = RtsWaypointPath.new()


# ========== 公开 API:移动请求 ==========

## 走到点附近;距离落入 [min_r, max_r]。重置 _failed_movements + 清双 path + 清 ticket。
func move_to(pos: Vector2, min_r: float, max_r: float) -> void:
	_move_request = RtsMoveRequest.to_point(pos, min_r, max_r)
	_reset_path_state()


## 接近 entity 到指定距离;eid 必须非空。重置 _failed_movements + 清双 path + 清 ticket。
func move_to_entity(eid: String, min_r: float, max_r: float) -> void:
	_move_request = RtsMoveRequest.to_entity(eid, min_r, max_r)
	_reset_path_state()


## 跟随 entity 保持 offset(本地坐标);M9 编队用,M7 阶段留接口。
## 重置 _failed_movements + 清双 path + 清 ticket。
func move_with_offset(eid: String, off: Vector2) -> void:
	_move_request = RtsMoveRequest.with_offset(eid, off)
	_reset_path_state()


## 取消当前请求 — _move_request 设 NONE,清双 path,清 ticket。activity stop / idle 调。
func stop() -> void:
	_move_request = RtsMoveRequest.new()
	_short_path.clear()
	_long_path.clear()
	if _expected_path_ticket != null:
		_expected_path_ticket.clear()
	# WHY: stop 不清 _failed_movements — activity 决定是否重新 move_to(届时由 move_to 清);
	# 跟 0ad CCmpUnitMotion 行为一致(StopMoving 不重置 m_FailedMovements)。


# ========== 公开 API:状态查询 ==========

## 当前是否有 active 移动请求(_move_request 非空且 type != NONE)。
func has_target() -> bool:
	return _move_request != null and _move_request.type != RtsMoveRequest.Type.NONE


## 当前 clearance(单位避让半径,px)。
func get_clearance() -> float:
	return _clearance


## 设 clearance — 仅更新 _clearance 字段;obstruction shape.clearance 同步由
## RtsMotionComponent 负责(M7c 接,D2 不变量:clearance ≡ obstruction.radius)。
##
## **不变量**:c > 0;0 / 负值 触发 assert_crash(motion 不应被设无效半径)。
func set_clearance(c: float) -> void:
	Log.assert_crash(c > 0.0, "RtsUnitMotion", "set_clearance: c must be > 0, got %f" % c)
	_clearance = c


# ========== 内部 helper ==========

## move_to_* 共用:清双 path、清 ticket、reset _failed_movements、reset countdown。
func _reset_path_state() -> void:
	_failed_movements = 0
	_follow_known_imperfect_path_countdown = 0
	_short_path.clear()
	_long_path.clear()
	if _expected_path_ticket != null:
		_expected_path_ticket.clear()
