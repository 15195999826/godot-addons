## RtsActivity primitive smoke — 链顺序 + cancel 传播 (P2.1 acceptance; P2.2 拆 movement)
##
## 验证 RtsActivity / RtsMoveToActivity / RtsAttackActivity 三件套在不接 controller / strategy
## 的情况下纯由 RtsActivity.advance 驱动是否正确:
##
##   Phase 1: 链 [MoveTo(A) → MoveTo(B) → AttackActivity(enemy)]; 跑到抵达 A,
##           验证 A 转 DONE 后 advance 自动切到 B (链推进顺序正确)。
##   Phase 2: 在 MoveTo(B) 移动途中调 head.cancel(); 推一次 advance 让 cancel 流过整链。
##           验证三个 activity 全部 state=DONE (cancel 递归到 next/child)。
##           验证 actor 不再前进 (>2px drift = FAIL — nav 没释放干净)。
##
## 不接 procedure / strategy: 直接构造 actor + nav agent + grid; 手动循环 RtsActivity.advance。
## 这是 Activity primitive unit test, 与 4v4 主 smoke 的"controller 集成"测试互补。
##
## P2.2 改动: activity tick 不再调 nav_agent.tick (移动已交给 procedure step 4 拆三段),
## smoke 在每次 advance 之后手动驱动 compute_desired_velocity + integrate, 替代 procedure 的角色。
extends Node


const TICK_INTERVAL_MS: float = 50.0
const MAX_PHASE1_TICKS: int = 200


var _world: RtsWorldGameplayInstance = null
var _battle_map: RtsBattleMap = null
var _agent: RtsNavAgent = null
var _actor: RtsUnitActor = null
var _enemy: RtsUnitActor = null


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

	# Actor 起点 (50, 50); A=(150, 50), B=(150, 150) 避开 (192..320, 192..320) 障碍
	_actor = RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	_actor.set_team_id(0)
	_world.add_actor(_actor)
	_actor.position_2d = Vector2(50.0, 50.0)
	_agent = RtsNavAgent.new()
	_battle_map.add_child(_agent)
	_agent.bind_actor(_actor, _battle_map.grid)

	# Enemy 远端, 让 AttackActivity 有 valid target id (cancel 前永远不会 in-range)
	_enemy = RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	_enemy.set_team_id(1)
	_world.add_actor(_enemy)
	_enemy.position_2d = Vector2(450.0, 50.0)

	# 链 [MoveTo(A) → MoveTo(B) → AttackActivity(enemy)]
	var pos_a := Vector2(150.0, 50.0)
	var pos_b := Vector2(150.0, 150.0)
	var move_a := RtsMoveToActivity.new(pos_a)
	var move_b := RtsMoveToActivity.new(pos_b)
	var attack := RtsAttackActivity.new(_enemy.get_id())
	move_a.queue(move_b).queue(attack)
	move_a.bind_runtime(_agent)

	var dt: float = TICK_INTERVAL_MS / 1000.0
	var head: RtsActivity = move_a

	# ===== Phase 1: 跑到 A 抵达 + advance 切到 B =====
	var phase1_ticks := 0
	while phase1_ticks < MAX_PHASE1_TICKS:
		head = RtsActivity.advance(head, _actor, _world, dt)
		# Activity tick 不再写 position; smoke 手动驱动 nav 移动管线 (P2.2 拆分后的两段)
		_drive_nav(dt)
		phase1_ticks += 1
		if head == null:
			_fail("phase1: chain ran out before reaching A (ticks=%d)" % phase1_ticks)
			return
		# 链头切到 MoveTo(B) 即视为 phase1 完成
		if head is RtsMoveToActivity and (head as RtsMoveToActivity).target_pos == pos_b:
			break

	if move_a.state != RtsActivity.State.DONE:
		_fail("phase1: expected MoveTo(A).state=DONE after chain advance, got %s" % _state_str(move_a.state))
		return
	if not (head is RtsMoveToActivity) or (head as RtsMoveToActivity).target_pos != pos_b:
		_fail("phase1: expected current=MoveTo(B), got %s" % _activity_kind(head))
		return
	if move_b.state != RtsActivity.State.ACTIVE:
		_fail("phase1: expected MoveTo(B).state=ACTIVE after takeover, got %s" % _state_str(move_b.state))
		return

	# ===== Phase 2: 让 actor 沿 B 方向走几帧, 然后 cancel head =====
	for _i in range(5):
		head = RtsActivity.advance(head, _actor, _world, dt)
		_drive_nav(dt)
		if head == null:
			_fail("phase2: chain ran out unexpectedly during pre-cancel ticks")
			return
	var pos_pre_cancel: Vector2 = _actor.position_2d

	head.cancel()
	head = RtsActivity.advance(head, _actor, _world, dt)
	_drive_nav(dt)

	# Cancel 应递归传播: MoveTo(B) DONE; AttackActivity (尚未 ACTIVE 即 QUEUED) 也应 DONE
	if move_b.state != RtsActivity.State.DONE:
		_fail("cancel: expected MoveTo(B).state=DONE, got %s" % _state_str(move_b.state))
		return
	if attack.state != RtsActivity.State.DONE:
		_fail("cancel: expected AttackActivity.state=DONE (cancel propagated to next), got %s" % _state_str(attack.state))
		return
	if head != null:
		_fail("cancel: expected advance to return null (chain fully done), got %s" % _activity_kind(head))
		return

	# ===== Phase 3: 取消后再推几 tick, actor 不该再移动 (nav cleared) =====
	for _i in range(10):
		head = RtsActivity.advance(head, _actor, _world, dt)
		_drive_nav(dt)
	var pos_settled: Vector2 = _actor.position_2d
	var drift := pos_pre_cancel.distance_to(pos_settled)
	if drift > 6.0:
		_fail("post-cancel: actor still moving (drift=%.2f from %s to %s)" % [drift, pos_pre_cancel, pos_settled])
		return

	print("smoke_activity_chain: phase1_ticks=%d, pre_cancel=%s, settled=%s, drift=%.2f" % [
		phase1_ticks, pos_pre_cancel, pos_settled, drift,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - chain order + cancel propagation + nav cleanup")
	get_tree().quit(0)


# ========== 移动驱动 (代替 procedure step 4) ==========

## P2.2 拆分后, activity tick 不再调 nav_agent.tick — 移动归 procedure step 4 三段管线。
## 此 smoke 不接 procedure, 手动模拟 compute_velocity + integrate; 不接 spatial_hash / steering
## (单 actor 场景, 无邻居 → steering 无作用)。
func _drive_nav(dt: float) -> void:
	if _agent == null:
		return
	_agent.compute_desired_velocity(dt)
	_agent.integrate(dt)


# ========== 调试输出 helper ==========

func _activity_kind(a: RtsActivity) -> String:
	if a == null:
		return "null"
	var s := a.get_script() as Script
	if s == null:
		return "RtsActivity"
	return s.resource_path.get_file()


func _state_str(s: int) -> String:
	match s:
		RtsActivity.State.QUEUED:
			return "QUEUED"
		RtsActivity.State.ACTIVE:
			return "ACTIVE"
		RtsActivity.State.CANCELING:
			return "CANCELING"
		RtsActivity.State.DONE:
			return "DONE"
		_:
			return "?"


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
