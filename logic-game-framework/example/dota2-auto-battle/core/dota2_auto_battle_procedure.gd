## Dota2AutoBattleProcedure - 单线程固定 tick 自动战斗过程
##
## tick-model.md / controller-intent-model.md 固定相位（顺序是合同，可微调实现不可换边界）：
##   1 tick AbilitySet cooldown/duration
##   2 cleanup 死 actor + 失效不可能的 current intent
##   3 update targeting/spatial（M1 on-demand，无独立索引）
##   4 controller decision：create/keep/interrupt current intent（不每 tick 决策）
##   5 movement + ability 系统推进 current intent（adapter 走 sim-nav；基础攻击走 Ability）
##   6 controller result：记录 RUNNING/COMPLETED/FAILED
##   7 death cleanup + 出帧（Dota2LogicFrame 快照 + events）
##
## advance_tick(dt_ms) 恰好推进一个 logic tick 并返回 Dota2LogicFrame（frontend logic
## clock block / headless smoke 直接驱动；**不**走 WorldGI.tick 的 blocking 循环，也
## **不**覆写基类 tick_once —— 基类签名 `tick_once() -> void` 不兼容带参带返回值的
## 固定步进入口，故用独立方法名）。无 command/order 层。DOTA2 策略只在本 example，
## LGF/sim-nav core 零改动。tick-model.md 设计文档里的 `tick_once(LOGIC_DT_MS)` 即此。
class_name Dota2AutoBattleProcedure
extends BattleProcedure


## 安全上限：1800 tick @ 33.33ms ≈ 60s；战斗未在此分胜负判 timeout（smoke 记 FAIL）。
const MAX_TICKS := 1800
## 30Hz 固定 tick（tick-model.md LOGIC_DT_MS）。
const DOTA2_TICK_INTERVAL_MS := 1000.0 / 30.0


var movement_adapter: Dota2MovementAdapter = null

var left_team: Array[Dota2BattleActor] = []
var right_team: Array[Dota2BattleActor] = []

var _world_instance: Dota2WorldGameplayInstance = null
var _controllers: Dictionary = {}
var _result: String = ""
var _global_spawn_counter: int = 0
var _waves_spawned: Dictionary = { Dota2LaneConfig.TEAM_LEFT: 0, Dota2LaneConfig.TEAM_RIGHT: 0 }
## 本 tick step 5 算出的每单位 IntentStepResult（step 6 controller 回灌用）。
var _pending_step_results: Dictionary = {}


func _init(world: Dota2WorldGameplayInstance, opts: Dictionary = {}) -> void:
	super._init(world, [] as Array[Actor])
	_world_instance = world
	_tick_interval = float(opts.get("tick_interval_ms", DOTA2_TICK_INTERVAL_MS))
	movement_adapter = Dota2MovementAdapter.new()


# ========== 生命周期 ==========

## 战斗起手：注册基础攻击 timeline，左右各刷一波 lane creep（spawner 不发 intent）。
func start() -> void:
	super.start()
	Dota2BasicAttackAbility.register_timelines()
	_spawn_wave(Dota2LaneConfig.TEAM_LEFT)
	_spawn_wave(Dota2LaneConfig.TEAM_RIGHT)


func _spawn_wave(team_id: int) -> void:
	if int(_waves_spawned[team_id]) >= Dota2LaneConfig.MAX_WAVES:
		return
	Dota2WaveSpawner.spawn_wave(_world_instance, self, team_id, _global_spawn_counter)
	_global_spawn_counter += Dota2LaneConfig.get_wave_composition().size()
	_waves_spawned[team_id] = int(_waves_spawned[team_id]) + 1


