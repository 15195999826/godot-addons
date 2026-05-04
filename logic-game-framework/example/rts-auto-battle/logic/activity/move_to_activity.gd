## RtsMoveToActivity - 沿 nav agent 路径走到指定世界坐标 (P2.1; P2.2 拆 movement)
##
## on_first_run: nav_agent.set_target(target_pos) 起 A*。
## tick: 检查抵达 (距离 ≤ ARRIVAL_THRESHOLD 或 nav_agent.is_arrived()); **不再** 调
##   nav_agent.tick — 移动 (compute_velocity / integrate) 由 procedure 主循环 step 4 统一驱动
##   (P2.2: nav 推进与 steering 之间需要 spatial_hash + steering 介入, 不能由 activity 一步打包)。
## on_last_run: nav_agent.clear_target() 释放路径资源。
##
## 决策来源: phase-2-core-systems.md P2.1 + P2.2
class_name RtsMoveToActivity
extends RtsActivity


# ========== 常量 ==========

const ARRIVAL_THRESHOLD: float = 4.0
const ARRIVAL_THRESHOLD_SQ: float = ARRIVAL_THRESHOLD * ARRIVAL_THRESHOLD


# ========== 字段 ==========

## 目标世界坐标 (像素)
var target_pos: Vector2

## 是否对 goal 走 canonicalize (M5):
##   - true (默认): 玩家 click free space 时, goal 落 impassable → mutate 到外缘 navcell
##     (✋2 体验点: 点墙后 unit 走最近可达, 不死循环)
##   - false: target 是 enemy actor 中心 (可能落 building footprint impassable 区), 直接走
##     LongPath direct-path fallback 朝 target 中心(到 ARRIVAL_THRESHOLD 内才算 arrive). 用于
##     RtsAttackMoveActivity 朝 enemy_ct 走 — 走到 ct 中心附近 child done → strategy 接管
##     RtsAttackActivity (它自己也走 canonicalize=false direct-path attack ct).
var canonicalize: bool = true

## 通过 bind_runtime 注入的 nav agent。
var _nav_agent: RtsNavAgent = null


# ========== 初始化 ==========

func _init(p_target_pos: Vector2, p_canonicalize: bool = true) -> void:
	target_pos = p_target_pos
	canonicalize = p_canonicalize


func bind_runtime(nav_agent: RtsNavAgent) -> void:
	_nav_agent = nav_agent
	super.bind_runtime(nav_agent)


# ========== 钩子 ==========

func on_first_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if _nav_agent != null:
		_nav_agent.set_target(target_pos, canonicalize)


func tick(actor: RtsUnitActor, _world: RtsWorldGameplayInstance, _dt: float) -> bool:
	if actor == null or actor.is_dead():
		return false
	if actor.position_2d.distance_squared_to(target_pos) <= ARRIVAL_THRESHOLD_SQ:
		return false
	if _nav_agent == null:
		return false
	if _nav_agent.is_arrived():
		return false
	return true


func on_last_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if _nav_agent != null:
		_nav_agent.clear_target()


func is_equivalent_to(other: RtsActivity) -> bool:
	if not (other is RtsMoveToActivity):
		return false
	var other_move := other as RtsMoveToActivity
	return target_pos.distance_squared_to(other_move.target_pos) < 1.0


func get_intent_label() -> String:
	return "move"
