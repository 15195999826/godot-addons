## RtsAIStrategy - RTS AI 策略基类 (S3 修复; P2.1 返回 Activity)
##
## P2.1 重写: decide() 返回 RtsActivity (替代 Phase 1 的 string Intent dict)。
## 策略仍**严格无状态** — decide(actor, world) 是 pure function, 同输入同输出。
##
## controller.tick 每 tick 调 decide; 提议的 Activity 与 controller.current_activity 比较
## (RtsActivity.is_equivalent_to), 等价则复用 (避免每 tick 重建 nav 状态), 不等价则
## cancel 旧的 + 接管新的。
##
## 不变量(P1.5 + P2.1):
##   - 策略 0 字段
##   - decide() 不写 self / actor / agent / world
##   - 共享实例由 RtsAIStrategyFactory 持有 (无状态可安全共享)
##
## 决策来源:
##   - phase-1-foundation.md P1.5 (S3 修复, 无状态共享)
##   - phase-2-core-systems.md P2.1 (string FSM → Activity)
class_name RtsAIStrategy


## AI 决策: 返回本 tick 的"建议 activity"。
## 子类必须覆盖。基类默认返回 IdleActivity (空 fallback)。
func decide(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> RtsActivity:
	return RtsIdleActivity.new()


# ============================================================
# 通用工具方法 (子类共用)
# ============================================================

## 找出 actor 的所有存活敌方单位
func _get_enemies(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> Array[RtsUnitActor]:
	var enemies: Array[RtsUnitActor] = []
	for other in world.get_alive_actors():
		if not (other is RtsUnitActor):
			continue
		var unit_other := other as RtsUnitActor
		if unit_other.get_team_id() != actor.get_team_id():
			enemies.append(unit_other)
	return enemies


## 在候选列表中选最近的(按 position_2d 距离平方, 避免开根, 同序结果)
func _select_nearest(actor: RtsUnitActor, candidates: Array[RtsUnitActor]) -> RtsUnitActor:
	if candidates.is_empty():
		return null
	var best: RtsUnitActor = candidates[0]
	var best_dsq: float = actor.position_2d.distance_squared_to(best.position_2d)
	for i in range(1, candidates.size()):
		var dsq: float = actor.position_2d.distance_squared_to(candidates[i].position_2d)
		if dsq < best_dsq:
			best_dsq = dsq
			best = candidates[i]
	return best