## 推进恰好一个固定 logic tick，返回该 tick 的只读快照帧。
## dt_ms < 0 退化为 _tick_interval（兼容 WorldGI.tick 的无参调用，但正常路径
## 由 frontend logic clock / smoke 显式传 LOGIC_DT_MS）。
func advance_tick(dt_ms: float = -1.0) -> Dota2LogicFrame:
	if _finished:
		return _build_logic_frame([])
	var step_ms := dt_ms if dt_ms > 0.0 else _tick_interval
	var dt_seconds := step_ms / 1000.0
	_current_tick += 1
	var logic_time_ms := get_logic_time()

	# 1. AbilitySet cooldown / duration tick（cooldown tag 自动过期在此清）。
	for unit in _world_instance.get_alive_units():
		if unit.ability_set != null:
			unit.ability_set.tick(step_ms, logic_time_ms)

	# 2. cleanup 死 actor + 失效不可能的 current intent：M1 无独立动作 —— 上 tick 致死
	#    的 actor 已在该 tick step 7 移除；ATTACK_TARGET 的 target 失效由 step 5 的
	#    _eval_step_result 自然映射成 COMPLETED/FAILED，intent 生命周期在 step 5/6 闭环。

	# 3. update targeting/spatial：M1 aggro 走 Dota2TargetingSystem on-demand，无独立索引。

	# 4. controller decision step（仅在 _needs_decision 时决策）。
	for unit in _world_instance.get_alive_units():
		var ctrl: Dota2UnitController = _controllers.get(unit.get_id(), null)
		if ctrl == null:
			continue
		for evt in ctrl.decide_if_needed(_world_instance, _current_tick):
			GameWorld.event_collector.push(evt)

	# 5. movement + ability 推进 current intent。
	_advance_intents(dt_seconds, step_ms, logic_time_ms)

	# 6. controller result step：回灌 IntentStepResult。
	for unit in _world_instance.get_alive_units():
		var ctrl2: Dota2UnitController = _controllers.get(unit.get_id(), null)
		if ctrl2 == null:
			continue
		var result: Dota2IntentStepResult = _pending_step_results.get(unit.get_id(), null)
		if result == null:
			continue
		for evt in ctrl2.record_step_result(result, _current_tick):
			GameWorld.event_collector.push(evt)
	_pending_step_results.clear()

	# 7. death cleanup（本 tick 致死）+ 出帧。
	_remove_dead_actors()
	var events := GameWorld.event_collector.flush()
	if _recorder != null:
		_recorder.record_frame(_current_tick, events)
	var frame := _build_logic_frame(events)

	# 胜负判定。
	if _current_tick >= MAX_TICKS:
		_result = "timeout"
		mark_finished()
	else:
		_check_battle_end()
	return frame


func finish(result: String = "") -> Dictionary:
	var effective := result if result != "" else _result
	if effective == "":
		effective = "battle_complete"
	return super.finish(effective)


# ========== step 5：推进 current intent ==========

func _advance_intents(dt_seconds: float, step_ms: float, logic_time_ms: float) -> void:
	var alive := _world_instance.get_alive_units()

	# 5a. 据 current intent 给 adapter 下移动原语（不移动，仅排 order）。
	for unit in alive:
		var ctrl: Dota2UnitController = _controllers.get(unit.get_id(), null)
		if ctrl == null or ctrl.current_intent == null:
			continue
		var intent := ctrl.current_intent
		unit.debug_current_target_id = intent.get_target_id()  # 仅 debug 镜像
		match intent.kind:
			Dota2Intent.KIND_LANE_MARCH:
				movement_adapter.ensure_march(unit, intent.get_lane_goal())
			Dota2Intent.KIND_ATTACK_TARGET:
				var tgt: Dota2BattleActor = _world_instance.get_actor(intent.get_target_id())
				if tgt != null and not tgt.is_dead():
					var stop_dist: float = unit.attribute_set.attack_range
					movement_adapter.ensure_chase(unit, tgt.position_2d, stop_dist)

	# 5b. 跑 sim-nav 移动管线（四相位 + 写回 position_2d）。
	movement_adapter.advance(dt_seconds, alive)

	# 5c. 推进已激活的基础攻击 Timeline 执行（到 attack point 触发伤害 Action）。
	for unit in alive:
		if unit.ability_set != null and _has_active_execution(unit):
			unit.ability_set.tick_executions(step_ms, _world_instance)

	# 5d. ATTACK_TARGET：在攻击距离内且基础攻击合法 → 发 ABILITY_ACTIVATE_EVENT
	#     （cooldown/legality 由 Ability 的 condition+cost 把关，非 controller ad-hoc）。
	for unit in alive:
		var ctrl3: Dota2UnitController = _controllers.get(unit.get_id(), null)
		if ctrl3 == null or ctrl3.current_intent == null:
			continue
		if ctrl3.current_intent.kind != Dota2Intent.KIND_ATTACK_TARGET:
			continue
		var target_id := ctrl3.current_intent.get_target_id()
		if not Dota2TargetingSystem.is_target_valid(_world_instance, unit, target_id):
			continue
		if not Dota2TargetingSystem.is_in_attack_range(_world_instance, unit, target_id):
			continue
		if _has_active_execution(unit):
			continue
		_request_basic_attack(unit, target_id, logic_time_ms)

	# 5e. 计算每单位 IntentStepResult（事实，step 6 controller 据此推进生命周期）。
	for unit in alive:
		var ctrl4: Dota2UnitController = _controllers.get(unit.get_id(), null)
		if ctrl4 == null or ctrl4.current_intent == null:
			continue
		_pending_step_results[unit.get_id()] = _eval_step_result(unit, ctrl4.current_intent)


