## RtsMotionComponent - 把 RtsUnitMotion 桥接到 RtsBattleActor + ObstructionManager (M7c 引入)
##
## 0 A.D. `CCmpUnitMotion` 是 actor 的一个 component;我们这里复刻:RtsUnitMotion 是纯算法 +
## 状态机(RefCounted 无 actor 依赖),RtsMotionComponent 是"这只 actor 用 motion + obstr_mgr
## 同步"的桥。component 挂在 actor.motion_component 字段(M7c 阶段 production 不创,smoke 创)。
##
## **职责**:
##   1. 每 tick 把 owner.position_2d 同步进 motion._position_2d(motion 内部 mirror)
##   2. 调 motion.tick(delta, world, facade) 推进状态机
##   3. tick 后把 motion.get_position_2d() 写回 owner.position_2d
##   4. 调 obstr_mgr.move_shape(actor.obstruction_tag, motion.get_position_2d()) 同步空间索引
##   5. set_unit_moving_flag(actor.obstruction_tag, was_moving != is_moving) 切换 FLAG_MOVING
##   6. set_clearance(c) 同步 motion._clearance + obstr_mgr.unit_shape.clearance
##      (D2 不变量:clearance ≡ obstruction_shape.radius)
##
## **不变量**:
##   - owner.motion_component == self 双向 wire(component 不持有不属于自己的 owner)
##   - motion 跟 component 1:1 持有(一个 component 一个 motion)
##
## **决策来源**:
##   - data-structures.md §8.4 (RtsMotionComponent 字段)
##   - milestones/M7-unit-motion.md §M7c.3 (clearance 同步 + obstr_mgr 桥接)
class_name RtsMotionComponent
extends RefCounted


# ========== 字段 ==========

## 持有的 actor(weak-ish,GDScript 没 weak ref;循环由 actor.motion_component = null 在
## actor unregister / death cleanup 打破)。
var owner_actor: RtsBattleActor = null

## 单位 motion 算法 + 状态机(RefCounted 无 actor 依赖)。
var motion: RtsUnitMotion = null

## 上一 tick 末的"是否在动"标记 — 用于检测 was_moving != is_moving 切换 FLAG_MOVING(避免
## 每 tick 都调 set_unit_moving_flag)。
var _was_moving: bool = false


# ========== 初始化 ==========

func _init(p_owner: RtsBattleActor, p_motion: RtsUnitMotion) -> void:
	Log.assert_crash(p_owner != null, "RtsMotionComponent", "_init: owner is null")
	Log.assert_crash(p_motion != null, "RtsMotionComponent", "_init: motion is null")
	owner_actor = p_owner
	motion = p_motion
	# motion 初始位置 = owner 当前位置
	motion.set_position_2d(p_owner.position_2d)


# ========== Tick(M7c.3) ==========

## 桥 actor ↔ motion ↔ obstr_mgr;procedure._world_tick 在 step 2 内对每个 motion-bearing actor
## 按 (type, spawn_seq) 排序后调用。
##
## **流程**:
##   1. motion.set_position_2d(owner.position_2d)— 同步入(actor 是上 tick 末的真相)
##   2. motion.tick(delta, world, facade)— 推进状态机
##   3. owner.position_2d = motion.get_position_2d()— 写回(motion._step 已渐进)
##   4. obstr_mgr.move_shape(owner.obstruction_tag, owner.position_2d)
##   5. set_unit_moving_flag — was_moving != is_moving 切换
##
## **world == null** smoke 兼容:obstr_mgr 同步路径 noop(world 没 obstruction_manager 字段)。
func tick(delta: float, world: Variant, facade: RtsPathfinderFacade) -> void:
	# Step 1: 同步 owner → motion
	motion.set_position_2d(owner_actor.position_2d)

	# Step 2: 推进 motion 状态机
	motion.tick(delta, world, facade)

	# Step 3: 写回 motion → owner
	var new_pos: Vector2 = motion.get_position_2d()
	owner_actor.position_2d = new_pos

	# Step 4 + 5: 同步 obstr_mgr(若有)
	if world == null:
		return
	if not world.has_method("get"):
		return
	var obstr_mgr = world.get("obstruction_manager")
	if obstr_mgr == null:
		return
	if owner_actor.obstruction_tag == 0:
		# 未注册 unit shape — 静默跳过(老 actor 未迁移时);M2.5 起 spawner 应注册
		return

	# Step 4: move_shape 同步 obstr center 到新位置
	obstr_mgr.move_shape(owner_actor.obstruction_tag, new_pos)

	# Step 5: FLAG_MOVING 切换(was_moving != is_moving 才调)
	# motion has_target + short_path 非空 = 还在走;否则 = 不动
	var is_moving: bool = motion.has_target() and not motion._short_path.is_empty()
	if _was_moving != is_moving:
		obstr_mgr.set_unit_moving_flag(owner_actor.obstruction_tag, is_moving)
		_was_moving = is_moving

	# Step 6 (M7d): MoveFailed event 反馈给 activity — motion 累达 35 失败次数 abort 时触发
	_emit_motion_failed_if_needed()


# ========== MoveFailed event 反馈(M7d) ==========

## 检查 motion 是否上 tick abort,若是则 emit "rts_motion_move_failed" event 给 owner_actor。
##
## **触发条件**:motion._failed_movements 累达 35 → motion._abort_due_to_failure() set _just_failed
## flag + stop()。本 component tick 末调此函数 emit event 给 actor → activity 监听处理。
##
## **不变量**:同一次 abort 只 emit 一次(consume_just_failed 清 flag);motion.move_to_*
## 重置 _failed_movements 时 _reset_path_state 也清 _just_failed,不会有 stale flag。
##
## **GameWorld.event_collector null 兼容**:smoke 不 start procedure(单元测试 mock world)时
## event_collector 未初始化,跳过 emit;motion abort 行为本身不依赖 event。
func _emit_motion_failed_if_needed() -> void:
	if not motion.has_just_failed():
		return
	motion.consume_just_failed()
	if GameWorld == null or GameWorld.event_collector == null:
		return
	var move_request_kind: int = RtsMoveRequest.Type.NONE
	if motion._move_request != null:
		move_request_kind = motion._move_request.type
	GameWorld.event_collector.push(RtsBattleEvents.make_motion_move_failed(
		owner_actor.get_id(),
		motion._failed_movements,
		move_request_kind,
	))


# ========== Clearance 同步(D2 不变量) ==========

## set clearance — 更新 motion + obstr_mgr.unit_shape.clearance(D2 不变量:
## clearance ≡ obstruction_shape.radius;两者必须同步)。
##
## obstr_mgr null / unit_shape 不存在时仅更新 motion(smoke 不接 obstr_mgr 时合法)。
func set_clearance(c: float, obstr_mgr: RtsObstructionManager = null) -> void:
	motion.set_clearance(c)
	if obstr_mgr == null or owner_actor.obstruction_tag == 0:
		return
	var shape := obstr_mgr.get_shape(owner_actor.obstruction_tag)
	if shape == null:
		return
	if shape is RtsObstructionShapeUnit:
		(shape as RtsObstructionShapeUnit).clearance = c
		# WHY: spatial_index radius 不更新(运行时 unit clearance 罕见变化,M9 加完整逻辑;
		# spec §M7c §M1 决策 A — 接受少数边角 query 误差 ≤ 1 cell)
