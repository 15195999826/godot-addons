## RtsHarvestStrategy - worker 经济决策策略 (M2.1 Phase C)
##
## 决策树:
##   1. actor 死亡 / world 空 → IdleActivity
##   2. carrying 总和 ≥ 1 (上次 harvest 没 drop 完) → ReturnAndDropActivity (Activity 自找最近 drop-off)
##   3. 否则: 找最近未耗尽 ResourceNode → HarvestActivity(node.id)
##   4. 找不到 ResourceNode → IdleActivity
##
## 严格无状态 (RtsAIStrategy 不变量): decide 是 pure function, 同输入同输出, 全场所有 worker
## 共用一个 _harvest_strategy 实例。
##
## 注: 不读 actor._cached_target_id — worker target_layer_mask=NONE → AutoTargetSystem
##     skip mover, 永不写 cached_target_id; 此策略自己扫 world.get_alive_actors() 过滤 RtsResourceNode。
## 注: stance 不影响 worker (mask=NONE 不参战; 见 phase-c §设计决策 D14)。
##
## 决策来源: phase-c-harvest-activity.md §AC4 + §设计决策 D7 (round-robin nearest, actor_id 字典序 tiebreak)
class_name RtsHarvestStrategy
extends RtsAIStrategy


func decide(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> RtsActivity:
	if actor == null or actor.is_dead() or world == null:
		return RtsIdleActivity.new()

	if actor.get_carry_total() >= 1:
		return RtsReturnAndDropActivity.new()  # 空 drop_off_id → Activity 自找

	var node_id := _find_closest_resource_node(actor, world)
	if node_id == "":
		return RtsIdleActivity.new()

	return RtsHarvestActivity.new(node_id)


# ========== 内部 ==========

## 找最近未耗尽 ResourceNode; 同距离取 actor_id 字典序最小 (D7 决定性 tiebreak)。
##
## get_alive_actors 已过滤 is_dead, 而 RtsResourceNode.is_dead = (_is_dead or is_depleted),
## 故耗尽节点不会出现在循环里 — `is_depleted()` 双保险防未来重构破。
func _find_closest_resource_node(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> String:
	var best_id: String = ""
	var best_dist_sq: float = INF
	for a in world.get_alive_actors():
		if not (a is RtsResourceNode):
			continue
		var node: RtsResourceNode = a as RtsResourceNode
		if node.is_depleted():
			continue
		var d: float = actor.position_2d.distance_squared_to(node.position_2d)
		if d < best_dist_sq:
			best_dist_sq = d
			best_id = node.get_id()
		elif d == best_dist_sq and best_id != "" and node.get_id() < best_id:
			best_id = node.get_id()
	return best_id
