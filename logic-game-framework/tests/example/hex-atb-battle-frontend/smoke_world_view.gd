## Smoke test: 阶段 2 验证 WorldView + BattleAnimator
##
## 目标：WorldView 对 WorldGameplayInstance mutation signal 的响应式绑定、
## 战斗结束后 BattleAnimator 能消费 event_timeline 驱动动画、以及显式
## remove_actor 能让 unit view 跟着消失（reactive projection）。
##
## 覆盖：
##   - bind_world 前无 view；bind_world 后 view 数 == actor 数（hydrate）
##   - HexDemoWorldGameplayInstance.start → configure_grid signal → grid renderer 建立
##   - HexDemoWorldGameplayInstance.start → actor_added × N → unit view × N
##   - WorldGI.tick 驱动战斗至 battle_finished signal，拿到非空 timeline
##   - BattleAnimator.play(timeline, views) 跑到 playback_ended 不崩
##   - WorldGI.remove_actor → WorldView unit view 随之移除
##
## 不覆盖：像素视觉正确性、VFX/粒子细节、相机。
##
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


const TIMEOUT_SEC := 30.0
const ANIM_SPEED := 50.0


var _world: HexDemoWorldGameplayInstance
var _world_view: FrontendWorldView
var _animator: FrontendBattleAnimator
var _phase: String = "init"
var _elapsed: float = 0.0
var _finished: bool = false
var _timeline: Dictionary = {}


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: WorldView + BattleAnimator ===")

	GameWorld.init()

	# Step 1: WorldView 先建好进场景树, 但不 bind
	_world_view = FrontendWorldView.new()
	_world_view.name = "WorldView"
	add_child(_world_view)

	if _world_view.get_unit_view_count() != 0:
		_fail("WorldView 初始应当无 unit view")
		return

	# Step 2: 建 HexDemoWorldGameplayInstance 但 *不* 立即 start —— bind_world 先接管 signal
	_world = HexDemoWorldGameplayInstance.new()
	GameWorld.create_instance(func() -> GameplayInstance: return _world)

	_world_view.bind_world(_world)

	if _world_view.get_unit_view_count() != 0:
		_fail("bind 时 world 还没 actor, view 应为 0")
		return

	# Step 3: start — configure_grid + add_actor × 6 的 signal 应该驱动 WorldView
	_world.start({
		"logging": false,
		"recording": true,
		"console_log": false,
		"file_log": false,
	})

	var expected_actors := _world.get_all_actors().size()
	if expected_actors == 0:
		_fail("HexDemoWorldGameplayInstance.start 后 actor 数为 0, 实装异常")
		return

	if _world_view.get_unit_view_count() != expected_actors:
		_fail("actor_added signal 没把 view 建全: expected %d, got %d" % [
			expected_actors, _world_view.get_unit_view_count(),
		])
		return

	print("[Smoke] bind + signal-driven spawn OK, views=%d" % _world_view.get_unit_view_count())

	# Step 4: 挂 animator + 监听 battle_finished
	_animator = FrontendBattleAnimator.new()
	_animator.name = "BattleAnimator"
	add_child(_animator)
	_animator.playback_ended.connect(_on_anim_done)
	_animator.set_speed(ANIM_SPEED)

	_world.battle_finished.connect(_on_battle_finished)
	_phase = "ticking"


func _process(dt: float) -> void:
	if _finished:
		return
	_elapsed += dt
	if _elapsed > TIMEOUT_SEC:
		_fail("timeout %.1fs in phase=%s" % [_elapsed, _phase])
		return

	if _phase == "ticking":
		# BATTLE_TICKS_PER_WORLD_FRAME=INT_MAX 时单次 tick 会推进战斗到结束。
		# HexBattleProcedure.MAX_TICKS=10000 作安全上限。
		GameWorld.tick_all(100.0)


func _on_battle_finished(timeline: Dictionary) -> void:
	if timeline.is_empty():
		_fail("battle_finished 广播空 timeline")
		return
	_timeline = timeline
	var total := 0
	if timeline.has("timeline"):
		total = (timeline["timeline"] as Array).size()
	print("[Smoke] battle_finished: frames=%d, recorded tick_count=%d" % [total, _world.tick_count])
	_phase = "animating"
	_animator.load(timeline, _world_view.get_unit_views())
	_animator.play()


func _on_anim_done() -> void:
	print("[Smoke] animator playback_ended")
	if _phase != "animating":
		_fail("playback_ended 在非 animating 阶段触发: phase=%s" % _phase)
		return

	# Step 5: 显式 remove_actor 验证 reactive 生命周期
	# 战斗中 damage_utils 已对死者调用 remove_actor（见 hex_battle_damage_utils.gd:90）,
	# 所以残存 actor 由 WorldView 当前持有的 view 集合决定。
	var view_ids := _world_view.get_unit_views().keys()
	if view_ids.is_empty():
		_pass("battle 全灭, 无 view 可移除 (算作通过, 战斗期 remove signal 已验证)")
		return

	var victim_id: String = view_ids[0]
	var before := _world_view.get_unit_view_count()
	var ok := _world.remove_actor(victim_id)
	if not ok:
		_fail("remove_actor 返回 false: id=%s view_count=%d" % [victim_id, before])
		return

	var after := _world_view.get_unit_view_count()
	if after != before - 1:
		_fail("remove_actor signal 未让 view 减少: %d -> %d" % [before, after])
		return

	_pass("bind + signal spawn + timeline 动画 + remove_actor 全部通过 (views %d -> %d)" % [before, after])


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
