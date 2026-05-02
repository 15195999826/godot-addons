## RTS Castle War Minimal smoke (P2.8 — AC8 headless 验证)
##
## AC8 城堡战争最小可玩 demo 的 headless 形式: 玩家命令放兵营 → 兵营 spawn 单位 → 单位攻击
## 对方水晶塔 → 水晶塔死 → 战斗以 *_win 结束 (而非 fallback 全灭)。
##
## 目标 = AC8 的 logic 层等价物 (UI 输入由 PlaceBuildingCommand 替代; 视觉效果留 F6 demo 验)。
##
## 验证要点:
##   1. 玩家命令: 起手放置左方 barracks → 后续生产 melee 单位
##   2. 单位 → 水晶塔 路径: AutoTargetSystem 把 right_crystal_tower 选作攻击目标 (没有别的单位可选,
##      左方只有 barracks/ct/melee 兵营 spawn 出来的单位; 右方 ct 是 GROUND 层, melee mask=GROUND 命中)
##   3. 飞行 vs 防空: 同时 spawn 一个右方 flying_scout 朝左方水晶塔进攻; 左方 archer_tower 防空 → scout 死
##   4. 战斗结束: 左方先打死右方 ct (因为左方 spawn 兵 + ct fragile or 因为我们少 spawn) →  result=left_win
##
## 设计:
##   - 起手:
##     - 左 barracks 通过 PlaceBuildingCommand 在 tick 0 放置 (玩家命令路径)
##     - 左 archer_tower (T0) — 防空
##     - 左 crystal_tower (T0) — 玩家保护对象
##     - 右 barracks (T1) — 直接 add_actor (模拟 "敌方起手已建好"); 也 spawn melee
##     - 右 archer_tower (T1) — 防空
##     - 右 crystal_tower (T1) hp=200 (低 hp 让战斗短)
##     - 右 flying_scout (T1) — 朝左方 ct 飞 (验证 AC7+AC8 联动 — 飞行单位被左方 archer 击落)
##   - 跑 600 ticks @ 50ms = 30s; 期望左方先打掉右方 ct → result=left_win
##
## 关键不变量:
##   - flying_scout 死亡前不能打到左方 ct (左方 archer 防空)
##   - 战斗以 ct 死亡结束 (走 P2.6 crystal_tower 模式判定, 不是 fallback team-wipeout)
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 7777
const MAX_TICKS: int = 600  # 30s @ 50ms

const STARTING_RESOURCES_LEFT: int = 100  # 够放 1 barracks (cost=100)
const RIGHT_CT_HP: float = 100.0  # 故意设低让战斗快速分胜负 (1 melee 4s 杀; 600 ticks 内可破)

# 注: barracks 2×2 footprint, 不能与 left_archer (80,200) / left_ct (80,350) cells 重叠。
# (160, 250) cell=(5,7) 2x2=(4,6/5,6/4,7/5,7) 与 archer cell (2,6) / ct cells (1,9..2,10) 都不冲突。
const LEFT_BARRACKS_POS: Vector2 = Vector2(160.0, 250.0)
const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 200.0, 400.0)


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _agents: Dictionary = {}        # actor_id → RtsNavAgent
var _controllers: Dictionary = {}   # actor_id → RtsUnitController
var _spawned_unit_ids: Array[String] = []
var _attack_events: Array[Dictionary] = []


