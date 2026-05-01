## RTS frontend Director streaming smoke (P2.7)
##
## 目标: 验证 RtsBattleDirector 接入流式 events 后, frontend 全链路工作:
##   1. director.actor_render_state_updated 累计 emit (visualizer 收到位置 push, 不再 polling actor)
##   2. director.attack_resolved 累计 emit > 0 (战斗实际打了 attack 且 events 流到 director)
##   3. visualizer 数量 = 8 (RtsWorldView 自动创建 RtsUnitVisualizer)
##   4. 至少一个 visualizer 的 _curr_pos != _prev_pos (位置实际推进过, 不是死锁)
##   5. 不出现 SCRIPT ERROR / actor_render_state 链断裂
##
## 与 smoke_frontend_main 的区别:
##   - smoke_frontend_main: 验证 demo_rts_frontend.tscn 视觉链不崩 (8 visualizers + alive count)
##   - 本 smoke: 验证 director signal 数据流 (attack/render emit count + 位置确实变了)
##
## P2.7 acceptance AC6 主断言: frontend 0 处 actor.position_2d 直读 — 通过 visualizer 持
## actor_id (而非 actor 引用) + 通过 director push render state 来支撑.
extends Node


const RUN_SECONDS: float = 4.0
const TICK_INTERVAL_MS: float = 50.0  # 与 phase 1 smoke 保持兼容; director 内部仍走 procedure 的 tick_interval


var _world: RtsWorldGameplayInstance = null
var _battle_map: RtsBattleMap = null
var _procedure: RtsAutoBattleProcedure = null
var _director: RtsBattleDirector = null
var _world_view: RtsWorldView = null
var _agents: Dictionary = {}
var _controllers: Dictionary = {}

# 信号计数 (验证 director 数据流是否真的流动)
var _attack_emit_count: int = 0
var _death_emit_count: int = 0
var _render_emit_count: int = 0


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

	_director = RtsBattleDirector.new()
	add_child(_director)
	_director.attack_resolved.connect(_on_attack_resolved)
	_director.actor_died.connect(_on_actor_died)
	_director.actor_render_state_updated.connect(_on_render_state_updated)

	_world_view = RtsWorldView.new()
	_battle_map.add_child(_world_view)
	_world_view.bind(_world, _director)

	# 4v4 spawn (与 smoke_rts_auto_battle 同套路: 各队 2 melee + 2 ranged)
	const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")
	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []
	for i in range(roster.size()):
		left_actors.append(_spawn_unit(roster[i], 0, RtsBattleMap.sample_team_spawn(0, i, roster.size())))
		right_actors.append(_spawn_unit(roster[i], 1, RtsBattleMap.sample_team_spawn(1, i, roster.size())))

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"unit_runtimes": _controllers,
		"tick_interval_ms": TICK_INTERVAL_MS,
	})
	_director.attach(_world, _procedure)

	# 等待几帧让 director._process 推进 procedure
	for _i in range(5):
		await get_tree().physics_frame

	# Visualizer 数量
	var visualizers_count: int = 0
	var visualizers: Array = []
	for child in _battle_map.find_children("*", "Node2D", true, false):
		if child is RtsUnitVisualizer:
			visualizers_count += 1
			visualizers.append(child)
	if visualizers_count != 8:
		_fail("expected 8 RtsUnitVisualizer, got %d" % visualizers_count)
		return

	# 跑 RUN_SECONDS 让战斗推进
	await get_tree().create_timer(RUN_SECONDS).timeout

	# === 断言 ===

	# 1. director 至少 emit 过几次 actor_render_state_updated (8 actor × N tick)
	if _render_emit_count == 0:
		_fail("director did not emit any actor_render_state_updated (visualizer push 链断裂)")
		return

	# 2. attack_resolved 至少 1 次 (战斗 4s 应该已经接敌)
	if _attack_emit_count == 0:
		_fail("director did not emit any attack_resolved (events 链未到 director)")
		return

	# 3. 至少有一个 visualizer 当前位置与起始位置不同 (单位实际移动了)
	var moved_count: int = 0
	for v in visualizers:
		var vis := v as RtsUnitVisualizer
		# 起始 spawn x 在 50 / 450 (左右两边); 跑 4s 后大部分单位应该已经向中场移动
		# 我们只要至少 1 个单位 moved (curr != initial spawn) 即可证明位置流动
		var pos: Vector2 = vis.get_render_position()
		var starting_xs := [50.0, 450.0]
		var moved := true
		for sx in starting_xs:
			if abs(pos.x - sx) < 0.5:
				moved = false
				break
		if moved:
			moved_count += 1
	if moved_count == 0:
		_fail("no visualizer moved past spawn x (位置插值流不动)")
		return

	# 4. director 仍 running (战斗 4s 内未结束) 或已 ended (allowed)
	# 5. 不需要断言 attack_count 精确值; smoke_rts_auto_battle 已盯住数值

	print("director streaming smoke: visualizers=%d render_emits=%d attack_emits=%d death_emits=%d moved=%d ticks=%d" % [
		visualizers_count,
		_render_emit_count,
		_attack_emit_count,
		_death_emit_count,
		moved_count,
		_director.get_current_tick(),
	])
	print("SMOKE_TEST_RESULT: PASS - director streaming 链路工作 (events emit + visualizer push + 位置流动)")
	get_tree().quit(0)


func _spawn_unit(unit_class, team_id: int, pos: Vector2) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(actor, _battle_map.grid)
	_agents[actor.get_id()] = agent

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(actor, agent, strategy)
	_controllers[actor.get_id()] = controller

	return actor


# ========== Signal handlers ==========

func _on_attack_resolved(_event: Dictionary) -> void:
	_attack_emit_count += 1


func _on_actor_died(_actor_id: String) -> void:
	_death_emit_count += 1


func _on_render_state_updated(
	_actor_id: String,
	_prev_pos: Vector2,
	_curr_pos: Vector2,
	_hp: float,
	_max_hp: float,
	_is_dead: bool,
) -> void:
	_render_emit_count += 1


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
