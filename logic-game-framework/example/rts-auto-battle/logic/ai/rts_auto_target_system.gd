## RtsAutoTargetSystem - 集中式目标选择系统 (P2.4 起; P2.8 扩到建筑 + layer mask)
##
## 替代 P1.5 中"每 unit 每 tick 自己 _select_nearest"的 O(N²) 散点扫描:
##   - 每 RESCAN_INTERVAL_TICKS (20 tick ≈ 1s @50ms) 做一次全量重评 (走全部 alive actor)
##   - 任何 actor cache 命中目标在本 tick 死亡 / 失效 → 立即给该 actor 单独重扫 (不等下个 scan)
##
## P2.8 改动:
##   - movers 扩展到含攻击能力的 RtsBattleActor (units + buildings); building 没 stance 但有
##     target_layer_mask, 防空塔等可直接作为 mover 写 _cached_target_id
##   - candidates 也扩展到全 alive RtsBattleActor (单位 + 建筑) — 单位现在能选建筑当目标
##     (AC8 城堡战争最小可玩 demo: 兵种打水晶塔判胜负)
##   - 候选过滤增加 layer-mask 命中检查: skip if not RtsWeaponConfig.matches(mover.mask, candidate.layer)
##
## 评分公式 (单一标量, 浮点稳定):
##   score = max_priority_weight * WEIGHT_SCALE - distance_squared
## 其中 max_priority_weight 来自 mover.target_priorities 与 candidate.unit_tags 的最大匹配
## (无匹配 = 0, 与"无 priority 设置时全打平 → 退化为最近"行为兼容)。
##
## 决定性 (replay bit-equal 友好):
##   - actors 入参顺序由 procedure 保证 (insertion order via world.get_alive_actors)
##   - 不调 randf
##   - 评分用 strict ">" 取最大, 同分时保留先扫到的 (与 _select_nearest 一致)
##   - by_team 字典迭代依赖 Godot 4 dict insertion-order 语义
##
## Stance 处理 (仅对 RtsUnitActor 生效, 建筑无 stance):
##   - HOLD_FIRE: 不写 _cached_target_id (清空)
##   - DEFENSIVE: 仅候选距离 ≤ DEFENSIVE_ENGAGE_RANGE_FACTOR × attack_range 的敌人
##   - AGGRESSIVE: 全部敌人入候选
##
## 决策来源: phase-2-core-systems.md §P2.4 + §P2.8
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
## strategy.decide 读到; 建筑也会在 procedure 内读 _cached_target_id 做攻击判定)。
##
## @param world 用于 get_actor() (alive 校验)
## @param actors 全部存活 RtsBattleActor (procedure 已过滤死亡 — 含 units + buildings)
func tick(world: RtsWorldGameplayInstance, actors: Array) -> void:
	if world == null:
		return

	_ticks_since_scan += 1
	var force_full_rescan: bool = _ticks_since_scan >= RESCAN_INTERVAL_TICKS
	if force_full_rescan:
		_ticks_since_scan = 0

	# 第 1 遍: 校验 cache 仍存活, 顺手收集 "需要重算" 的 mover (cache 失效 / HOLD_FIRE 清空)。
	# Mover = 任何能攻击的 RtsBattleActor (target_layer_mask != 0); 建筑也是 mover。
	# HOLD_FIRE 走单独清空分支 (仅 unit); building 没 stance 永远参战。
	var needs_rescan: Array[RtsBattleActor] = []
	for a in actors:
		var mover := a as RtsBattleActor
		if mover == null or mover.is_dead():
			continue
		if mover.target_layer_mask == MovementLayer.MASK_NONE:
			continue  # 没武器 (兵营 / 水晶塔 / 单位 mask=0)

		if _is_hold_fire(mover):
			mover._cached_target_id = ""
			continue

		var cached_id: String = mover._cached_target_id
		if not cached_id.is_empty():
			var cached := world.get_actor(cached_id) as RtsBattleActor
			if cached == null or cached.is_dead():
				mover._cached_target_id = ""
				needs_rescan.append(mover)
		else:
			needs_rescan.append(mover)

	# 第 2 遍: force_full_rescan 时全部 mover 重评; 否则仅 needs_rescan。
	var rescan_set: Array[RtsBattleActor]
	if force_full_rescan:
		rescan_set = []
		for a in actors:
			var mover := a as RtsBattleActor
			if mover == null or mover.is_dead():
				continue
			if mover.target_layer_mask == MovementLayer.MASK_NONE:
				continue
			if _is_hold_fire(mover):
				continue
			rescan_set.append(mover)
	else:
		rescan_set = needs_rescan

	if rescan_set.is_empty():
		return

	# 预聚合: 按 team_id 分组所有 alive 候选 (units + buildings 都进)。
	# Godot 4 Dictionary keys() 遵循 insertion order → 决定性。
	var by_team: Dictionary = {}
	for a in actors:
		var actor := a as RtsBattleActor
		if actor == null or actor.is_dead():
			continue
		var t: int = actor.get_team_id()
		if not by_team.has(t):
			by_team[t] = ([] as Array[RtsBattleActor])
		(by_team[t] as Array[RtsBattleActor]).append(actor)

	# 第 3 遍: 对 rescan_set 中每个 mover, 按 priority + distance 评分选最佳候选。
	for mover in rescan_set:
		_rescore_mover(mover, by_team)


