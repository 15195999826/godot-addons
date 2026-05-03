## RtsAutoBattleProcedure - RTS 自动战斗过程(P1.3 内化主循环)
##
## P1.3 修复 S1 (主循环散落 5 处): tick_once() 内化 AI / nav / cooldown / attack /
## push-out 推进, 调方不再传 per_tick callback。RtsBasicAI / RtsNavAgent 通过
## opts.unit_runtimes 注入 (actor_id → {ai, agent})。
##
## 与 HexBattleProcedure 的差异:
##   - 没有 ATB 累积; cooldown 走 ability_set tag-duration (P1.6 修 M4 后)
##   - 没有"施法施放"显式段; basic attack 由 AI 在 cooldown 到 0 时即时触发
##   - 不广播投射物事件(M0 无投射物 entity)
##
## 决策来源:
##   - architecture-baseline.md §5 (Procedure 主循环, S1 修复后)
##   - phase-1-foundation.md P1.3 (5 处 demo+smoke 改走 world.start_battle 或 procedure 直接调)
##
## 调方 contract: 跑 tick_once 之前必须 procedure.start(); 跑完调 procedure.finish()。
class_name RtsAutoBattleProcedure
extends BattleProcedure


## 安全上限。默认 1800 ticks, 配合 33.33ms tick_interval ≈ 60s 真实时间。
## 战斗未在此期间内分出胜负即判 timeout(smoke 记 FAIL)。
const MAX_TICKS := 1800

## 默认 tick 间隔(毫秒)。30Hz fixed-tick (D3-A) — P1.7 改为 33.333ms (1000/30)。
## 调方仍可在 opts.tick_interval_ms 覆盖(老 smoke 起步用 50ms 也支持向后兼容)。
const RTS_TICK_INTERVAL_MS := 1000.0 / 30.0


# ========== 字段 ==========

var left_team: Array[RtsBattleActor] = []
var right_team: Array[RtsBattleActor] = []

var _world_instance: RtsWorldGameplayInstance = null
var _result: String = ""

## actor_id → RtsUnitController (P1.5 S3 修复后的形式)
## controller 持 strategy(共享无状态) + agent + 每 actor 的 nav refresh 计时 / 上 tick intent。
var _unit_runtimes: Dictionary = {}

## 事件 sink (smoke logger 用): 每 tick 在 flush 之前调用, 收 events 副本镜像。
## 用 Callable 是为了不强耦合 logger 类型 — smoke 想要日志就传, 不要就空。
var _event_sink: Callable = Callable()

## P1.4 (S2 修复): 共享 RtsBasicAttackAction 实例。每个 attacker 走同一个 action,
## 通过 ExecutionContext.ability_ref.owner_actor_id 区分 source。
var _basic_attack_action: RtsBasicAttackAction = null

## P1.7 light determinism: 战斗起始时重置 RtsRng 用的种子, 也存进 world_snapshot 给 replay。
var _rng_seed: int = 0

## P1.7 录像最简骨架: 仅含 rng_seed (Phase 2 P2.7 接 BattleRecorder 时扩为完整 RtsRecording)。
## smoke 通过 procedure.get_world_snapshot() 读 rng_seed 用于决定性比对。
var _world_snapshot: Dictionary = {}

## P2.2: 单位邻接 spatial hash, lazy 创建于第一 tick。每 tick 调 update_all 全量增量同步。
var _spatial_hash: RtsSpatialHash = null

## P2.3: 单位 stuck 检测 + local repath + 失败降级, lazy 创建。每 tick 在 step 4c 之后调 tick。
var _stuck_detector: RtsStuckDetector = null

## P2.4: AutoTarget system, lazy 创建。每 tick 在 controller.tick 之前调一次, 写 _cached_target_id;
## 全量 rescan 间隔 = RESCAN_INTERVAL_TICKS (20 ticks); cache 失效单位本 tick 立即重扫。
var _auto_target_system: RtsAutoTargetSystem = null

## P2.5: Production system, lazy 创建。每 tick 在 step 4 (movement) 之后调一次,
## 累积 building.production_progress_ms; 满周期触发 _unit_spawner 回调实际创建单位。
var _production_system: RtsProductionSystem = null

## P2.5: 单位 spawner 回调 (smoke / 调方提供); 签名:
##   func(building: RtsBuildingActor) -> RtsUnitActor
## 返回非 null 视为 spawn 成功, production_system 减一周期; 返回 null 视为失败, 周期不重置。
##
## 调方负责在 spawner 内: 创建 RtsUnitActor + add_actor + 注册 nav agent / controller +
## add_unit_to_team(unit, team_id) + set_activity_chain(初始 attack-move 链)。
var _unit_spawner: Callable = Callable()