func _eval_step_result(unit: Dota2UnitActor, intent: Dota2Intent) -> Dota2IntentStepResult:
	match intent.kind:
		Dota2Intent.KIND_LANE_MARCH:
			var goal := intent.get_lane_goal()
			if movement_adapter.is_arrived(unit.get_id(), goal):
				return Dota2IntentStepResult.completed("reached_lane_goal")
			if movement_adapter.is_failed(unit.get_id()):
				var ms := movement_adapter.get_movement_state(unit.get_id())
				return Dota2IntentStepResult.failed("movement_failed:" + str(ms.get("block_reason", "")))
			return Dota2IntentStepResult.running()
		Dota2Intent.KIND_ATTACK_TARGET:
			var target_id := intent.get_target_id()
			var target: Dota2BattleActor = _world_instance.get_actor(target_id)
			if target == null or target.is_dead():
				return Dota2IntentStepResult.completed("target_dead")
			if not Dota2TargetingSystem.is_target_valid(_world_instance, unit, target_id):
				return Dota2IntentStepResult.failed("target_invalid")
			return Dota2IntentStepResult.running()
	return Dota2IntentStepResult.running()


## 发起一次基础攻击：ABILITY_ACTIVATE_EVENT 携带 controller 的 intent 目标，
## 喂 ability_set.receive_event → Ability condition(NoTag cd)+cost 把关合法性 →
## Timeline → attack point → Dota2DamageAction。与 hex procedure 同构。
func _request_basic_attack(unit: Dota2UnitActor, target_id: String, logic_time_ms: float) -> void:
	var ability := unit.get_basic_attack_ability()
	if ability == null:
		return
	var event := {
		"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
		"abilityInstanceId": ability.id,
		"sourceId": unit.get_id(),
		"target_actor_id": target_id,
		"logicTime": logic_time_ms,
	}
	unit.ability_set.receive_event(event, _world_instance)


func _has_active_execution(unit: Dota2UnitActor) -> bool:
	for ability in unit.ability_set.get_abilities():
		if ability.get_executing_instances().size() > 0:
			return true
	return false


# ========== step 7：death cleanup ==========

## 移除本 tick 致死的 actor：emit unit_removed → world.remove_actor → 注销移动体 +
## controller。team 列表保留引用（is_dead 过滤），用于胜负判定计数。
func _remove_dead_actors() -> void:
	var dead_ids: Array[String] = []
	for actor in _world_instance.get_actors():
		var ba: Dota2BattleActor = actor as Dota2BattleActor
		if ba != null and ba.is_dead():
			dead_ids.append(ba.get_id())
	for actor_id in dead_ids:
		GameWorld.event_collector.push(Dota2BattleEvents.make_unit_removed(actor_id))
		movement_adapter.unregister_unit(actor_id)
		_controllers.erase(actor_id)
		_world_instance.remove_actor(actor_id)


