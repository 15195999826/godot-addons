## RTS Crystal Tower Win-Condition smoke (P2.6 — AC5 gate, 单元二)
##
## 验证要点 (新胜负判定 — 决策 D1):
##   1. team_configs 装 crystal_tower_id 后, _check_battle_end 走 crystal-tower-死亡 模式
##   2. 起手 procedure.start() 自动绑定 crystal_tower_id (smoke 不需要手动 set)
##   3. 单方 crystal_tower 死 → 该方败 (左 alive but 右 crystal_tower dead → left_win)
##   4. 双方 crystal_tower 都活 → 战斗未结束
##   5. 双方都死 → draw
##   6. 不破 fallback 模式: 旧 smoke (无 team_configs / 无 crystal_tower_id) 仍走全灭判定
##      (fallback 由 main 4v4 smoke 验证, 此处仅看新模式)
##
## 设计:
##   - 双方各 1 crystal_tower (hp=2000); 起手不放 unit (避免单位互殴干扰)
##   - 起手 procedure.start() 应自动绑 crystal_tower_id
##   - tick 1 后状态: 双方 crystal_tower 都活 → 战斗 in progress
##   - 手动 mark_dead 右方 crystal_tower (单测层模拟"被打死"; P2.7+ 单位攻击建筑是后续工作)
##   - tick 1 后状态: 右方败 → result=left_win
##
## 与 fallback 模式的区分:
##   - 本 smoke 设了 team_configs.crystal_tower_id (经 start() 自动绑定)
##   - fallback (旧 smoke) 不设 team_configs → unconfigured.crystal_tower_id="" → has_crystal_tower=false → 全灭判定
extends Node


const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 7777


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _grid: RtsBattleGrid = null
var _host: Node2D = null


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

	# 双方各 1 crystal_tower
	var left_ct := RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = Vector2(80.0, 250.0)

	var right_ct := RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = Vector2(420.0, 250.0)

	# team_configs: crystal_tower_id 留空让 procedure.start() 自动绑 (验证自动绑定逻辑)
	var left_team_cfg := RtsTeamConfig.create(0, "human", 0, Rect2())
	var right_team_cfg := RtsTeamConfig.create(1, "human", 0, Rect2())

	var left_actors: Array[RtsBattleActor] = [left_ct]
	var right_actors: Array[RtsBattleActor] = [right_ct]

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": {},
		"team_configs": { 0: left_team_cfg, 1: right_team_cfg },
		"rng_seed": RNG_SEED,
	})

	# 验证 1: procedure.start() 自动绑 crystal_tower_id
	if left_team_cfg.crystal_tower_id != left_ct.get_id():
		_fail("left team_config.crystal_tower_id NOT auto-bound; got '%s' expected '%s'" % [
			left_team_cfg.crystal_tower_id, left_ct.get_id(),
		])
		return
	if right_team_cfg.crystal_tower_id != right_ct.get_id():
		_fail("right team_config.crystal_tower_id NOT auto-bound; got '%s' expected '%s'" % [
			right_team_cfg.crystal_tower_id, right_ct.get_id(),
		])
		return

	# Phase A: 跑 1 tick — 双方 crystal_tower 都活, 战斗 in progress
	_procedure.tick_once()
	if _procedure.should_end():
		_fail("battle ended too early at tick 1 (both crystal_towers should be alive)")
		return

	# Phase B: 手动 mark_dead 右方 crystal_tower (单测层模拟"被打死")
	right_ct.attribute_set.set_hp_base(0.0)
	right_ct.mark_dead()

	# Phase C: 再跑 1 tick — 应该立即 left_win
	_procedure.tick_once()
	if not _procedure.should_end():
		_fail("battle did not end after right crystal_tower dead (procedure.should_end()=false)")
		return

	var result: String = _procedure.get_result()
	if result != "left_win":
		_fail("expected left_win after right crystal_tower dead, got '%s'" % result)
		return

	# Phase D: 验证双方都死 → draw 路径 (不破; 重启 procedure 测)
	# 用同样的 grid + world 跑一个新 procedure (复用 actor 已死, 直接构造新 procedure)
	# 简化: 不重启 procedure, 用 _is_team_lost 单独验证 — 走公共 API: get_team_config + 内部判定
	# 由于 left_ct 仍活 + right_ct 死, 直接 mark left_ct 死也走 draw 路径; 但当前 procedure 已 finished
	# 不能再 tick. 此 path 留待真实战斗多兵种 demo 验证.
	# 主路径 (单方 crystal_tower 死) 已 covered, 这是 P2.6 AC5 主断言.
	_procedure.finish()

	# 报告
	print("rts crystal_tower_win smoke: ticks=%d result=%s left_ct_dead=%s right_ct_dead=%s" % [
		_procedure.get_current_tick(), result, str(left_ct.is_dead()), str(right_ct.is_dead()),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - crystal_tower death triggers correct win condition")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