## P2.6: team_id (int) → RtsTeamConfig (build_zone / starting_resources / crystal_tower_id /
## faction_id)。opts.team_configs 不传时, 内部用 unconfigured(team_id) 占位 (旧 smoke 行为)。
var _team_configs: Dictionary = {}

## M2.1 Phase A — team_id (int) → 当前剩余资源 (Dictionary[String, int]; key = "gold" / "wood");
## 初始化时深拷自 team_config.starting_resources, PlaceBuildingCommand 通过
## spend_team_resources(team_id, cost: Dictionary) 逐 key 扣减。读 API get_team_resources 返
## 拷贝防外部改 reference。Phase D 会加 add_team_resources (worker harvest drop-off 用)。
var _team_resources: Dictionary[int, Dictionary] = {}

## P2.6: 玩家命令队列; opts.player_command_queue 不传时按需 lazy 创建 (但若没人 enqueue, apply 也是 no-op)。
##
## 调方推命令: procedure.enqueue_player_command(cmd) (或直接 _player_command_queue.enqueue)。
## tick_once step 2 调 apply_due 应用所有 tick_stamp ≤ current_tick 的命令。
var _player_command_queue: RtsPlayerCommandQueue = null

## P2.6: 已应用 player commands 流式录像 (含成功 / 失败); 每 tick step 2 之后 append。
##
## Phase 2 P2.7 加 BattleRecorder 时把此字段持续 append 到 RtsRecording.player_commands;
## smoke / replay 可通过 get_player_commands_log() 读取。
var _player_commands_log: Array[Dictionary] = []

## M2.2 — team-level AI 对手实例; 默认空 (E10 决策 — procedure 不主动创建,
## smoke / demo 显式调 attach_computer_player(team_id) 才入)。
##
## tick 末尾循环调 cp.think(world, _current_tick) — AI enqueue 的命令在下一 tick step 1.5 应用。
##
## E10 决策保旧 smoke 行为不破: 既有 12 项 smoke 不 attach AI → think 路径不进 → 数字 0 漂移。
var _computer_players: Array[RtsComputerPlayer] = []


# ========== 初始化 ==========

## opts 键:
##   - tick_interval_ms: float                 每帧毫秒(默认 RTS_TICK_INTERVAL_MS)
##   - unit_runtimes: Dictionary               actor_id → RtsUnitController (P1.5 后)
##                                             procedure tick 时按此 map 推进单位行为
##   - event_sink: Callable                    签名 func(events: Array[Dictionary])
##                                             每 tick 在 flush 前调一次, 给 smoke logger 用
##   - rng_seed: int                           P1.7 light determinism: 战斗起始 RtsRng.set_seed(seed),
##                                             并写入 world_snapshot.rng_seed; 同 seed → 同 winner
##   - unit_spawner: Callable                  P2.5: production_system spawn 单位 (见上方 _unit_spawner 注释)
##   - team_configs: Dictionary[int, RtsTeamConfig]  P2.6: 阵营配置 (build_zone / starting_resources /
##                                             crystal_tower_id / faction_id); 不传时按需 unconfigured
##   - player_command_queue: RtsPlayerCommandQueue  P2.6: 玩家命令队列; 不传时按需 lazy 创建
func _init(
	world: RtsWorldGameplayInstance,
	left: Array[RtsBattleActor],
	right: Array[RtsBattleActor],
	opts: Dictionary = {},
) -> void:
	var all_actors: Array[Actor] = []
	for a in left:
		all_actors.append(a)
	for a in right:
		all_actors.append(a)
	super._init(world, all_actors)
	_world_instance = world
	left_team = left
	right_team = right
	_tick_interval = float(opts.get("tick_interval_ms", RTS_TICK_INTERVAL_MS))
	_unit_runtimes = opts.get("unit_runtimes", {})
	if opts.has("event_sink"):
		_event_sink = opts.get("event_sink", Callable()) as Callable
	if opts.has("unit_spawner"):
		_unit_spawner = opts.get("unit_spawner", Callable()) as Callable

	# P1.7: rng_seed 起手就立; 同时把 RtsRng autoload 重置 — procedure 起始即拿到确定性 RNG。
	_rng_seed = int(opts.get("rng_seed", 0))
	_world_snapshot = { "rng_seed": _rng_seed }
	RtsRng.set_seed(_rng_seed)

	# P1.4: 共享 action 实例 + CurrentUnitTarget selector. 每 tick 给所有 attackers 复用。
	_basic_attack_action = RtsBasicAttackAction.new(RtsTargetSelectors.current_unit_target())

	# P2.6: team_configs + player_command_queue 装配 (旧 smoke 不传时占位行为不破)。
	_install_team_configs(opts.get("team_configs", {}) as Dictionary)
	if opts.has("player_command_queue"):
		_player_command_queue = opts.get("player_command_queue", null) as RtsPlayerCommandQueue

	# M2.1 Phase C: 让 world 持当前 procedure 引用, Activity 通过 world.procedure 访问 procedure API。
	world.bind_procedure(self)

	# M1.1: PassabilityClassRegistry — 注册顺序固化是 replay determinism 关键。
	# default 先 (bit_index=0, mask=0x1) → air 后 (bit_index=1, mask=0x2)。
	# 顺序换会让 NavcellGrid 上所有 mask 数字漂, 破 replay bit-identical (R5 P1 决策)。
	if world.passability_registry == null:
		var registry := RtsPassabilityClassRegistry.new()
		var ground_cfg := RtsPassabilityClassConfig.new()
		ground_cfg.class_name_id = "default"
		ground_cfg.clearance = 14.0
		registry.register(ground_cfg)
		var air_cfg := RtsPassabilityClassConfig.new()
		air_cfg.class_name_id = "air"
		air_cfg.clearance = 8.0
		registry.register(air_cfg)
		world.passability_registry = registry

	# M1.4: 把 registry attach 到 grid; grid 自此走 NavcellGrid 路径 (双写 model 兼容老 smoke)。
	# grid 可能为 null (smoke 不走 frontend / scenario 时), 此时跳过 attach, 老 smoke 走 fallback。
	if world.rts_grid != null:
		world.rts_grid.attach_passability_registry(world.passability_registry)

	# M2.3: 构造 ObstructionManager (依赖 navcell_grid + registry, 必须 attach 之后)。
	# **M2.3 仅实例化**, building / unit / placement 链路改造留 M2.4 / M2.5; 此处 manager 闲置,
	# 不影响 baseline 0 漂移。grid 为 null 时跳过 (老 smoke 不走 frontend)。
	if world.rts_grid != null and world.rts_grid.has_navcell_grid():
		world.obstruction_manager = RtsObstructionManager.new(
			world.rts_grid.get_navcell_grid(),
			world.passability_registry,
		)


