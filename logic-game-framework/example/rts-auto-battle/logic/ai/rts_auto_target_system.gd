## RtsAutoTargetSystem - 集中式目标选择系统 (P2.4, Mindustry + OpenRA 风)
##
## 替代 P1.5 中"每 unit 每 tick 自己 _select_nearest"的 O(N²) 散点扫描:
##   - 每 RESCAN_INTERVAL_TICKS (20 tick ≈ 1s @50ms) 做一次全量重评 (走全部 alive unit)
##   - 任何单位 cache 命中目标在本 tick 死亡 / 失效 → 立即给该单位单独重扫 (不等下个 scan)
##
## 评分公式 (单一标量, 浮点稳定):
##   score = max_priority_weight * WEIGHT_SCALE - distance_squared
## 其中 max_priority_weight 来自 actor.target_priorities 与 candidate.unit_tags 的最大匹配
## (无匹配 = 0, 与"无 priority 设置时全打平 → 退化为最近"行为兼容)。
##
## 决定性 (replay bit-equal 友好):
##   - units 入参顺序由 procedure 保证 (insertion order via world.get_alive_units)
##   - 不调 randf
##   - 评分用 strict ">" 取最大, 同分时保留先扫到的 (与 _select_nearest 一致)
##   - by_team 字典迭代依赖 Godot 4 dict insertion-order 语义 (与 Phase 1 _get_enemies 同序)
##
## Stance 处理:
##   - HOLD_FIRE: 不写 _cached_target_id (清空)
##   - DEFENSIVE: 仅候选距离 ≤ DEFENSIVE_ENGAGE_RANGE_FACTOR × attack_range 的敌人
##   - AGGRESSIVE: 全部敌人入候选
##
## 决策来源: phase-2-core-systems.md §P2.4
class_name RtsAutoTargetSystem
extends RefCounted


# ========== 调参常量 ==========

## 全量 rescan 间隔 (tick); 20 ticks @ 50ms = 1s, @ 33.33ms (30Hz) ≈ 0.67s。
## 与 spec "每 20 tick 扫一次全场 enemy" 对齐。
const RESCAN_INTERVAL_TICKS: int = 20

## priority weight 在评分中的放大系数。需远大于战场最大可能 distance_squared
## (RTS 主 smoke 500×500 px 战场, max dsq ≈ 5e5; WEIGHT_SCALE = 1e5 让 weight=1 永远胜过最远候选)。
##
## 副作用: weight=0 时 score = -dsq → 与 _select_nearest 同序 (P1.5 行为兼容)。
const WEIGHT_SCALE: float = 100000.0


# ========== 字段 ==========

## 距离上次全量 rescan 的 tick 数; 累计到 RESCAN_INTERVAL_TICKS 触发全量。
## procedure 起始时 = RESCAN_INTERVAL_TICKS 让第一次 tick 立即全量, 不留空窗。
var _ticks_since_scan: int = RESCAN_INTERVAL_TICKS


# ========== Tick ==========

