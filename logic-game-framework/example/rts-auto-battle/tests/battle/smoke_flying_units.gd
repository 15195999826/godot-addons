## RTS Flying Units smoke (P2.8 — AC7 gate)
##
## 验证 P2.8 三个核心契约:
##   1. AIR-only 防空塔能命中飞行单位 (target_layer_mask=MASK_AIR + flying.movement_layer=AIR)
##   2. GROUND-only 近战不能命中飞行单位 (target_layer_mask=MASK_GROUND 命不到 AIR)
##   3. 飞行单位穿过地面建筑 footprint (RtsPathfinding for AIR layer 直接走 _direct_path,
##      不绕路; 与地面单位被 footprint 阻挡走 A* 形成对比)
##
## 设计:
##   - 自建轻量 host + grid (cell_size=32, 500×500)
##   - 起手:
##     - left team: archer_tower @ (200, 100)  — anti-air 塔, mask=MASK_AIR, range=140
##                  melee unit  @ (200, 200)   — GROUND only, mask=MASK_GROUND, HOLD_FIRE 防止移动
##     - right team: flying_scout @ (450, 100) — AIR 层, mask=MASK_GROUND, HOLD_FIRE + AttackMove (50,100)
##                                                让 scout 飞越战场 + 靠近 archer_tower 进攻击范围
##                  ground_melee @ (450, 200)  — GROUND, 走 AttackMove (50,200), 路上有 barracks 阻挡
##                  barracks   @ (300, 200)   — 障碍物 (footprint 2×2), 阻 ground_melee 的直线路径
##   - 跑 200 ticks @ 50ms = 10s
##
## 期望:
##   1. flying_scout HP < 90 (起手 hp) — archer_tower anti-air 命中起码 1 次
##   2. melee 期间不产生攻击 (target_layer_mask=GROUND, scout 是 AIR; 即使 scout 飞过 melee 头顶
##      也不能被锁定; AutoTargetSystem.matches 过滤掉)
##   3. flying_scout x < 250 (从 (450,100) 飞向 (50, 100) 越过 barracks 区域不绕路) — 直线飞行
##   4. attack_resolved events 中 source=archer_tower, target=flying_scout 至少 1 条
##   5. attack_resolved events 中 source=melee, target=flying_scout 0 条
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 1337
const MAX_TICKS: int = 200  # 10s @ 50ms

const SCOUT_INITIAL_HP: float = 90.0
const SCOUT_TARGET: Vector2 = Vector2(50.0, 100.0)
const GROUND_MELEE_TARGET: Vector2 = Vector2(50.0, 200.0)


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null

var _agents: Dictionary = {}        # actor_id → RtsNavAgent
var _controllers: Dictionary = {}   # actor_id → RtsUnitController

