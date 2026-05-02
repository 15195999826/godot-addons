## RtsReturnAndDropActivity - worker 把 carrying 资源回送到己方 drop-off (M2.1 Phase C)
##
## 与 RtsAttackActivity / RtsHarvestActivity 同模式 (单一 Activity 自管 nav, in-range/out-of-range 切换):
##   - on_first_run: 找己方最近 is_drop_off 建筑 (D6: ct 兼任), 起手 set_target
##   - tick 距离 ≤ DROP_OFF_RADIUS → 抵达, world.procedure.add_team_resources(team_id, carrying)
##     + carrying.clear() → DONE; strategy 下 tick 切回 RtsHarvestActivity
##   - tick 距离 > DROP_OFF_RADIUS → approach (set_target 限频)
##   - drop-off 中途死亡 → 重找最近 is_drop_off; 找不到 → DONE (strategy 下 tick 重新评估)
##
## 决策来源: phase-c-harvest-activity.md §AC3 + §设计决策 D6 (ct 兼任 drop-off) /
## D9 (world.procedure 通信) / D12 (DROP_OFF_RADIUS=32)
class_name RtsReturnAndDropActivity
extends RtsActivity


# ========== 常量 ==========

## 抵达 drop-off 的距离阈值 (像素; D12: ct footprint 2×2 ≈ 64 px, drop-off radius=32 让 worker 走到 ct 边即可)
const DROP_OFF_RADIUS: float = 32.0
const DROP_OFF_RADIUS_SQ: float = DROP_OFF_RADIUS * DROP_OFF_RADIUS

# Nav refresh 限频 (NAV_REFRESH_INTERVAL / _time_since_nav_refresh / _last_set_target /
# _should_refresh_nav / _refresh_nav_target) 在 RtsActivity 基类 — attack/harvest/return 共用。


# ========== 字段 ==========

## 目标 drop-off 建筑 actor id (空表示 on_first_run 找己方最近)。
var drop_off_id: String = ""

## 通过 bind_runtime 注入的 nav agent
var _nav_agent: RtsNavAgent = null

## 当前是否处于 return 状态 (出发→drop-off; 抵达 in-range 那 tick 直接 return false 完成 drop,
## 故 false → "return"; 与 RtsAttackActivity._wants_attack 同模式 — Activity DONE 后 controller 看 is_done 返 "idle")
var _intent_arriving: bool = false


# ========== 初始化 ==========

func _init(p_drop_off_id: String = "") -> void:
	drop_off_id = p_drop_off_id


func bind_runtime(nav_agent: RtsNavAgent) -> void:
	_nav_agent = nav_agent
	super.bind_runtime(nav_agent)


# ========== 钩子 ==========

func on_first_run(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> void:
	if world == null:
		return
	if drop_off_id == "":
		drop_off_id = _find_closest_drop_off(actor, world)
	if drop_off_id == "" or _nav_agent == null:
		return
	var building := world.get_actor(drop_off_id) as RtsBuildingActor
	if building == null or building.is_dead():
		return
	_refresh_nav_target(_nav_agent, building.position_2d)


func tick(actor: RtsUnitActor, world: RtsWorldGameplayInstance, dt: float) -> bool:
	_time_since_nav_refresh += dt
	if actor == null or actor.is_dead() or world == null:
		return false

	var building := world.get_actor(drop_off_id) as RtsBuildingActor
	if building == null or building.is_dead():
		# Drop-off 中途死亡 — 重找最近己方 is_drop_off
		drop_off_id = _find_closest_drop_off(actor, world)
		if drop_off_id == "":
			return false
		building = world.get_actor(drop_off_id) as RtsBuildingActor
		if building == null or building.is_dead():
			return false
		_refresh_nav_target(_nav_agent, building.position_2d)
		return true  # 下 tick 再评估距离

	var dist_sq: float = actor.position_2d.distance_squared_to(building.position_2d)
	if dist_sq <= DROP_OFF_RADIUS_SQ:
		if world.procedure != null and not actor.carrying.is_empty():
			world.procedure.add_team_resources(actor.get_team_id(), actor.carrying)
		actor.carrying.clear()
		return false  # 完成 drop, strategy 下 tick 切回 HarvestActivity
	_intent_arriving = false
	if _nav_agent != null and _should_refresh_nav(building.position_2d):
		_refresh_nav_target(_nav_agent, building.position_2d)
	return true


func on_last_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if _nav_agent != null:
		_nav_agent.clear_target()


func is_equivalent_to(other: RtsActivity) -> bool:
	if not (other is RtsReturnAndDropActivity):
		return false
	return drop_off_id == (other as RtsReturnAndDropActivity).drop_off_id


func get_intent_label() -> String:
	# Activity 抵达 drop-off 那 tick 即 return false → DONE; controller.get_intent_action()
	# 看 is_done() 返 "idle". 故 _intent_arriving = true 永远不可观察, "return" 是唯一活跃标签.
	return "drop_off" if _intent_arriving else "return"


# ========== 内部 ==========

## 找己方最近 is_drop_off 建筑; 同距离取 actor_id 字典序最小 (D7 round-robin 决定性 tiebreak).
##
## 找不到 → 返空串 (worker 在 castle_war 模式下若 ct 死亡可能触发, 但战斗结束胜负判定优先于 worker 行为).
func _find_closest_drop_off(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> String:
	var team_id: int = actor.get_team_id()
	var best_id: String = ""
	var best_dist_sq: float = INF
	for a in world.get_alive_actors():
		if not (a is RtsBuildingActor):
			continue
		var b: RtsBuildingActor = a as RtsBuildingActor
		if not b.is_drop_off:
			continue
		if b.get_team_id() != team_id:
			continue
		var d: float = actor.position_2d.distance_squared_to(b.position_2d)
		if d < best_dist_sq:
			best_dist_sq = d
			best_id = b.get_id()
		elif d == best_dist_sq and best_id != "" and b.get_id() < best_id:
			best_id = b.get_id()
	return best_id