# ========== 生命周期 ==========

## 战斗起始钩子 — super.start() 触发 in_combat 标志 + recorder; P2.5 在此基础上把所有
## 起手 RtsBuildingActor 的 footprint 写入 world.rts_grid (建筑硬阻挡 pathing map)。
##
## 起手注册而非 add_actor 时注册的理由: smoke / 调方常在 add_actor 之后才 set position_2d,
## 此时 footprint cells 还不对; 把注册推迟到 start() 让所有建筑 position 已就位。
##
## 战斗中通过 P2.6 玩家命令 / P2.5 spawner 新增建筑时, 由调方负责自行调
## world.rts_grid.place_building (通常在 PlaceBuildingCommand 内做)。
##
## P2.6 自动绑定 crystal_tower_id: 若起手已放置 is_crystal_tower=true 的建筑且对应 team_config
## 还没绑 crystal_tower_id, 此处自动写入 — smoke 不需要手动 set crystal_tower_id 即可享胜负判定。
func start() -> void:
	super.start()
	var world := _world_instance
	if world == null or world.rts_grid == null:
		return
	for actor in get_all_actors():
		if not (actor is RtsBuildingActor):
			continue
		var building := actor as RtsBuildingActor
		if building.is_dead():
			continue
		# M0.5 — procedure.start 时建筑已被 demo / scenario / smoke 调方 set position_2d, 这里
		# sync obstruction_shape.center 到 position_2d + offset, 必须在 get_footprint_cells 前.
		building.sync_obstruction_shape()
		var footprint: Array = building.get_footprint_cells(world.rts_grid)
		world.rts_grid.place_building(building.get_id(), footprint)
		# M2.4 — 起手已 placed building 也注册到 ObstructionManager (dual-write 模式).
		# manager 为 null (老 smoke 不走 frontend 创 grid) / shape 为 null (factory 未注入) 时跳过,
		# 跟 place_building 行为一致 — 全程 baseline 0 漂移。
		if world.obstruction_manager != null and building.obstruction_shape != null:
			var shape := building.obstruction_shape
			building.obstruction_tag = world.obstruction_manager.add_static_shape(
				building.get_id(),
				shape.center,
				shape.rotation_rad,
				shape.width,
				shape.height,
				RtsObstructionFlags.BLOCK_PATHFINDING | RtsObstructionFlags.BLOCK_FOUNDATION,
				str(building.team_id),
			)
		# P2.6: 自动绑 crystal_tower_id 给 team_config (若尚未配)
		if building.is_crystal_tower:
			var cfg: RtsTeamConfig = _team_configs.get(building.get_team_id(), null) as RtsTeamConfig
			if cfg != null and cfg.crystal_tower_id == "":
				cfg.crystal_tower_id = building.get_id()


