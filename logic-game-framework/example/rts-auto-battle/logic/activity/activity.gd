## RtsActivity - 单位行为意图基类 (P2.1, OpenRA 风)
##
## 替代 Phase 1 的 string FSM Intent ({action: "approach"|"attack"|"idle"})。
## 一个 Activity 表示单位本帧及未来若干帧的"意图":
##   - 生命周期: QUEUED → ACTIVE → DONE; cancel 进 CANCELING 后下次 advance 转 DONE
##   - child_activity: 嵌套子任务 (parent.tick 先跑, 决定是否 push/cancel child)
##   - next_activity: 链式队列, 当前 DONE 后接管
##
## 推进通过 static func advance(head, actor, world, dt) -> RtsActivity 调用,
## 返回 head 链中第一个未 DONE 的 activity (或 null)。
## controller 用法:
##   current_activity = RtsActivity.advance(current_activity, actor, world, dt)
##
## 钩子顺序 (per-tick):
##   - 父 tick 先跑 (supervisor 模式: 决定 child 创建/取消)
##   - 然后递归 advance child
##   - parent.tick 返回 false → on_last_run + DONE → 切到 next
##
## 注: 这与 OpenRA 子先父后顺序反过来。RTS 主控逻辑 (AttackActivity 决定 push MoveTo child)
## 走 supervisor 模式更直观。
##
## 决策来源: phase-2-core-systems.md P2.1
class_name RtsActivity
extends RefCounted


# ========== Nav refresh 限频 (子类共享) ==========

## Nav target 刷新最小间隔(秒). attack / harvest / return-and-drop Activity 共用 —
## target 移动 > 2px 也立即刷(避免追不上跑动目标; Phase 1 controller 同值)。
const NAV_REFRESH_INTERVAL: float = 0.2

## 距离上次 _refresh_nav_target 累积时间(秒). 子类 tick 起手 += dt 即可.
var _time_since_nav_refresh: float = 0.0

## 上一次 set_target 位置 (跳过 < 2px 抖动)
var _last_set_target: Vector2 = Vector2.INF


# ========== State ==========

enum State {
	QUEUED,
	ACTIVE,
	CANCELING,
	DONE,
}


# ========== 链式结构 ==========

## 嵌套子任务 (parent 持引用, parent.tick 决定 push/cancel)。
var child_activity: RtsActivity = null

## 链式队列下一个 activity (当前 DONE 后接管)。
var next_activity: RtsActivity = null

## 当前生命周期状态。
var state: int = State.QUEUED


# ========== 钩子 (子类 override) ==========

## state QUEUED → ACTIVE 时调用一次。子类设置初始 nav target / 标志。
func on_first_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	pass


## 每 tick 推进。
##   返回 true → 继续此 activity;
##   返回 false → 本 activity 转 DONE, 链上 next 接管。
func tick(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance, _dt: float) -> bool:
	return false


## state 转 DONE 之前调用一次。子类释放 nav 资源 / 清 actor 引用字段。
##
## 注: cancel 路径下 on_last_run 也会调; 子类需保证幂等 (即使 on_first_run 没跑过也能安全 cleanup)。
func on_last_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	pass


## 注入 runtime 依赖 (e.g. 当前单位的 nav agent)。
##
## 子类持 nav_agent 引用时 override + 调 super.bind_runtime, 让 child / next 也得到。
## 已绑过的 activity 再次 bind 是幂等无副作用的 (覆盖同一引用)。
func bind_runtime(nav_agent: RtsNavAgent) -> void:
	if child_activity != null:
		child_activity.bind_runtime(nav_agent)
	if next_activity != null:
		next_activity.bind_runtime(nav_agent)


## 是否本帧想触发 basic attack。
##
## 默认 false; AttackActivity override 为 true (in-range 时)。
## parent activity 默认转发到 child (AttackMoveActivity 套 AttackActivity 时用)。
func wants_to_attack() -> bool:
	if child_activity != null and not child_activity.is_done():
		return child_activity.wants_to_attack()
	return false


## 统一意图标签 ("idle" / "move" / "approach" / "attack" / "attack_move"),
## 服务 smoke / debug; 不在生产 path 上做 string 决策 (那是 Phase 1 string FSM 的反模式)。
func get_intent_label() -> String:
	if child_activity != null and not child_activity.is_done():
		return child_activity.get_intent_label()
	return "idle"