# ========== 内部 ==========

## 给单个 mover 在 by_team 内挑出 best_target, 写入 _cached_target_id。
## 没合法候选 → 写空字符串。
func _rescore_mover(mover: RtsBattleActor, by_team: Dictionary) -> void:
	var my_team: int = mover.get_team_id()
	var atk_range: float = mover.get_attack_range()
	var defensive_range_sq: float = pow(atk_range * RtsUnitActor.DEFENSIVE_ENGAGE_RANGE_FACTOR, 2)
	var apply_defensive: bool = _is_defensive(mover)

	var best: RtsBattleActor = null
	var best_score: float = -INF

	for team_key in by_team.keys():
		if int(team_key) == my_team:
			continue
		var enemy_list: Array[RtsBattleActor] = by_team[team_key]
		for enemy in enemy_list:
			# P2.8: 过滤 layer mask — mover 武器命不到 enemy.movement_layer 直接跳过
			if not RtsWeaponConfig.matches(mover.target_layer_mask, enemy.movement_layer):
				continue

			var dsq: float = mover.position_2d.distance_squared_to(enemy.position_2d)

			if apply_defensive and dsq > defensive_range_sq:
				continue

			var weight: float = _priority_weight(mover, enemy)
			var score: float = weight * WEIGHT_SCALE - dsq
			if score > best_score:
				best_score = score
				best = enemy

	mover._cached_target_id = best.get_id() if best != null else ""


## 计算 mover 对 candidate 的最大 priority weight (max over 匹配的 tag 项)。
##
## 无 priority 配置 → 0 (退化为按距离选最近)。
## 多 tag 匹配 → 取最大 weight (例如 candidate 既是 ranged 又是 elite 时, 取较高的那个)。
static func _priority_weight(mover: RtsBattleActor, candidate: RtsBattleActor) -> float:
	if mover.target_priorities.is_empty():
		return 0.0
	var max_w: float = 0.0
	for entry in mover.target_priorities:
		var tag: String = str(entry.get("tag", ""))
		if tag.is_empty():
			continue
		if not candidate.unit_tags.has(tag):
			continue
		var w: float = float(entry.get("weight", 0.0))
		if w > max_w:
			max_w = w
	return max_w


## stance HOLD_FIRE 仅 RtsUnitActor 有; building 永远参战。
static func _is_hold_fire(mover: RtsBattleActor) -> bool:
	if not (mover is RtsUnitActor):
		return false
	return (mover as RtsUnitActor).stance == RtsUnitActor.Stance.HOLD_FIRE


## stance DEFENSIVE 仅 RtsUnitActor 有; building 永远 AGGRESSIVE-equivalent (按 mask 吃距离)。
static func _is_defensive(mover: RtsBattleActor) -> bool:
	if not (mover is RtsUnitActor):
		return false
	return (mover as RtsUnitActor).stance == RtsUnitActor.Stance.DEFENSIVE
