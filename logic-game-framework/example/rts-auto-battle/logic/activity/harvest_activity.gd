## RtsHarvestActivity - worker 在 ResourceNode 处采集资源 (M2.1 Phase C)
##
## 与 RtsAttackActivity 同模式 (单一 Activity 自管 nav, in-range/out-of-range 切换):
##   - 距离 ≤ HARVEST_RADIUS → harvesting (累 harvest_progress; 转化整数单位时 mutate node.amount + worker.carrying)
##   - 距离 > HARVEST_RADIUS → approach (set_target 限频)
##   - target_node 不存在 / is_depleted → DONE; strategy 下 tick 找新 node
##   - carrying 满 carry_capacity → DONE; strategy 下 tick 切 RtsReturnAndDropActivity
##
## per-tick 累积 progress 模型 (D16):
##   harvest_progress += unit.harvest_speed * dt    # ~0.166 per tick (5/sec @ 30Hz)
##   transferable = int(harvest_progress)
##   actual = min(transferable, node.amount, capacity_remaining)
##   node.amount -= actual; unit.carrying[key] += actual; progress -= actual
##
## 多 worker 同 node 无锁 (D11): controller.tick 顺序决定性, 后到 worker 见 node.amount 已减,
## 取 actual = min(..., node.amount) 自然处理 (后到 worker 可能 actual=0 此 tick 不 transfer,
## 下 tick is_depleted check 切其它 node)。
##
## 决策来源: phase-c-harvest-activity.md §AC2 + §设计决策 D10 (单 Activity 自管 nav) /
## D11 (无锁) / D12 (HARVEST_RADIUS=32) / D15 (carrying dict) / D16 (per-tick 累积模型)
class_name RtsHarvestActivity
extends RtsActivity


# ========== 常量 ==========

## 抵达 ResourceNode 的距离阈值 (像素; D12: cell_size=32 ≈ worker collision 12 + node margin)
const HARVEST_RADIUS: float = 32.0
const HARVEST_RADIUS_SQ: float = HARVEST_RADIUS * HARVEST_RADIUS

# Nav refresh 限频 (NAV_REFRESH_INTERVAL / _time_since_nav_refresh / _last_set_target /
# _should_refresh_nav / _refresh_nav_target) 在 RtsActivity 基类 — attack/harvest/return 共用。


# ========== 字段 ==========

## 目标 ResourceNode actor id (中立 team_id=-1)
var target_node_id: String

## 累积 harvest progress (D16 per-tick 模型: 满 1 单位 transfer 1 单位资源)
var harvest_progress: float = 0.0

## M7d — 通过 bind_runtime 注入的 motion component(替代 nav_agent)。
var _motion: RtsMotionComponent = null

## Worker stats cache (on_first_run 时缓存; 避免 tick 每帧调 get_stats 分配 StatBlock)。
## carry_capacity (满 capacity → DONE 切 ReturnAndDrop); harvest_speed (per-tick progress 增量)
var _carry_capacity: int = 0
var _harvest_speed: float = 0.0

## 当前是否 in-range (供 get_intent_label / 调试用; 与 RtsAttackActivity._wants_attack 同模式)
var _intent_in_range: bool = false


# ========== 初始化 ==========

func _init(p_target_node_id: String) -> void:
	target_node_id = p_target_node_id


func bind_runtime(motion_component: RtsMotionComponent) -> void:
	_motion = motion_component
	super.bind_runtime(motion_component)


# ========== 钩子 ==========

func on_first_run(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> void:
	# Cache worker stats (immutable mid-battle; 避免 tick 每帧调 get_stats 分配 StatBlock)
	if actor != null:
		var stats: RtsUnitClassConfig.StatBlock = RtsUnitClassConfig.get_stats(actor.unit_class)
		_carry_capacity = stats.carry_capacity
		_harvest_speed = stats.harvest_speed

	if world == null or _motion == null:
		return
	var node := world.get_actor(target_node_id) as RtsResourceNode
	if node == null or node.is_depleted():
		return
	# M7d: target=ResourceNode 中心(可能被旁边 ct clearance inflate 阻挡)→ motion.move_to 走
	# facade.compute_path_immediate 内部 canonicalize,goal 落 impassable 时 mutate 到外缘 navcell;
	# motion._step 走到外缘 + distance ≤ HARVEST_RADIUS=32 触发 harvest。
	_refresh_motion_target(_motion, node.position_2d, false)


func tick(actor: RtsUnitActor, world: RtsWorldGameplayInstance, dt: float) -> bool:
	_time_since_nav_refresh += dt
	if actor == null or actor.is_dead() or world == null:
		return false

	var node := world.get_actor(target_node_id) as RtsResourceNode
	if node == null or node.is_depleted():
		return false

	var capacity_remaining: int = _carry_capacity - actor.get_carry_total()
	if capacity_remaining <= 0:
		return false  # worker 满载 → strategy 下 tick 切 RtsReturnAndDropActivity

	var dist_sq: float = actor.position_2d.distance_squared_to(node.position_2d)
	if dist_sq <= HARVEST_RADIUS_SQ:
		_intent_in_range = true
		if _motion != null and _motion.motion.has_target():
			_motion.motion.stop()
		harvest_progress += _harvest_speed * dt
		var transferable: int = int(harvest_progress)
		if transferable > 0:
			var actual: int = min(transferable, node.amount, capacity_remaining)
			if actual > 0:
				node.amount -= actual
				actor.carrying[node.field_kind_key] = int(actor.carrying.get(node.field_kind_key, 0)) + actual
				harvest_progress -= float(actual)
	else:
		_intent_in_range = false
		if _motion != null and _should_refresh_nav(node.position_2d):
			_refresh_motion_target(_motion, node.position_2d, false)
	return true


func on_last_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if _motion != null:
		_motion.motion.stop()


func is_equivalent_to(other: RtsActivity) -> bool:
	if not (other is RtsHarvestActivity):
		return false
	return target_node_id == (other as RtsHarvestActivity).target_node_id


func get_intent_label() -> String:
	return "harvest" if _intent_in_range else "approach"
