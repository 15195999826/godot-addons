## RtsComputerPlayer - team-level AI 对手 (M2.2)
##
## 每 DECISION_INTERVAL_TICKS (30 tick = 1s @ 30Hz) 决策一次, 走 RtsPlayerCommandQueue
## 与玩家同接口 enqueue PlaceBuildingCommand / MoveUnitsCommand, 保 bit-identical replay。
##
## 不持有 procedure ref (避免循环); world.procedure 已就位 (M2.1 Phase C),
## 通过 world.procedure.* 访问 procedure API。
##
## 不变量:
##   - decide 只读 world / procedure 状态, 不写 actor / system 内部字段
##   - _attack_dispatched 由 procedure 管理生命周期 (procedure-attached object → 决定性 OK)
##   - 决定性来源 = 同 game state → 同决策; barracks 数每决策 tick 重新查 (不缓存)
##
## 决策来源: task-plan/m2-2-ai-opponent/README.md §设计决策表 E1-E10
class_name RtsComputerPlayer
extends RefCounted


# ========== 决策粒度 ==========

## E3 — 每 30 tick (1s @ 30Hz) 触发一次决策; 非决策 tick think() 直接返
const DECISION_INTERVAL_TICKS: int = 30


# ========== 字段 ==========

## 阵营 ID (0=left, 1=right; 与 RtsBattleActor.team_id 对齐)
var team_id: int = -1

## E6 cache: 是否已发出过 attack-move 命令 (M2.2 不做反复跟随, only-once)
var _attack_dispatched: bool = false


# ========== 初始化 ==========

func _init(p_team_id: int) -> void:
	team_id = p_team_id


# ========== 决策入口 ==========

## procedure tick 末尾调用 — 非决策 tick (current_tick % DECISION_INTERVAL_TICKS != 0)
## 直接返。决策 tick 顺序:
##   1. _try_build_barracks: 资源 ≥ cost + barracks 数 == 0 → enqueue PlaceBuildingCommand
##   2. _try_attack: alive non-worker unit ≥ 3 → enqueue MoveUnitsCommand (only-once)
func think(world: RtsWorldGameplayInstance, current_tick: int) -> void:
	if world == null:
		return
	if current_tick % DECISION_INTERVAL_TICKS != 0:
		return
	_try_build_barracks(world, current_tick)
	_try_attack(world, current_tick)


# ========== 决策实现 (E.1 占位; E.2 / E.3 实现) ==========

## E2 — Build 决策: barracks 1 cap, ct 偏移点。E.2 实现。
func _try_build_barracks(_world: RtsWorldGameplayInstance, _current_tick: int) -> void:
	pass


## E3 — Attack 决策: ≥3 non-worker unit 后 attack-move 一次。E.3 实现。
func _try_attack(_world: RtsWorldGameplayInstance, _current_tick: int) -> void:
	pass