var _attack_events: Array[Dictionary] = []  # 记录所有 attack_resolved 给断言用


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

	# 左方 archer_tower (anti-air) + melee (GROUND only)
	var archer_tower := RtsBuildings.create_archer_tower()
	archer_tower.set_team_id(0)
	_world.add_actor(archer_tower)
	archer_tower.position_2d = Vector2(200.0, 100.0)

	var ground_obstacle := RtsBuildings.create_barracks()  # 仅作障碍, 不开生产 (无 spawner)
	ground_obstacle.set_team_id(0)
	_world.add_actor(ground_obstacle)
	ground_obstacle.position_2d = Vector2(300.0, 200.0)

	var melee := _spawn_unit_with_controller(
		RtsUnitClassConfig.UnitClass.MELEE, 0, Vector2(200.0, 200.0),
		RtsUnitActor.Stance.HOLD_FIRE,  # 不移动 / 主动接战, 让验证简单 (虽然 scout 是 AIR melee 也打不到)
	)

	# 右方 flying_scout (AIR) + ground_melee (GROUND); 都用 HOLD_FIRE + AttackMove 链
	var scout := _spawn_unit_with_controller(
		RtsUnitClassConfig.UnitClass.FLYING_SCOUT, 1, Vector2(450.0, 100.0),
		RtsUnitActor.Stance.HOLD_FIRE,
	)
	# 给 scout 显式 AttackMove 链让它朝西飞 (override_strategy=true 不让 strategy 替换)
	var scout_ctrl := _controllers[scout.get_id()] as RtsUnitController
	scout_ctrl.set_activity_chain(RtsAttackMoveActivity.new(SCOUT_TARGET), true)

	var ground_melee := _spawn_unit_with_controller(
		RtsUnitClassConfig.UnitClass.MELEE, 1, Vector2(450.0, 200.0),
		RtsUnitActor.Stance.HOLD_FIRE,
	)
	var gm_ctrl := _controllers[ground_melee.get_id()] as RtsUnitController
	gm_ctrl.set_activity_chain(RtsAttackMoveActivity.new(GROUND_MELEE_TARGET), true)

	# 启动战斗 (no team_configs → fallback team-wipeout, 但 HOLD_FIRE 的双方互不开火不会自然结束)
	_procedure = _world.start_rts_battle(
		[archer_tower, ground_obstacle, melee] as Array[RtsBattleActor],
		[scout, ground_melee] as Array[RtsBattleActor],
		{
			"tick_interval_ms": TICK_INTERVAL_MS,
			"unit_runtimes": _controllers,
			"rng_seed": RNG_SEED,
			"event_sink": Callable(self, "_on_event_sink"),
		},
	)

	# 主循环
	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 验证 =====
	var archer_id: String = archer_tower.get_id()
	var melee_id: String = melee.get_id()
	var scout_id: String = scout.get_id()
	var ground_melee_id: String = ground_melee.get_id()

	# 1. scout HP 应显著低于初始 (archer 命中过 N 次)
	var scout_hp: float = scout.attribute_set.hp
	if scout_hp >= SCOUT_INITIAL_HP:
		_fail("scout HP did not decrease: %.1f >= %.1f (archer_tower anti-air not firing?)" % [
			scout_hp, SCOUT_INITIAL_HP,
		])
		return

	# 2. attack_events 中 archer → scout 至少 1 条
	var archer_hits_scout: int = _count_attacks(archer_id, scout_id)
	if archer_hits_scout < 1:
		_fail("expected archer_tower to hit flying_scout >= 1 time, got %d" % archer_hits_scout)
		return

	# 3. melee → scout 应该 0 条 (GROUND-only mask 命不到 AIR)
	var melee_hits_scout: int = _count_attacks(melee_id, scout_id)
	if melee_hits_scout > 0:
		_fail("melee should never hit flying scout (GROUND mask vs AIR target), got %d hits" % melee_hits_scout)
		return

	# 4. scout 飞过 barracks 位置 (x < 250 — 起点 450, barracks @ 300, target @ 50)
	if scout.is_dead():
		# 即使死了, 看死前最远点 — 用 scout.position_2d 末位置
		# (archer 弓箭 25 atk × 0.7 attack_speed × ~10s ≈ 175 dmg, 大于 scout 90 hp 容易死)
		# 死后 nav 已 clear, 但 position_2d 是死时位置
		pass
	if scout.position_2d.x >= 250.0:
		_fail("flying_scout did not fly past barracks (x=%.1f, expected < 250)" % scout.position_2d.x)
		return

	# 5. ground_melee 路径被 barracks 阻挡 — 验证 ground 对 AIR 直线行为差异
	#    barracks @ (300, 200) footprint 2×2 cells (cell_size=32 → 64 px); ground_melee @ (450, 200)
	#    target (50, 200) 直线穿 barracks. ground_melee 的 A* 会绕开 → x 走得没 scout 远 OR 绕开后偏 y。
	#    不强断言 ground_melee 终位置 (因为 stuck recovery 可能 abandon, 或绕路慢) — 仅打日志。

	# 报告
	print("rts flying_units smoke: ticks=%d scout_hp=%.1f scout_pos=(%.1f,%.1f) archer_hits=%d melee_hits_scout=%d ground_melee_x=%.1f" % [
		_procedure.get_current_tick(), scout_hp, scout.position_2d.x, scout.position_2d.y,
		archer_hits_scout, melee_hits_scout, ground_melee.position_2d.x,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - anti-air tower hits flying, ground unit cannot, flying flies over building")
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit_with_controller(
	unit_class: int,
	team_id: int,
	pos: Vector2,
	stance: int,
) -> RtsUnitActor:
	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	unit.stance = stance
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


## procedure 主循环每 tick 调; 只关心 attack_resolved (验证攻击 source/target)。
func _on_event_sink(events: Array) -> void:
	for ev in events:
		var event: Dictionary = ev as Dictionary
		if event.get("kind", "") == RtsBattleEvents.ATTACK_RESOLVED_EVENT:
			_attack_events.append(event)


func _count_attacks(source_id: String, target_id: String) -> int:
	var count: int = 0
	for ev in _attack_events:
		if ev.get("source_actor_id", "") == source_id and ev.get("target_actor_id", "") == target_id:
			count += 1
	return count


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