func tick_once() -> void:
	if _finished:
		return
	_current_tick += 1

	var world := _world_instance
	if world == null:
		return

	var dt_seconds: float = _tick_interval / 1000.0

	# 1. 框架级 system tick (system 在 base_tick 内推进)
	world.base_tick(_tick_interval)

	# 1.5 P2.6: 玩家命令应用段 — 走 _player_command_queue.apply_due 把所有 tick_stamp ≤
	#     _current_tick 的命令应用 (placement / 升级 / 卖建筑 / 单位下命令); 失败命令不静默丢弃,
	#     进 _player_commands_log 给 replay / UI 反馈。
	#     旧 smoke 没设 _player_command_queue → 跳过 (no-op)。
	if _player_command_queue != null:
		var applied: Array[Dictionary] = _player_command_queue.apply_due(self, world, _current_tick)
		for entry in applied:
			_player_commands_log.append(entry)

	# 2. 单位 AbilitySet tick (cooldown / buff duration 等)
	#    传 _tick_interval (ms) + 当前 logic_time (ms) — 与 hex BattleProcedure 一致, 让
	#    add_auto_duration_tag 的 duration_ms 单位对齐。
	for actor in get_alive_actors():
		var ability_set := _safe_get_ability_set(actor)
		if ability_set != null:
			ability_set.tick(_tick_interval, get_logic_time())

	# 2.5 P2.4 (P2.8 扩到建筑): AutoTargetSystem 写 _cached_target_id (在 strategy.decide 之前)。
	#     每 RESCAN_INTERVAL_TICKS (20) tick 全量重评; cache 失效 actor 本 tick 立即单独重扫。
	#     P2.8: 入参从 alive_units 改 alive_actors (含建筑) — 让单位可以选 building (e.g. 水晶塔)
	#     当目标; 让 building (e.g. archer_tower) 也作为 mover 写自己的 cached_target_id。
	if _auto_target_system == null:
		_auto_target_system = RtsAutoTargetSystem.new()
	# step 2.5 + step 3 同 tick 内不增删 actor, 共用一份 alive 列表 (省一次 O(N) 遍历 + Array alloc)
	var alive_actors: Array = world.get_alive_actors()
	_auto_target_system.tick(world, alive_actors)

	# 3. Actor 行为推进: 单位走 controller / activity, 建筑走攻击直读 cached_target_id。
	#    Unit:    controller.tick → strategy.decide → reconcile current_activity → advance。
	#             strategy.decide 读 actor._cached_target_id (AutoTargetSystem 在 step 2.5 填好)。
	#             Activity tick 仅维护 nav target / wants_to_attack — **不写 position** (P2.2 拆分);
	#             实际移动留给 step 4 的 compute_velocity → steering → integrate 三段管线。
	#    Building (P2.8): 没 controller / activity, procedure 直接读 _cached_target_id, 范围内
	#                     + cooldown ready → 触发 BasicAttackAction (e.g. archer_tower 防空)。
	for actor in alive_actors:
		if actor is RtsUnitActor:
			var unit := actor as RtsUnitActor
			var controller := _unit_runtimes.get(unit.get_id(), null) as RtsUnitController
			if controller != null:
				controller.tick(dt_seconds, world)

			# P1.6 (修 M4): cooldown 走 ability_set.tag_container, ability_set.tick (步骤 2)
			# 已自动 cleanup 过期 tag → can_attack 直接查 has_tag。
			# P2.8: target 不再强制 cast 为 RtsUnitActor — 单位可以打 building (水晶塔等)。
			if controller != null and controller.wants_to_attack() and unit.can_attack():
				var target_id: String = unit.current_target_id
				if target_id != "":
					var target := world.get_actor(target_id) as RtsBattleActor
					if target != null and not target.is_dead():
						_invoke_basic_attack(unit, world)
						unit.start_attack_cooldown()
		elif actor is RtsBuildingActor:
			# P2.8: 建筑攻击循环 — 没 strategy / activity, 直接读 _cached_target_id 决定是否 fire。
			var building := actor as RtsBuildingActor
			if building.target_layer_mask == MovementLayer.MASK_NONE:
				continue  # 兵营 / 水晶塔 不参战
			var cached_id: String = building._cached_target_id
			if cached_id.is_empty():
				continue
			var target_b := world.get_actor(cached_id) as RtsBattleActor
			if target_b == null or target_b.is_dead():
				continue
			# 与 RtsAttackActivity.RANGE_TOLERANCE = 1.05 对齐, 浮点 + 边界一致体验
			var atk_range_with_tol: float = building.get_attack_range() * 1.05
			var dist_sq: float = building.position_2d.distance_squared_to(target_b.position_2d)
			if dist_sq > atk_range_with_tol * atk_range_with_tol:
				continue
			if not building.can_attack():
				continue
			building.current_target_id = cached_id  # CurrentUnitTarget selector 读此字段
			_invoke_basic_attack(building, world)
			building.start_attack_cooldown()

	# 4. P2.2 移动管线: spatial_hash → compute_velocity → steering → integrate
	#    替代 Phase 1 的"nav_agent.tick (compute+integrate 一体) + RtsMinimalPushOut.resolve"。
	#    新流程让 steering 可以在 nav 写出 desired velocity 后、整合 position 之前修改 velocity,
	#    实现 separation + deflection 避障 (P2.2 避障层 1+2)。
	var alive_units: Array = world.get_alive_units()
	if _spatial_hash == null:
		_spatial_hash = RtsSpatialHash.new()
	_spatial_hash.update_all(alive_units)

	# 4a. 每个有 nav 的单位写 desired velocity (waypoint 方向 × move_speed; 无 path → 0)
	for unit in alive_units:
		var ru := unit as RtsUnitActor
		var ctrl := _unit_runtimes.get(ru.get_id(), null) as RtsUnitController
		if ctrl != null and ctrl.agent != null:
			ctrl.agent.compute_desired_velocity(dt_seconds)

	# 4b. Steering 修改 velocity: separation + deflection (静止单位与建筑跳过)
	for unit in alive_units:
		var ru2: RtsUnitActor = unit as RtsUnitActor
		RtsUnitSteering.apply(ru2, _spatial_hash, world, dt_seconds)

	# 4c. 整合 position += velocity * dt + 推进 waypoint (steering 推过头时跳号)
	for unit in alive_units:
		var ru3: RtsUnitActor = unit as RtsUnitActor
		var ctrl3: RtsUnitController = _unit_runtimes.get(ru3.get_id(), null) as RtsUnitController
		if ctrl3 != null and ctrl3.agent != null:
			ctrl3.agent.integrate(dt_seconds)

	# 4d. P2.3 stuck detection: 跟踪本 tick 后实际位移; STUCK_TICK_THRESHOLD 内未动 →
	#     local repath; 连续 MAX_REPATH_FAILURES 次失败 → controller.abandon_command (Idle 降级)
	if _stuck_detector == null:
		_stuck_detector = RtsStuckDetector.new()
	_stuck_detector.tick(alive_units, _unit_runtimes)

	# 4f. M2.5 — 同步 unit obstruction shape 到 ObstructionManager (dual-write 模式):
	#     新 spawn 单位 (obstruction_tag == 0) → add_unit_shape 注册, 拿 tag 存到 actor.obstruction_tag;
	#     已注册单位 → move_shape(tag, position_2d) 同步 _spatial_index 内位置。
	#     manager 为 null 时跳过 (老 smoke 不走 frontend); production code 不消费 manager._shapes,
	#     baseline 0 漂移。
	#     **Death unregister deferred** (spec drift): 不在死亡时反注册, _shapes 持续膨胀直到战斗结束,
	#     procedure GC 时随 manager 一并 release; M5 切 pathfinder 时再加完整 cleanup。
	if world.obstruction_manager != null:
		_sync_unit_obstruction_shapes(world, alive_units)

	# 4e. P2.5 production system: 走全部 alive RtsBuildingActor, 累积 production_progress_ms,
	#     满周期触发 _unit_spawner 回调 (smoke / 调方负责实际 add_actor + nav agent + controller +
	#     add_unit_to_team + initial activity chain)。
	if _unit_spawner.is_valid():
		if _production_system == null:
			_production_system = RtsProductionSystem.new()
		_production_system.tick(_tick_interval, world, _unit_spawner)

	# 5. Event sink (smoke logger 镜像) — 必须在 record_current_frame_events 之前
	#    (后者会 flush 清空 collector)。
	if _event_sink.is_valid():
		_event_sink.call(GameWorld.event_collector.collect())

	# 6. 录像帧
	record_current_frame_events()

	# 6.5 M2.2 — AI 对手决策 (E10 — 默认空, attach_computer_player 显式入)
	#     非决策 tick (current_tick % 30 != 0) think() 直接返; 决策 tick AI enqueue
	#     PlaceBuildingCommand / MoveUnitsCommand → 下一 tick step 1.5 apply_due 应用。
	#     放在录像帧之后 — think 不影响本 tick events; 放在胜负判定之前 — 让最后一 tick
	#     AI 决策也被记录 (但战斗已结束的下一 tick 不会被 apply, 自然丢弃)。
	for cp in _computer_players:
		cp.think(world, _current_tick)

	# 7. 胜负判定
	if _current_tick >= MAX_TICKS:
		_result = "timeout"
		mark_finished()
	else:
		_check_battle_end()