# ========== 出帧（Dota2LogicFrame 快照）==========

func _build_logic_frame(events: Array) -> Dota2LogicFrame:
	var snaps: Dictionary = {}
	for actor in _world_instance.get_actors():
		var unit: Dota2UnitActor = actor as Dota2UnitActor
		if unit == null:
			continue
		snaps[unit.get_id()] = _build_actor_snapshot(unit)
	return Dota2LogicFrame.new(_current_tick, get_logic_time(), snaps, events)


func _build_actor_snapshot(unit: Dota2UnitActor) -> Dictionary:
	var ctrl: Dota2UnitController = _controllers.get(unit.get_id(), null)
	var ms := movement_adapter.get_movement_state(unit.get_id())
	# TagContainer 无"剩余 ms"公共 API；snapshot 用布尔表征 cooldown（debug 面板足够）。
	var on_cd := false
	if unit.ability_set != null:
		on_cd = unit.ability_set.has_tag(Dota2AttackCooldown.COOLDOWN_TAG)
	return {
		"actor_id": unit.get_id(),
		"unit_type_id": unit.get_unit_type_id(),
		"team_id": unit.get_team_id(),
		"x": unit.position_2d.x,
		"y": unit.position_2d.y,
		"facing": unit.velocity.angle() if unit.velocity.length_squared() > 0.01 else 0.0,
		"hp": unit.attribute_set.hp,
		"max_hp": unit.attribute_set.max_hp,
		"alive": not unit.is_dead(),
		"intent_kind": ctrl.get_intent_kind() if ctrl != null else "",
		"intent_status": ctrl.current_intent_status if ctrl != null else Dota2IntentStatus.NONE,
		"intent_target_id": ctrl.get_intent_target_id() if ctrl != null else "",
		"next_decision_tick": ctrl.next_decision_tick if ctrl != null else 0,
		"movement_state": ms.get("state", "none"),
		"movement_goal_x": ms.get("goal_x", 0.0),
		"movement_goal_y": ms.get("goal_y", 0.0),
		"movement_block_reason": ms.get("block_reason", ""),
		"attack_executing": _has_active_execution(unit),
		"attack_on_cooldown": on_cd,
		"attack_target_id": unit.debug_current_target_id,
	}


# ========== spawner / 编排 API ==========

func register_controller(actor_id: String, controller: Dota2UnitController) -> void:
	_controllers[actor_id] = controller


func get_controller(actor_id: String) -> Dota2UnitController:
	return _controllers.get(actor_id, null)


func add_unit_to_team(unit: Dota2BattleActor, team_id: int) -> void:
	if team_id == Dota2LaneConfig.TEAM_LEFT:
		left_team.append(unit)
	elif team_id == Dota2LaneConfig.TEAM_RIGHT:
		right_team.append(unit)
	else:
		Log.assert_crash(false, "Dota2AutoBattleProcedure", "invalid team_id %d" % team_id)


func get_tick_index() -> int:
	return _current_tick


func get_result() -> String:
	return _result


# ========== 胜负判定 ==========

## 某队全灭（且已至少刷过一波）→ 对方胜；双灭 = draw。
func _check_battle_end() -> bool:
	var left_alive := _team_alive_count(left_team)
	var right_alive := _team_alive_count(right_team)
	var left_spawned := int(_waves_spawned[Dota2LaneConfig.TEAM_LEFT]) > 0
	var right_spawned := int(_waves_spawned[Dota2LaneConfig.TEAM_RIGHT]) > 0
	if not (left_spawned and right_spawned):
		return false
	if left_alive == 0 and right_alive == 0:
		_result = "draw"
		mark_finished()
		return true
	if left_alive == 0:
		_result = "right_win"
		mark_finished()
		return true
	if right_alive == 0:
		_result = "left_win"
		mark_finished()
		return true
	return false


func _team_alive_count(team: Array[Dota2BattleActor]) -> int:
	var n := 0
	for actor in team:
		if not actor.is_dead():
			n += 1
	return n
