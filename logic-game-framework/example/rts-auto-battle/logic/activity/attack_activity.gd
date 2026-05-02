## RtsAttackActivity - 攻击指定目标; 自带接敌 nav (P2.1; P2.2 拆 movement)
##
## 替代 Phase 1 string FSM 的 "attack" + "approach" 两态:
##   - target 仍存活 + 距离 ≤ attack_range × RANGE_TOLERANCE → wants_to_attack=true
##     (procedure 在 controller.wants_to_attack && unit.can_attack 时触发 basic attack)
##   - 距离过远 → wants_to_attack=false; nav_agent.set_target(target.position_2d) 接敌
##   - target 死亡 → tick 返回 false → activity DONE; controller / strategy 下一 tick 选新目标
##
## P2.2: tick 仅维护 set_target / clear_target (基于距离判断), **不再** 调 nav_agent.tick — 移动
## 由 procedure 主循环 step 4 统一调度 (compute_velocity → steering → integrate)。
##
## nav refresh 限频 (NAV_REFRESH_INTERVAL=0.2s) 与 Phase 1 controller 一致 — target 移动 > 2px
## 也立即刷新 (避免追不上跑动目标)。
##
## 决策来源:
##   - phase-2-core-systems.md P2.1 + P2.2
##   - phase-1-foundation.md P1.5 (NAV_REFRESH_INTERVAL 来源)
class_name RtsAttackActivity
extends RtsActivity


# ========== 常量 ==========

## attack 距离判定加 5% 容差(浮点抖动 + 单位贴边时不抢攻击, 与 Phase 1 一致)
const RANGE_TOLERANCE: float = 1.05

## Nav target 刷新最小间隔(秒); Phase 1 controller 同值。
const NAV_REFRESH_INTERVAL: float = 0.2


# ========== 字段 ==========

## 目标 actor id; 必须是另一队伍的 RtsUnitActor。
var target_id: String

## 通过 bind_runtime 注入的 nav agent。
var _nav_agent: RtsNavAgent = null

## 本帧是否想 attack (in-range 时 true; out-of-range / target dead 时 false)
var _wants_attack: bool = false

## Nav refresh 限频计时
var _time_since_nav_refresh: float = 0.0

## 上一次 set_target 的位置, 用于跳过 < 2px 抖动
var _last_set_target: Vector2 = Vector2.INF


# ========== 初始化 ==========

func _init(p_target_id: String) -> void:
	target_id = p_target_id


func bind_runtime(nav_agent: RtsNavAgent) -> void:
	_nav_agent = nav_agent
	super.bind_runtime(nav_agent)


# ========== 钩子 ==========

func on_first_run(actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if actor != null:
		actor.current_target_id = target_id


func tick(actor: RtsUnitActor, world: RtsWorldGameplayInstance, dt: float) -> bool:
	_time_since_nav_refresh += dt
	if actor == null or actor.is_dead() or world == null:
		return false
	# P2.8: target 类型放宽到 RtsBattleActor — 单位可以打建筑 (e.g. AC8 攻击水晶塔判胜负)。
	var target := world.get_actor(target_id) as RtsBattleActor
	if target == null or target.is_dead():
		return false
	actor.current_target_id = target_id
	var dist_sq: float = actor.position_2d.distance_squared_to(target.position_2d)
	var atk_range: float = actor.attribute_set.attack_range
	var atk_range_with_tol: float = atk_range * RANGE_TOLERANCE
	if dist_sq <= atk_range_with_tol * atk_range_with_tol:
		_wants_attack = true
		if _nav_agent != null:
			_nav_agent.clear_target()
	else:
		_wants_attack = false
		if _nav_agent != null and _should_refresh_nav(target.position_2d):
			_nav_agent.set_target(target.position_2d)
			_last_set_target = target.position_2d
			_time_since_nav_refresh = 0.0
	return true


func on_last_run(actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if actor != null:
		actor.current_target_id = ""
	_wants_attack = false
	if _nav_agent != null:
		_nav_agent.clear_target()


func wants_to_attack() -> bool:
	return _wants_attack


func is_equivalent_to(other: RtsActivity) -> bool:
	if not (other is RtsAttackActivity):
		return false
	return target_id == (other as RtsAttackActivity).target_id


func get_intent_label() -> String:
	return "attack" if _wants_attack else "approach"


# ========== 内部 ==========

## 是否应该刷新 nav target:
##   - 距离上次刷新已经 ≥ NAV_REFRESH_INTERVAL, 或
##   - 目标位置发生显著变化 (>2 px) — 即使在限频窗口内也立即刷
func _should_refresh_nav(target_pos: Vector2) -> bool:
	if _time_since_nav_refresh >= NAV_REFRESH_INTERVAL:
		return true
	if _last_set_target.distance_squared_to(target_pos) > 4.0:  # 2² px 抖动阈值
		return true
	return false
