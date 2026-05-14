## RTS stuck recovery smoke (current motion path)
##
## 验证当前 M7 motion contract 的集成层:
##   1. procedure 使用 world.pathfinder_facade 驱动 RtsUnitMotionManager
##   2. pathfinder 持续返回 empty path 时, motion._failed_movements 达阈值并 set just_failed
##   3. procedure._dispatch_motion_failed 把 abort 派发给 RtsUnitController
##   4. controller.abandon_command() 后单位进入 abandoned + idle,不再 wants_to_attack
##
## 旧版本 smoke 通过"单位塞进中央障碍"间接期望 stuck_detector abandon。M7 motion 之后,
## terrain/direct-path fallback 语义变了,低层失败计数已由 smoke_motion_failed_movements 覆盖。
## 这里保留更有价值的 procedure/controller 集成合同。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_TICKS: int = 80
const STUCK_UNIT_COUNT: int = 3


## 永远返空 path 的 facade,模拟持续不可达/无法规划。
class MockEmptyPathFacade extends RtsPathfinderFacade:
	func _init() -> void:
		# 故意不调 super._init(),跳过 grid 必填 assert。
		pass

	func compute_path_immediate(_start: Vector2, _goal: RtsPathGoal, _pass_mask: int) -> RtsWaypointPath:
		return RtsWaypointPath.new()

	func compute_path_direct(_start: Vector2, _goal: RtsPathGoal, _pass_mask: int) -> RtsWaypointPath:
		return RtsWaypointPath.new()

	func compute_short_path_immediate(_req: RtsShortPathRequest, _obstr_mgr: RtsObstructionManager) -> RtsWaypointPath:
		return RtsWaypointPath.new()


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _controllers: Dictionary = {}
var _stuck_units: Array[RtsUnitActor] = []
var _start_positions: Dictionary = {}


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

	var start_positions: Array[Vector2] = [
		Vector2(50.0, 220.0),
		Vector2(50.0, 250.0),
		Vector2(50.0, 280.0),
	]
	for pos in start_positions:
		_spawn_stuck_unit(pos)

	var enemy := RtsUnitActor.new(Config.UnitClass.MELEE)
	enemy.set_team_id(1)
	_world.add_actor(enemy)
	enemy.position_2d = Vector2(450.0, 250.0)

	var team_left: Array[RtsBattleActor] = []
	for unit in _stuck_units:
		team_left.append(unit)
	var team_right: Array[RtsBattleActor] = [enemy]

	_procedure = _world.start_rts_battle(team_left, team_right, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
	})
	_world.pathfinder_facade = MockEmptyPathFacade.new()

	for i in range(MAX_TICKS):
		_procedure.tick_once()
		if _all_stuck_units_abandoned():
			break

	_procedure.finish()
	if not _assert_abandoned_units():
		return

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - motion failure dispatch abandoned %d/%d units" % [
		STUCK_UNIT_COUNT,
		STUCK_UNIT_COUNT,
	])
	get_tree().quit(0)


func _spawn_stuck_unit(pos: Vector2) -> void:
	var unit := RtsUnitActor.new(Config.UnitClass.MELEE)
	unit.set_team_id(0)
	_world.add_actor(unit)
	unit.position_2d = pos
	_stuck_units.append(unit)
	_start_positions[unit.get_id()] = pos

	var motion_component := RtsMotionComponent.attach_default(unit, _world)
	motion_component.motion._allow_unreachable_fallback = false

	var strategy := RtsAIStrategyFactory.get_strategy(Config.UnitClass.MELEE)
	var controller := RtsUnitController.new(unit, motion_component, strategy)
	_controllers[unit.get_id()] = controller


func _all_stuck_units_abandoned() -> bool:
	for unit in _stuck_units:
		var ctrl: RtsUnitController = _controllers[unit.get_id()]
		if not ctrl.is_command_abandoned():
			return false
	return true


func _assert_abandoned_units() -> bool:
	var abandoned_count := 0
	for unit in _stuck_units:
		var ctrl: RtsUnitController = _controllers[unit.get_id()]
		if ctrl.is_command_abandoned():
			abandoned_count += 1
			var start: Vector2 = _start_positions[unit.get_id()]
			var drift: float = unit.position_2d.distance_to(start)
			if drift > 5.0:
				_fail("unit %s abandoned but drifted %.2f px" % [unit.get_id(), drift])
				return false
			if ctrl.get_intent_action() != "idle":
				_fail("unit %s abandoned but intent='%s'" % [unit.get_id(), ctrl.get_intent_action()])
				return false
			if ctrl.wants_to_attack():
				_fail("unit %s abandoned but still wants_to_attack" % unit.get_id())
				return false

	if abandoned_count != STUCK_UNIT_COUNT:
		_fail("only %d / %d units abandoned" % [abandoned_count, STUCK_UNIT_COUNT])
		return false
	return true


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