## P2.7: finish 在 BattleRecorder.stop_recording 返回的 dict 上注入 RTS 专属字段:
##   - "player_commands": _player_commands_log 副本 (P2.6 P2.7 联动 — bit-identical replay 用)
##   - "rng_seed": _rng_seed (Phase 1 light determinism; world_snapshot 也存了一份)
##
## 不修改 stdlib BattleRecorder; 仅在 RTS 层 wrap 输出 dict. 调方 (smoke / replay player) 通过此
## 增量字段可还原"同 seed + 同 player_commands → 同 event_timeline" 的完整 replay 信息.
func finish(result: String = "") -> Dictionary:
	var effective := result if result != "" else _result
	if effective == "":
		effective = "battle_complete"
	var record: Dictionary = super.finish(effective)
	record["player_commands"] = _player_commands_log.duplicate()
	record["rng_seed"] = _rng_seed
	return record


# ========== 查询 ==========

func get_all_actors() -> Array[RtsBattleActor]:
	var result: Array[RtsBattleActor] = []
	result.append_array(left_team)
	result.append_array(right_team)
	return result


func get_alive_actors() -> Array[RtsBattleActor]:
	var result: Array[RtsBattleActor] = []
	for actor in get_all_actors():
		if not actor.is_dead():
			result.append(actor)
	return result