## 与另一 activity 是否"语义等价" (同类 + 主参数相近)。
##
## controller.tick 用此判断 strategy 提议是否值得替换 current — 等价则复用,
## 避免每 tick 重建 nav 状态。
##
## 默认 false (子类必须 override 才有"复用"语义)。
func is_equivalent_to(_other: RtsActivity) -> bool:
	return false


# ========== 状态查询 ==========

func is_done() -> bool:
	return state == State.DONE


func is_canceling() -> bool:
	return state == State.CANCELING


# ========== Nav refresh 共享 helper (子类可调) ==========

## 是否应该刷新 nav target:
##   - 距离上次刷新 ≥ NAV_REFRESH_INTERVAL, 或
##   - 目标位置发生显著变化 (>2 px) — 即使在限频窗口内也立即刷
func _should_refresh_nav(target_pos: Vector2) -> bool:
	if _time_since_nav_refresh >= NAV_REFRESH_INTERVAL:
		return true
	if _last_set_target.distance_squared_to(target_pos) > 4.0:  # 2² px 抖动阈值
		return true
	return false


## 写 nav target + 更新限频状态. nav_agent null 时 no-op (子类需自查).
##
## **M5 canonicalize**:
##   - true (默认):玩家 click move / 自治 idle move,target 是地图坐标 → 走 canonicalize
##     让玩家点不可达点时 unit 走最近可达 navcell(✋2 体验点)
##   - false:attack / harvest target 是 actor 中心(可能落 building footprint 内),不走
##     canonicalize 直接 A*(M4b.3 wire fail lesson:enemy 中心被偏到 ct 旁外缘 → unit 在
##     attack range 外)
func _refresh_nav_target(nav_agent: RtsNavAgent, target_pos: Vector2, canonicalize: bool = true) -> void:
	if nav_agent == null:
		return
	nav_agent.set_target(target_pos, canonicalize)
	_last_set_target = target_pos
	_time_since_nav_refresh = 0.0


# ========== 链式构造工具 ==========

## 在链尾 push next activity。返回 self 方便链式调用 (a.queue(b).queue(c))。
func queue(activity: RtsActivity) -> RtsActivity:
	if next_activity == null:
		next_activity = activity
	else:
		next_activity.queue(activity)
	return self


# ========== 取消 ==========

## 标 self CANCELING, 递归 child + next。
##
## 不立刻 transition 到 DONE — 下一次 advance 才真正调 on_last_run + DONE。
## 这样 cancel 是 idempotent 且无副作用 (重复 cancel 安全)。
func cancel() -> void:
	if state == State.DONE:
		return
	if state == State.QUEUED or state == State.ACTIVE:
		state = State.CANCELING
	if child_activity != null:
		child_activity.cancel()
	if next_activity != null:
		next_activity.cancel()


# ========== 推进 (静态 driver) ==========

## 推进 head 链, 返回链中第一个未 DONE 的 activity (或 null 全 DONE)。
##
## 父 tick 先跑 (supervisor); 父 tick=true 后再 advance child。这与 OpenRA 子先父后反过来,
## 但符合 RTS 监督模式 (parent 决定 child 何时创建 / 取消)。
##
## 输入 head 必须是 RtsActivity 实例; null → 直接返回 null (链终结)。
static func advance(
	head: RtsActivity,
	actor: RtsUnitActor,
	world: RtsWorldGameplayInstance,
	dt: float,
) -> RtsActivity:
	var current := head
	while current != null:
		# CANCELING → on_last_run + DONE, 切下一个
		if current.state == State.CANCELING:
			current.on_last_run(actor, world)
			current.state = State.DONE
			current = current.next_activity
			continue
		# QUEUED → ACTIVE
		if current.state == State.QUEUED:
			current.state = State.ACTIVE
			current.on_first_run(actor, world)
		# 父 tick 先跑 (supervisor)
		var keep_running := current.tick(actor, world, dt)
		if not keep_running:
			current.on_last_run(actor, world)
			current.state = State.DONE
			current = current.next_activity
			continue
		# 然后推进 child (父 tick 内可能新建 / 取消 child)
		if current.child_activity != null:
			current.child_activity = RtsActivity.advance(current.child_activity, actor, world, dt)
		return current
	return null
