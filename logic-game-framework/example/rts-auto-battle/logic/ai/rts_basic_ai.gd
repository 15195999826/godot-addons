## RtsBasicAI - RTS 单位的轻量 AI 决策器
##
## 每 tick 跑一次:
##   1. 若 current_target_id 空 / 死 / 不在 world → 重新找最近敌人(按 position_2d 距离平方)
##   2. 与 target 距离 ≤ attack_range → clear nav target(停下), 通知 attack 行为(M0.6 接入)
##   3. 距离 > attack_range → set nav target = target.position_2d, 每 200ms 才刷新一次避免抖动
##
## 没用 LGF 的 AIStrategy 接口: 那套基于 ATB tick 的策略接口与 RTS 连续 tick 节奏不一致,
## 此处直接持 actor + nav agent 引用做最小决策。
##
## 调方(procedure 的 per_tick)循环遍历所有存活 character actor, 对每个调 ai.tick(dt)。
class_name RtsBasicAI
extends RefCounted


## Nav target 刷新最小间隔(秒) — 同一目标重复 set_target 触发 NavigationServer rebuild,
## 每帧刷会让单位卡住; 200ms 一次足够追手。
const NAV_REFRESH_INTERVAL: float = 0.2

## attack 距离判定加 5% 容差(浮点抖动 + 单位贴边时不抢攻击)
const RANGE_TOLERANCE: float = 1.05


# ========== 字段 ==========

var actor: RtsCharacterActor = null
var agent: RtsNavAgent = null

## 当前 target 已 set_target 多久没刷新, 累加 dt
var _time_since_nav_refresh: float = 0.0

## AI 上一帧的"决策状态" — 给 attack action 看, 也方便日志
##   "idle"      — 没目标
##   "approach"  — 向目标移动中
##   "in_range"  — 已进入 attack_range, cooldown 到时即可攻击
var last_decision: String = "idle"


# ========== 初始化 ==========

func bind(p_actor: RtsCharacterActor, p_agent: RtsNavAgent) -> void:
	actor = p_actor
	agent = p_agent


# ========== Tick ==========

func tick(dt: float, world: RtsWorldGameplayInstance) -> void:
	if actor == null or actor.is_dead() or world == null:
		return

	_time_since_nav_refresh += dt

	var target: RtsCharacterActor = _find_or_keep_target(world)
	if target == null:
		actor.current_target_id = ""
		if agent != null:
			agent.clear_target()
		last_decision = "idle"
		return

	actor.current_target_id = target.get_id()
	var dist := actor.position_2d.distance_to(target.position_2d)
	var atk_range := actor.attribute_set.attack_range

	if dist <= atk_range * RANGE_TOLERANCE:
		# In range, hold position. attack action(M0.6) 会读 current_target_id 触发实际攻击。
		if agent != null:
			agent.clear_target()
		last_decision = "in_range"
	else:
		# Out of range, approach. Refresh nav target every NAV_REFRESH_INTERVAL.
		if agent != null and _time_since_nav_refresh >= NAV_REFRESH_INTERVAL:
			agent.set_target(target.position_2d)
			_time_since_nav_refresh = 0.0
		last_decision = "approach"


# ========== 内部 ==========

## 当前 target 仍存活且在 world → 复用; 否则找最近敌人。
func _find_or_keep_target(world: RtsWorldGameplayInstance) -> RtsCharacterActor:
	var current_id := actor.current_target_id
	if current_id != "":
		var existing := world.get_actor(current_id) as RtsCharacterActor
		if existing != null and not existing.is_dead():
			return existing

	var best: RtsCharacterActor = null
	var best_dist_sq: float = INF
	for other in world.get_alive_actors():
		if not (other is RtsCharacterActor):
			continue
		var character_other := other as RtsCharacterActor
		if character_other.get_team_id() == actor.get_team_id():
			continue
		var dsq := actor.position_2d.distance_squared_to(character_other.position_2d)
		if dsq < best_dist_sq:
			best_dist_sq = dsq
			best = character_other
	return best