## P2.5: 把战斗中新生成的单位加入指定阵营的 team 列表。
##
## 调方 (production_system 的 spawner / 未来玩家命令) 在 actor 已 add_actor + 配齐 controller
## 之后调用; 让 _check_battle_end 把这些后加入的单位也算入存活计数。
##
## team_id 必须是 0 (left) 或 1 (right); 其它值会 Log.assert_crash。
func add_unit_to_team(unit: RtsBattleActor, team_id: int) -> void:
	Log.assert_crash(unit != null, "RtsAutoBattleProcedure", "add_unit_to_team: unit is null")
	if team_id == 0:
		left_team.append(unit)
	elif team_id == 1:
		right_team.append(unit)
	else:
		Log.assert_crash(false, "RtsAutoBattleProcedure", "add_unit_to_team: invalid team_id %d" % team_id)
	# 与 _init 中 super._init(world, all_actors) 同步: 让 base 类的 _participants_ids 也含新成员,
	# 但 base BattleProcedure 没暴露 _participants_ids; 这里只更新 left/right_team — _check_battle_end
	# 直接走 left_team / right_team, 不依赖 base 的 participant tracking。


func get_result() -> String:
	return _result


## P1.7: 返回 world_snapshot dict (Phase 1 仅含 rng_seed; Phase 2 P2.7 扩为完整 RtsRecording 形态)。
func get_world_snapshot() -> Dictionary:
	return _world_snapshot.duplicate()


func get_rng_seed() -> int:
	return _rng_seed


# ========== 胜负判定 ==========

## P2.6 改写: crystal_tower-死亡 优先, 否则 fallback 到 team-wipeout (Phase 1 兼容)。
##
## 每队的"是否败"判定:
##   - team_config.has_crystal_tower(): crystal_tower 死亡 (或被 world 清掉) → 败
##   - 否则: team 全灭 (Phase 1 行为) → 败
##
## 双败 = draw; 仅一队败 = 另一队胜。
func _check_battle_end() -> bool:
	var left_lost := _is_team_lost(0, left_team)
	var right_lost := _is_team_lost(1, right_team)

	if left_lost and right_lost:
		_result = "draw"
		mark_finished()
		return true
	if left_lost:
		_result = "right_win"
		mark_finished()
		return true
	if right_lost:
		_result = "left_win"
		mark_finished()
		return true
	return false


## 给定 team_id 与该 team 的 actor 列表, 判该 team 是否已败。
##
## crystal_tower 模式 (team_config.has_crystal_tower):
##   - 找 actor_id == crystal_tower_id 的 actor
##   - 不存在 / is_dead() → 败
##
## 兼容模式 (无 crystal_tower 配置):
##   - team 全灭 → 败 (Phase 1 行为)
func _is_team_lost(team_id: int, team_actors: Array[RtsBattleActor]) -> bool:
	var cfg: RtsTeamConfig = _team_configs.get(team_id, null) as RtsTeamConfig
	if cfg != null and cfg.has_crystal_tower():
		var ct_id: String = cfg.crystal_tower_id
		# 在 team 列表里找 (常用 path); 找不到也找 world (PlaceBuildingCommand 后 add_unit_to_team 应已加, 但保险)
		for actor in team_actors:
			if actor.get_id() == ct_id:
				return actor.is_dead()
		# team 列表没找到 → 兼容查 world
		if _world_instance != null:
			var ct: Actor = _world_instance.get_actor(ct_id)
			if ct == null:
				return true
			if ct is RtsBattleActor:
				return (ct as RtsBattleActor).is_dead()
		return true
	# 兼容模式: team 全灭判定
	for actor in team_actors:
		if not actor.is_dead():
			return false
	return true


