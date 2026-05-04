## RtsWorldGameplayInstance - RTS 连续坐标战斗世界 Instance
##
## WorldGameplayInstance 子类: 持 grid (RtsBattleGrid wrapper, P1.2 替代 NavigationRegion2D)
## + 连续 Vector2 描述位置。
##
## P1.3 (S1 修复) 后, 战斗推进由 RtsAutoBattleProcedure 完全内化(不再有 per_tick callback)。
## 调方走 start_rts_battle(left, right, opts) → world.start_battle 工厂创建 procedure。
class_name RtsWorldGameplayInstance
extends WorldGameplayInstance


# ========== 字段 ==========

## 地图边界(像素), 仅供 AI / 出生点采样使用; 物理边界由 grid blocking cells 决定。
var map_size: Vector2 = Vector2(500.0, 500.0)

## RTS 战场 grid wrapper (P1.2 替代 NavigationRegion2D), 由 frontend / smoke 入口注入。
## 为 null 时 actor 退化为直线接敌(走 RtsPathfinding.find_path 的 _direct_path 分支)。
##
## **M5.5 deprecation**: RtsBattleGrid 在 M5.5 末计划被完全替换为 `navcell_grid: RtsNavcellGrid`
## 直接持有(spec §M5.5)。M5.5 阶段保留双字段:`rts_grid` 兼容老 smoke / scenario 构造,
## production code(facade / nav_agent / activity)走 `navcell_grid` 直接 + `obstruction_manager`。
var rts_grid: RtsBattleGrid = null

## M5.5: NavcellGrid 一等公民引用(从 rts_grid 内部提升)。procedure._init 设值,production code
## (facade compute / canonicalize / activity nav)直接走此字段,不再通过 rts_grid wrapper。
##
## `navcell_grid == rts_grid.get_navcell_grid()` 由 procedure._init 保证;rts_grid null 时 navcell_grid 也 null。
var navcell_grid: RtsNavcellGrid = null

## M1: Passability class 注册查询单例 (default / air); procedure._init 末尾按固定顺序注册。
## Determinism 关键 — register 顺序固化让 mask 数字 (0x1 default / 0x2 air) 跨 run 不漂。
var passability_registry: RtsPassabilityClassRegistry = null

## M2: ObstructionManager 实例 (shape 数据库 + spatial index + rasterize); procedure._init 末尾构造
## (grid + registry 都就位后)。grid 为 null 时 manager 也是 null (老 smoke 不走 frontend 时)。
##
## **M2.3 阶段**: 仅实例化, **不**接 building / unit / placement 链路 (留 M2.4 / M2.5)。
## production code (place_building / spawn unit / move tick) 仍走 RtsBattleGrid facade 路径,
## ObstructionManager 闲置不影响 baseline。
var obstruction_manager: RtsObstructionManager = null

## M4: Hierarchical pathfinder 实例 (chunk + region 可达性查询); procedure._init 末尾构造
## (obstruction_manager 之后)。grid 为 null 时此字段也是 null。
##
## **M4a 阶段**: 仅实例化 + 首次 tick step 6.7 lazy recompute; production code (player
## commands / activity) **不消费** — 0 漂移保 replay bit-identical。
## **M4b 阶段**: player commands 调 make_goal_reachable canonicalize goal → 改变路径 →
## 接受新 baseline (P1)。
## **M4c 阶段**(可选): tick step 6.7 改 incremental update 替代 lazy recompute;触发条件 =
## M4a recompute > 30 ms / tick (perf 测量后决定)。
var hierarchical_pathfinder: RtsHierarchicalPathfinder = null

## M5: LongPathfinder 朴素 A* on NavcellGrid;procedure._init 末构造(navcell_grid 之后)。
## 跟 facade 一起;callsite 一般通过 pathfinder_facade 走,极少直接用 long_pathfinder。
var long_pathfinder: RtsLongPathfinder = null

## M5: PathfinderFacade 顶层入口(聚合 NavcellGrid + Hierarchical + LongPath)。
##
## **接口**:
##   - `compute_path_immediate(start, goal, mask)` 玩家 click move 走 canonicalize → A*
##   - `compute_path_direct(start, goal, mask)` AI attack-move / harvest 不过 canonicalize → 直接 A*
##   - `is_goal_reachable(start, goal, mask)` 纯查询
##   - `make_goal_reachable(start, goal, mask)` 显式 canonicalize
var pathfinder_facade: RtsPathfinderFacade = null


# ========== 战斗 staging fields (start_rts_battle 写, _create_battle_procedure 读) ==========