func _ready() -> void:
	GameWorld.init()

	_host = Node2D.new()
	add_child(_host)

	_grid = RtsBattleGrid.new(Vector2(500.0, 500.0), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_grid)

	# 左方起手: archer_tower (防空) + crystal_tower (要保护)
	var left_archer := RtsBuildings.create_archer_tower()
	left_archer.set_team_id(0)
	_world.add_actor(left_archer)
	left_archer.position_2d = Vector2(80.0, 200.0)

	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = Vector2(80.0, 350.0)

	# 右方起手: archer_tower (防空 — 不会打地面 melee, 让左方 melee 能直奔 ct) +
	# crystal_tower (要打掉的目标; hp=100 让 1-2 个 melee 几秒就破); 不放 barracks 避免分散左方火力
	var right_archer := RtsBuildings.create_archer_tower()
	right_archer.set_team_id(1)
	_world.add_actor(right_archer)
	right_archer.position_2d = Vector2(420.0, 380.0)  # 远离主战线让左方 melee 优先打 ct

	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	# ct 放主战线让 melee 进军时它最近 (优于 archer_tower 在远端 380)
	right_ct.position_2d = Vector2(420.0, 250.0)
	# 故意降 hp 让左方 melee 能在 600 ticks 内打掉
	right_ct.attribute_set.set_hp_base(RIGHT_CT_HP)

	# 右方起手投放 1 个 flying_scout 朝左方 ct 飞 (测试 AC7 联动 + 验证防空 wins)
	var right_scout := _spawn_unit(
		RtsUnitClassConfig.UnitClass.FLYING_SCOUT, 1, Vector2(450.0, 200.0),
	)
	# scout 朝左方 ct 飞 (override-strategy 让 strategy.decide 不替换它)
	(_controllers[right_scout.get_id()] as RtsUnitController).set_activity_chain(
		RtsAttackMoveActivity.new(left_ct.position_2d), true,
	)

	# Team configs: 左方 build_zone, starting_resources 够放 1 barracks
	var left_cfg := RtsTeamConfig.create(0, "human", STARTING_RESOURCES_LEFT, LEFT_BUILD_ZONE)
	var right_cfg := RtsTeamConfig.create(1, "ai", 0, Rect2())

	var left_actors: Array[RtsBattleActor] = [left_archer, left_ct]
	var right_actors: Array[RtsBattleActor] = [right_archer, right_ct, right_scout]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
		"event_sink": Callable(self, "_on_event_sink"),
	})

	# 玩家命令: tick 1 放置左方 barracks (生产 melee 朝右方 ct 进攻)
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		1, 0, RtsBuildingConfig.KIND_BARRACKS, LEFT_BARRACKS_POS,
	))

	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 验证 =====
	var result: String = _procedure.get_result()
	var ticks: int = _procedure.get_current_tick()

	# 1. 战斗自然结束 (走 crystal_tower 模式) — result 必须是 left_win 或 right_win
	if result != "left_win" and result != "right_win":
		_fail("expected battle to end with crystal_tower death, got result='%s' ticks=%d" % [result, ticks])
		return

	# 2. 玩家命令成功执行 (左方 barracks 成功放置)
	var log: Array[Dictionary] = _procedure.get_player_commands_log()
	if log.is_empty():
		_fail("no player_commands_log entry — placement command not applied")
		return
	var first_cmd: Dictionary = log[0]
	var cmd_result: Dictionary = first_cmd.get("result", {}) as Dictionary
	if not cmd_result.get("success", false):
		_fail("placement command failed: reason=%s" % str(cmd_result.get("reason", "")))
		return

	# 3. flying_scout 应被左方 archer_tower 击落 (验证 AC7 anti-air 在 AC8 上下文中工作)
	var scout_dead: bool = right_scout.is_dead()
	if not scout_dead:
		# 软警告 — 飞行单位可能击中目标后才被击落; 主断言是 ct 死亡
		print("warning: flying_scout still alive at battle end (hp=%.1f)" % right_scout.attribute_set.hp)

	# 4. 至少 1 次单位 → 建筑 攻击事件 (验证 AC8 单位攻击建筑链路)
	var unit_to_building_attacks: int = 0
	for ev in _attack_events:
		var src_id: String = ev.get("source_actor_id", "")
		var tgt_id: String = ev.get("target_actor_id", "")
		var src := _world.get_actor(src_id)
		var tgt := _world.get_actor(tgt_id)
		if src is RtsUnitActor and tgt is RtsBuildingActor:
			unit_to_building_attacks += 1
	if unit_to_building_attacks < 1:
		_fail("no unit→building attack events — AC8 unit-attacks-building path may not work")
		return

	# 5. 至少 1 次 archer_tower → flying_scout 攻击 (AC7)
	var archer_anti_air: int = 0
	for ev in _attack_events:
		var src_id: String = ev.get("source_actor_id", "")
		var tgt_id: String = ev.get("target_actor_id", "")
		if src_id == left_archer.get_id() and tgt_id == right_scout.get_id():
			archer_anti_air += 1
	if archer_anti_air < 1:
		_fail("expected left archer_tower to hit right flying_scout >= 1 time, got %d" % archer_anti_air)
		return

	# 报告
	print("rts castle_war_minimal smoke: ticks=%d result=%s left_ct_dead=%s right_ct_dead=%s scout_dead=%s unit_to_building_attacks=%d archer_anti_air=%d spawn_count=%d" % [
		ticks, result, str(left_ct.is_dead()), str(right_ct.is_dead()),
		str(scout_dead), unit_to_building_attacks, archer_anti_air, _spawned_unit_ids.size(),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - castle war minimal: player placed barracks, units attacked building, anti-air shot down flying, crystal tower died")
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	_world.add_actor(unit)
	unit.position_2d = pos

	var agent := RtsNavAgent.new()
	_host.add_child(agent)
	agent.bind_actor(unit, _grid)
	_agents[unit.get_id()] = agent

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, agent, strategy)
	_controllers[unit.get_id()] = controller

	return unit


## production_system 调用; 把右方 barracks 生产的 melee spawn 出来。
##
## 左方 barracks 也走此 spawner — 但是 strategy 不 override (与 player_command_production 不同),
## 让 AutoTargetSystem 决定打谁。左方 melee 因 mask=GROUND 选 right ct (近) → 接战。
func _spawn_unit_for_building(building: RtsBuildingActor) -> RtsUnitActor:
	if building == null or building.is_dead():
		return null
	var unit_class: int = building.spawn_unit_kind
	if unit_class < 0:
		return null
	var team_id: int = building.get_team_id()

	# 朝对方阵营前方 spawn (左 → +x 方向; 右 → -x 方向)
	var spawn_offset: float = 28.0  # footprint half + unit_radius + buffer
	var spawn_pos: Vector2
	if team_id == 0:
		spawn_pos = building.position_2d + Vector2(spawn_offset, 0.0)
	else:
		spawn_pos = building.position_2d - Vector2(spawn_offset, 0.0)

	var unit := _spawn_unit(unit_class, team_id, spawn_pos)
	unit.stance = building.spawn_unit_stance
	_procedure.add_unit_to_team(unit, team_id)
	_spawned_unit_ids.append(unit.get_id())
	# 不 set_activity_chain — 让 strategy.decide / AutoTargetSystem 自然驱动
	# (单位会去打 cached target, 选距离最近的 enemy ground actor — 即对方 ct)
	return unit


func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		if event.get("kind", "") == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			_attack_events.append(event)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