# ========== P2.6 玩家命令 / 阵营资源 公共 API ==========

## 把命令加入队列。tick_stamp 早于 _current_tick 也会被立刻 apply_due (overdue 命令也算 due)。
##
## 调用顺序:
##   - 战斗起手前: 推 tick_stamp = 0 命令 (起手放兵营 / 配水晶塔)
##   - tick 之间: 推未来 tick_stamp 命令 (玩家在 tick 30 放兵营 → tick_stamp=30)
##
## 命令对象一旦 enqueue 由 procedure 持有引用, 不要外部继续修改字段 — 决定性会破。
func enqueue_player_command(cmd: RtsPlayerCommand) -> void:
	if cmd == null:
		return
	if _player_command_queue == null:
		_player_command_queue = RtsPlayerCommandQueue.new()
	_player_command_queue.enqueue(cmd)


## 取阵营 config (PlaceBuildingCommand 校验 build_zone 时调; 玩家未配置 → 返回默认 unconfigured)。
##
## 返回 null 仅当 team_id 既不在 0/1 也未在 install_team_configs 时占位 — 一般不会发生。
func get_team_config(team_id: int) -> RtsTeamConfig:
	return _team_configs.get(team_id, null) as RtsTeamConfig


## 取阵营当前剩余资源 (PlaceBuildingCommand 校验花费时调)。
##
## M2.1 Phase A — 返回 Dictionary[String, int] 拷贝 (key = 资源种类; 缺 key 由调方 .get(kind, 0))。
## 拷贝防外部改 reference 触发 procedure 内部状态漂移。
func get_team_resources(team_id: int) -> Dictionary:
	var src: Dictionary = _team_resources.get(team_id, {}) as Dictionary
	var copy: Dictionary[String, int] = {}
	for key in src:
		copy[str(key)] = int(src[key])
	return copy


## 扣阵营资源 (PlaceBuildingCommand 成功后调; 调方应保证每 key cost ≤ 当前 remaining)。
##
## M2.1 Phase A — cost 为 Dictionary[String, int]; 缺 key / value=0 跳过, 不扣减该资源。
## key 不在 _team_resources[team_id] 内 → 视为当前 0, 直接负数 (上层 placement.validate 已保证
## 充足, 不应到此; 防御式存负数让后续 audit 容易看到 bug)。
func spend_team_resources(team_id: int, cost: Dictionary) -> void:
	var bucket: Dictionary = _team_resources.get(team_id, {}) as Dictionary
	for key in cost:
		var amount: int = int(cost[key])
		if amount == 0:
			continue
		var current: int = int(bucket.get(key, 0))
		bucket[str(key)] = current - amount
	_team_resources[team_id] = bucket


## 加阵营资源 (M2.1 Phase C — RtsReturnAndDropActivity worker 抵达 drop-off 时调)。
##
## delta 为 Dictionary[String, int]; value=0 跳过; key 不在 _team_resources[team_id] 内 →
## 视为当前 0 起加。对称 spend_team_resources。
func add_team_resources(team_id: int, delta: Dictionary) -> void:
	var bucket: Dictionary = _team_resources.get(team_id, {}) as Dictionary
	for key in delta:
		var amount: int = int(delta[key])
		if amount == 0:
			continue
		var current: int = int(bucket.get(key, 0))
		bucket[str(key)] = current + amount
	_team_resources[team_id] = bucket


## M2.2 — 给指定 team_id 注册 AI 对手 (E10 显式 attach 时机决策)。
##
## smoke / demo 在 procedure 创建后调用 (procedure.attach_computer_player(0/1));
## 不在 procedure._init 默认创建, 保留旧 smoke "右侧不发 command 就死站" 行为不变。
##
## 同 team_id 重复 attach 不去重 — 调方负责只调一次; 重复 attach 会让 think 一 tick 调多次。
func attach_computer_player(p_team_id: int) -> void:
	Log.assert_crash(
		p_team_id == 0 or p_team_id == 1,
		"RtsAutoBattleProcedure",
		"attach_computer_player: invalid team_id %d" % p_team_id,
	)
	_computer_players.append(RtsComputerPlayer.new(p_team_id))


## P2.6 录像入口: 全 player_commands history (含 success / fail entries)。
##
## smoke / replay 通过此接口读全部 player_commands 流式录像; Phase 2 P2.7 完整 BattleRecorder
## 会把此字段持续 append 到 RtsRecording.player_commands。
func get_player_commands_log() -> Array[Dictionary]:
	return _player_commands_log.duplicate()