## 即将开战的 left team — 仅在 start_rts_battle 调用期间有效。
var _pending_left: Array[RtsBattleActor] = []

## 即将开战的 right team — 仅在 start_rts_battle 调用期间有效。
var _pending_right: Array[RtsBattleActor] = []

## 即将传给 procedure 的 opts (含 unit_runtimes / event_sink / tick_interval_ms)。
var _pending_battle_opts: Dictionary = {}


# ========== Procedure 引用 (M2.1 Phase C) ==========

## 当前活跃 procedure; procedure._init 末尾调 bind_procedure(self) 写入。
##
## Activity 子类 (M2.1 Phase C: RtsHarvestActivity / RtsReturnAndDropActivity) 通过
## world.procedure.add_team_resources(...) 改阵营资源, 不破坏 Activity (actor, world, dt) sig。
##
## 战斗结束后 procedure GC, 此字段仍指向旧实例无影响 (Activity 只在战斗内 tick);
## 下次开战 start_rts_battle 创建新 procedure → 新 procedure._init 末尾 bind_procedure 覆盖。
var procedure: RtsAutoBattleProcedure = null


# ========== 初始化 ==========

func _init(id_value: String = "") -> void:
	super._init(id_value if id_value != "" else IdGenerator.generate("rts_world"))
	type = "rts_world"


## 注入 RtsBattleGrid。frontend / smoke 在 _ready 中构造 RtsBattleMap 后调用。
func set_grid(p_grid: RtsBattleGrid) -> void:
	rts_grid = p_grid


## 由 RtsAutoBattleProcedure._init 末尾调用; Activity 通过 world.procedure 访问 procedure API。
func bind_procedure(p: RtsAutoBattleProcedure) -> void:
	procedure = p


# ========== 战斗调度 (P1.3 S1 修复) ==========

## 启动一场 RTS 战斗。返回 procedure 引用, 调方负责 tick_once / finish。
##
## opts 键(透传给 RtsAutoBattleProcedure._init):
##   - tick_interval_ms: float
##   - unit_runtimes: Dictionary[actor_id, {ai, agent}]
##   - event_sink: Callable(events: Array[Dictionary])
func start_rts_battle(
	left: Array[RtsBattleActor],
	right: Array[RtsBattleActor],
	opts: Dictionary = {},
) -> RtsAutoBattleProcedure:
	_pending_left = left
	_pending_right = right
	_pending_battle_opts = opts

	var participants: Array[Actor] = []
	for a in left:
		participants.append(a)
	for a in right:
		participants.append(a)

	var procedure := start_battle(participants) as RtsAutoBattleProcedure

	# 清 pending state 让 GC 在 procedure 释放后能 release left/right reference
	_pending_left = []
	_pending_right = []
	_pending_battle_opts = {}

	return procedure


## 工厂钩子: WorldGameplayInstance.start_battle 调用此函数创建 procedure。
## 读 _pending_* 字段构造 RtsAutoBattleProcedure。
func _create_battle_procedure(_participants: Array[Actor]) -> BattleProcedure:
	return RtsAutoBattleProcedure.new(self, _pending_left, _pending_right, _pending_battle_opts)


# ========== Actor registry ==========

## 仅返回存活的 actor id 集合, 服务 EventProcessor.process_post_event 广播。
## RtsBattleActor 子类暴露 is_dead(); 非 RtsBattleActor 视作非战斗对象, 不进集合。
##
## 过滤 ability_set == null 的纯 data actor (如 RtsResourceNode), 因 process_post_event
## 走 IAbilitySetOwner.get_ability_set 后 assert 非 null — 没 ability_set 的 actor
## 不参与事件广播.
func get_alive_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor in get_actors():
		if not (actor is RtsBattleActor):
			continue
		var battle_actor := actor as RtsBattleActor
		if battle_actor.is_dead():
			continue
		if battle_actor.ability_set == null:
			continue
		result.append(actor.get_id())
	return result


func get_alive_actors() -> Array[RtsBattleActor]:
	var result: Array[RtsBattleActor] = []
	for actor in get_actors():
		if actor is RtsBattleActor and not (actor as RtsBattleActor).is_dead():
			result.append(actor as RtsBattleActor)
	return result


## 仅返回存活的 RtsUnitActor (排除 RtsBuildingActor)。
## P1.2 push-out / nav tick 等"对单位生效"的循环用此过滤。
func get_alive_units() -> Array[RtsUnitActor]:
	var result: Array[RtsUnitActor] = []
	for actor in get_actors():
		if actor is RtsUnitActor and not (actor as RtsUnitActor).is_dead():
			result.append(actor as RtsUnitActor)
	return result
