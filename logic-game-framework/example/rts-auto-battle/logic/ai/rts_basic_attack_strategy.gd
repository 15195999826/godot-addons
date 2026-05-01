## RtsBasicAttackStrategy - "找最近敌人, 持续攻击" 策略 (S3 修复; P2.1 返回 Activity; P2.4 读 cache)
##
## P2.1 重写: 不再返回 string Intent dict; decide 返回 RtsAttackActivity (含 in-range/out-of-range
## 自管理) 或 RtsIdleActivity (无敌)。AttackActivity 内部处理"approach + attack"两态切换,
## 避免 controller 抖动 nav 状态。
##
## P2.4 重写: decide 不再自己扫描敌人 — 直接读 actor._cached_target_id (RtsAutoTargetSystem 写)。
## 这样:
##   1. 全场扫敌 O(N²) 从 N 个 strategy.decide 摊到一个 system 的 O(RESCAN_INTERVAL_TICKS×N²/N) 频率
##   2. priority 标签 (target_priorities + unit_tags) 在 system 一处生效, 策略保持纯
##   3. stance (HOLD_FIRE / DEFENSIVE / AGGRESSIVE) 由 system 决定是否给 unit 分配 cache, 策略只读
##
## 决策树 (P2.4 简化):
##   - actor 死亡 / world 空 → IdleActivity
##   - _cached_target_id 空或 cached 已死 → IdleActivity (AutoTargetSystem 下个 tick 会重 scan)
##   - cached 存活 → AttackActivity(cached.id) (controller 复用直至下次 cache 切换)
class_name RtsBasicAttackStrategy
extends RtsAIStrategy


func decide(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> RtsActivity:
	if actor == null or actor.is_dead() or world == null:
		return RtsIdleActivity.new()

	var target := _resolve_cached_target(actor, world)
	if target == null:
		return RtsIdleActivity.new()

	return RtsAttackActivity.new(target.get_id())


# ========== 内部 ==========

## 读 actor._cached_target_id; 仍存活 → 返回; 否则 null。
##
## P2.4 不再做 fallback 全场扫描 — 那是 RtsAutoTargetSystem 的职责; 策略保持 pure 读。
## 边界 case: AutoTargetSystem 没运行过 (cache 一直空) → 单位永远 Idle, 但这种情况只在没接
## procedure 主循环的特殊测试里发生, 正式 procedure tick 顺序保证 cache 在 strategy 之前写好。
func _resolve_cached_target(actor: RtsUnitActor, world: RtsWorldGameplayInstance) -> RtsUnitActor:
	var cached_id: String = actor._cached_target_id
	if cached_id.is_empty():
		return null
	var cached := world.get_actor(cached_id) as RtsUnitActor
	if cached == null or cached.is_dead():
		return null
	return cached