## P3.2: 取 actor_id 对应的 RtsUnitController (P1.5 后的 runtime 持有者).
##
## 玩家命令 (RtsMoveUnitsCommand 等) 在 apply 时通过此 accessor 取 controller 调
## set_activity_chain — 不让 _unit_runtimes 私有 dict 暴露给 command 子类直接访问。
##
## actor_id 对应 actor 不是 RtsUnitActor (如建筑) → 返回 null;
## actor_id 没注册 runtime → 返回 null (smoke 自由场景中 actor 可能没 controller)。
func get_unit_runtime(actor_id: String) -> RtsUnitController:
	return _unit_runtimes.get(actor_id, null) as RtsUnitController


# ========== 内部 ==========

## P2.6: 装配 team_configs。opts 不传 / 不含 0/1 时, 用 unconfigured(team_id) 占位让旧 smoke 不破。
##
## 调用后:
##   - _team_configs[0/1] 永远存在
##   - _team_resources[0/1] 深拷自 cfg.starting_resources (默认 {})
##
## M2.1 Phase A — 深拷防 cfg.starting_resources 与 runtime 状态共享同一 dict reference;
## procedure 内 spend 改 bucket 后, 外部 cfg.starting_resources 不应被污染。
func _install_team_configs(opts_team_configs: Dictionary) -> void:
	for team_id in [0, 1]:
		var cfg: RtsTeamConfig = opts_team_configs.get(team_id, null) as RtsTeamConfig
		if cfg == null:
			cfg = RtsTeamConfig.unconfigured(team_id)
		_team_configs[team_id] = cfg
		var bucket: Dictionary[String, int] = {}
		for key in cfg.starting_resources:
			bucket[str(key)] = int(cfg.starting_resources[key])
		_team_resources[team_id] = bucket


## RtsBattleActor 基类不强制持 ability_set; 子类(RtsUnitActor) 通过 get_ability_set 暴露。
## 用 has_method 探测避免 stub actor 崩溃。
func _safe_get_ability_set(actor: RtsBattleActor) -> AbilitySet:
	if actor == null:
		return null
	if actor.has_method("get_ability_set"):
		return actor.call("get_ability_set") as AbilitySet
	return null


## M2.5 — 每 tick 末 sync 所有 alive unit 的 obstruction shape 到 ObstructionManager。
##
## 新单位 (obstruction_tag == 0) 调 add_unit_shape 注册; 已注册单位调 move_shape 更新位置。
## **Death unregister deferred** 到 M5: M2.5 阶段死单位 obstruction_tag 残留, 但 production code
## 不消费 manager._shapes, baseline 不漂; 战斗结束 procedure GC 时随 manager 释放。
##
## **Determinism**: alive_units 顺序由 RtsWorldGameplayInstance.get_alive_units() 决定 (跟 base
## get_actors 同序), 跨 run 一致 → tag 分配序也一致。
##
## **Perf**: 100 unit × 30 Hz = 3000 op/s, 主要开销在 _spatial_index.update (remove+insert);
## M3 时若 perf hot 可加 short-circuit (旧/新 AABB 桶集合相同时不动)。
func _sync_unit_obstruction_shapes(world: RtsWorldGameplayInstance, alive_units: Array) -> void:
	var manager: RtsObstructionManager = world.obstruction_manager
	for u in alive_units:
		var unit: RtsUnitActor = u as RtsUnitActor
		if unit.obstruction_tag == 0:
			unit.obstruction_tag = manager.add_unit_shape(
				unit.get_id(),
				unit.position_2d,
				unit.collision_radius,
				RtsObstructionFlags.BLOCK_MOVEMENT,
				str(unit.team_id),
			)
		else:
			manager.move_shape(unit.obstruction_tag, unit.position_2d)


## P1.4: 包装 basic attack action 调用。给共享 action 喂 ExecutionContext + AbilityRef。
## ability_ref.owner_actor_id 让 RtsTargetSelectors.CurrentUnitTarget 拿到 attacker。
##
## P2.8: 接受任意 RtsBattleActor (单位 / 建筑); 共享 action 内部按 attacker.get_atk() 等
## virtual accessor 取数值, 不再强制 RtsUnitActor.attribute_set 路径。
func _invoke_basic_attack(attacker: RtsBattleActor, world: RtsWorldGameplayInstance) -> void:
	var ability_ref := AbilityRef.create(
		"basic_attack_inst",
		"basic_attack",
		attacker.get_id(),
	)
	var ctx := ExecutionContext.create(
		[],  # 无事件链 (basic attack 不是 ability trigger 触发)
		world,
		GameWorld.event_collector,
		ability_ref,
	)
	_basic_attack_action.execute(ctx)
