## RtsAIStrategyFactory - AI 策略工厂(static var 共享实例, S3 修复)
##
## 与 hex example/AIStrategyFactory 同构 — 同种 unit_class 所有 actor 共用一个策略实例
## (因为策略是无状态共享的, decide 是 pure function)。
##
## P1.5 仅一种策略 (RtsBasicAttackStrategy); Phase 2 P2.4 加 AutoTargetSystem 后可能演化
## 出 RtsRangedSupportStrategy / RtsCarrierAttackStrategy 等。
class_name RtsAIStrategyFactory


# ========== 共享实例(无状态, 可安全共享) ==========

static var _basic_attack: RtsAIStrategy = RtsBasicAttackStrategy.new()


## 根据 unit_class 获取 AI 策略。
##
## P1.5 melee / ranged 都走 basic_attack — 行为差异在数值上(attack_range / move_speed),
## 不在策略上。Phase 2 P2.4 AutoTargetSystem + Activity 后可能拆出 ranged-specific 策略
## (如 ranged 持距离 / 撤退微操)。
##
## M2.1 Phase B: WORKER 也复用 basic_attack — worker target_layer_mask=NONE 让
## AutoTargetSystem 在 mover 阶段 skip, 永不写 _cached_target_id; basic_attack.decide 因
## cached 空返 IdleActivity → worker 自然 idle。Phase C 启动 RtsHarvestStrategy 替代此分支。
static func get_strategy(unit_class: RtsUnitClassConfig.UnitClass) -> RtsAIStrategy:
	match unit_class:
		RtsUnitClassConfig.UnitClass.MELEE:
			return _basic_attack
		RtsUnitClassConfig.UnitClass.RANGED:
			return _basic_attack
		RtsUnitClassConfig.UnitClass.WORKER:
			return _basic_attack
		_:
			return _basic_attack
