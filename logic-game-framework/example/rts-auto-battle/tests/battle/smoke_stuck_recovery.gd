## RTS stuck recovery smoke (P2.3 acceptance) — 3 单位被建筑地形包围, 至少 2 个 abandon
##
## 验证 RtsStuckDetector + RtsUnitController.abandon_command 在 procedure 主循环中接入后:
##   1. 3 个 melee 单位起点全部塞在中央障碍内 (cells 6..9, 6..9 = px 192..320 全 blocking),
##      每个单位的所有相邻 cell 也是 blocking → A* 起点没合法 neighbor → path 永远空
##   2. 远端 (450, 250) 放 1 个不动 dummy 敌人作为 attack 目标; basic_attack_strategy 会让 melee
##      不停 set_target 接敌 → 每次 A* 都返回空 path → 单位原地不动
##   3. 跑 200 ticks (远超 stuck_threshold (20) × repath_failures (3) = 60 ticks 即应 abandon):
##      a. **主断言**: 至少 2/3 单位 controller.is_command_abandoned() == true
##      b. **辅助断言**: abandon 后 unit.position_2d 几乎不变 (Idle activity 不写 nav)
##      c. **辅助断言**: stuck detector 的 stuck_ticks / repath_failures 在 abandon 后 reset
##
## 与 smoke_rts_auto_battle 的差异:
##   - 主 smoke 验证 stuck 不发生 (4v4 单位都能找到路径); 本 smoke 验证 stuck 发生 + 降级正确
##   - 主 smoke 不退化 = stuck detector 不误伤"正常移动"单位 (P2.3 不退化 AC9 验证)
##
## 与 smoke_steering 的差异:
##   - steering 验证"动态单位互避"; stuck recovery 验证"地形围困逃不出"
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_TICKS: int = 200

const STUCK_UNIT_COUNT: int = 3


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _controllers: Dictionary = {}   # actor.id → RtsUnitController
var _stuck_units: Array[RtsUnitActor] = []
var _start_positions: Dictionary = {}  # actor.id → Vector2 (起点)


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_battle_map.grid)

	# 3 个单位塞在中央障碍 (cells 6..9, 6..9 = px 192..320) — 起点 cell 自身 blocking,
	# 相邻 cell 也都 blocking → A* 永远找不到出路。
	# 用 cell_size=32, cell (7, 7) 中心 = px (224+16, 224+16) = (240, 240).
	# 3 个起点: (235, 235), (250, 250), (265, 265) — 各自 cell 都在障碍内
	var start_positions: Array[Vector2] = [
		Vector2(235.0, 235.0),
		Vector2(250.0, 250.0),
		Vector2(265.0, 265.0),
	]
	for pos in start_positions:
		_spawn_stuck_unit(pos)

	# Dummy 敌人 (team 1) 放在远端可达位置 — 成为 basic_attack_strategy 选中的 target,
	# 推动 stuck 单位不停 set_target 接敌
	var enemy_pos := Vector2(450.0, 250.0)
	var enemy := RtsUnitActor.new(Config.UnitClass.MELEE)
	enemy.set_team_id(1)
	_world.add_actor(enemy)
	enemy.position_2d = enemy_pos

	# enemy 也加 controller + agent? 不需要 — 我们用 unit_runtimes 仅含 stuck 单位; enemy 留默认
	# (无 controller, procedure 跳过其行为, 静止不动)

	var team_left: Array[RtsBattleActor] = []
	for u in _stuck_units:
		team_left.append(u)
	var team_right: Array[RtsBattleActor] = [enemy]

	_procedure = _world.start_rts_battle(team_left, team_right, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
	})

	# 跑 procedure
	for i in range(MAX_TICKS):
		_procedure.tick_once()
		if _procedure.should_end():
			break

	_procedure.finish()

	# ===== 主断言: 至少 2/3 单位 abandoned =====
	var abandoned_count: int = 0
	for unit in _stuck_units:
		var ctrl: RtsUnitController = _controllers[unit.get_id()]
		if ctrl.is_command_abandoned():
			abandoned_count += 1

	if abandoned_count < 2:
		_fail("only %d / %d units abandoned (expected ≥ 2)" % [abandoned_count, STUCK_UNIT_COUNT])
		return

	# ===== 辅助断言: abandon 单位的位置漂移 < 5 px (Idle activity 不写 nav) =====
	for unit in _stuck_units:
		var ctrl: RtsUnitController = _controllers[unit.get_id()]
		if not ctrl.is_command_abandoned():
			continue
		var start: Vector2 = _start_positions[unit.get_id()]
		var drift := unit.position_2d.distance_to(start)
		if drift > 5.0:
			_fail("unit %s abandoned but drifted %.2f px from %s to %s" % [
				unit.get_id(), drift, start, unit.position_2d,
			])
			return

	# ===== 辅助断言: abandon 后 controller.current_activity 是 Idle =====
	for unit in _stuck_units:
		var ctrl: RtsUnitController = _controllers[unit.get_id()]
		if not ctrl.is_command_abandoned():
			continue
		var label: String = ctrl.get_intent_action()
		if label != "idle":
			_fail("unit %s abandoned but get_intent_action='%s' (expected 'idle')" % [unit.get_id(), label])
			return

	# 辅助断言: 至少 1 个单位的 controller 不抢攻击 (wants_to_attack=false in Idle)
	var any_idle_no_attack: bool = false
	for unit in _stuck_units:
		var ctrl: RtsUnitController = _controllers[unit.get_id()]
		if ctrl.is_command_abandoned() and not ctrl.wants_to_attack():
			any_idle_no_attack = true
			break
	if not any_idle_no_attack:
		_fail("no abandoned unit has wants_to_attack=false (Idle should not want attack)")
		return

	print("stuck recovery smoke: abandoned=%d/%d units; positions stable; intents=idle" % [
		abandoned_count, STUCK_UNIT_COUNT,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - %d/3 surrounded units abandoned command" % abandoned_count)
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_stuck_unit(pos: Vector2) -> void:
	var unit := RtsUnitActor.new(Config.UnitClass.MELEE)
	unit.set_team_id(0)
	_world.add_actor(unit)
	unit.position_2d = pos
	_stuck_units.append(unit)
	_start_positions[unit.get_id()] = pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)
	# M7d: 测试"地形围困 → motion 自治 abort → controller abandon"路径,关 unreachable
	# fallback 让 motion 真累 _failed_movements 到 35(production 默认开 fallback 让 unit 走
	# 出 inflate 区,但本 smoke 测原 abort 行为)。
	motion_component.motion._allow_unreachable_fallback = false

	var strategy := RtsAIStrategyFactory.get_strategy(Config.UnitClass.MELEE)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	_controllers[unit.get_id()] = controller


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