## procedure 主循环每 tick 调一次 (在 controller.tick 之前 — 写完 _cached_target_id 才让
## strategy.decide 读到)。
##
## @param world 用于 get_actor() (alive 校验)
## @param units 全部存活 RtsUnitActor (procedure 已过滤建筑 / 死亡)
func tick(world: RtsWorldGameplayInstance, units: Array) -> void:
	if world == null:
		return

	_ticks_since_scan += 1
	var force_full_rescan: bool = _ticks_since_scan >= RESCAN_INTERVAL_TICKS
	if force_full_rescan:
		_ticks_since_scan = 0

	# 第 1 遍: 校验 cache 仍存活, 顺手收集 "需要重算" 的单位 (cache 失效 / HOLD_FIRE 清空)。
	# HOLD_FIRE 走单独清空分支; AGGRESSIVE / DEFENSIVE 在此阶段保持 cache 不变 (除非失效)。
	var needs_rescan: Array[RtsUnitActor] = []
	for u in units:
		var unit := u as RtsUnitActor
		if unit == null or unit.is_dead():
			continue

		if unit.stance == RtsUnitActor.Stance.HOLD_FIRE:
			unit._cached_target_id = ""
			continue

		var cached_id: String = unit._cached_target_id
		if not cached_id.is_empty():
			var cached := world.get_actor(cached_id) as RtsUnitActor
			if cached == null or cached.is_dead():
				unit._cached_target_id = ""
				needs_rescan.append(unit)
		else:
			needs_rescan.append(unit)

	# 第 2 遍: 如果 force_full_rescan, 所有非 HOLD_FIRE 单位都参与重评; 否则仅 needs_rescan。
	var rescan_set: Array[RtsUnitActor]
	if force_full_rescan:
		rescan_set = []
		for u in units:
			var unit := u as RtsUnitActor
			if unit == null or unit.is_dead():
				continue
			if unit.stance == RtsUnitActor.Stance.HOLD_FIRE:
				continue
			rescan_set.append(unit)
	else:
		rescan_set = needs_rescan

	if rescan_set.is_empty():
		return

	# 预聚合: 按 team_id 分组 (避免每个 unit 重新过滤一遍 units 列表)。
	# Godot 4 Dictionary keys() 遵循 insertion order → 决定性。
	var by_team: Dictionary = {}
	for u in units:
		var unit := u as RtsUnitActor
		if unit == null or unit.is_dead():
			continue
		var t: int = unit.get_team_id()
		if not by_team.has(t):
			by_team[t] = ([] as Array[RtsUnitActor])
		(by_team[t] as Array[RtsUnitActor]).append(unit)

	# 第 3 遍: 对 rescan_set 中每个单位, 按 priority + distance 评分选最佳。
	for unit in rescan_set:
		_rescore_unit(unit, by_team)


# ========== 内部 ==========

## 给单个 unit 在 by_team 内挑出 best_target, 写入 _cached_target_id。
## 没合法候选 → 写空字符串 (strategy 下一 tick 看到空 → 返回 IdleActivity)。
func _rescore_unit(unit: RtsUnitActor, by_team: Dictionary) -> void:
	var my_team: int = unit.get_team_id()
	var atk_range: float = unit.attribute_set.attack_range if unit.attribute_set != null else 0.0
	var defensive_range_sq: float = pow(atk_range * RtsUnitActor.DEFENSIVE_ENGAGE_RANGE_FACTOR, 2)

	var best: RtsUnitActor = null
	var best_score: float = -INF

	for team_key in by_team.keys():
		if int(team_key) == my_team:
			continue
		var enemy_list: Array[RtsUnitActor] = by_team[team_key]
		for enemy in enemy_list:
			var dsq: float = unit.position_2d.distance_squared_to(enemy.position_2d)

			if unit.stance == RtsUnitActor.Stance.DEFENSIVE and dsq > defensive_range_sq:
				continue

			var weight: float = _priority_weight(unit, enemy)
			var score: float = weight * WEIGHT_SCALE - dsq
			if score > best_score:
				best_score = score
				best = enemy

	unit._cached_target_id = best.get_id() if best != null else ""


## 计算 actor 对 candidate 的最大 priority weight (max over 匹配的 tag 项)。
##
## 无 priority 配置 → 0 (退化为按距离选最近)。
## 多 tag 匹配 → 取最大 weight (例如 candidate 既是 ranged 又是 elite 时, 取较高的那个)。
static func _priority_weight(actor: RtsUnitActor, candidate: RtsUnitActor) -> float:
	if actor.target_priorities.is_empty():
		return 0.0
	var max_w: float = 0.0
	for entry in actor.target_priorities:
		var tag: String = str(entry.get("tag", ""))
		if tag.is_empty():
			continue
		if not candidate.unit_tags.has(tag):
			continue
		var w: float = float(entry.get("weight", 0.0))
		if w > max_w:
			max_w = w
	return max_w
