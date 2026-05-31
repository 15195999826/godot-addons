## Smoke test: headless 模式下加载 frontend main.tscn，触发 Start Battle，播放到结束
##
## 目标：验证 frontend 完整链路（配置 UI → core 战斗 → battle_finished signal →
##      WorldView spawn unit views → BattleAnimator 播放 → playback_ended）
##      不验证视觉正确性，只验证"逻辑 + 表演调度"跑通不崩。
##
## 覆盖的回归面：
##   - main.tscn 能在 headless 下实例化（无 Viewport 也不炸）
##   - _on_start_battle_button_pressed() 同步跑完 logic battle 并触发 animator.play
##   - WorldView 响应式 spawn unit views
##   - BattleAnimator + Director tick + ActionScheduler 把所有动作播到排空
##
## 不覆盖：像素渲染正确性、粒子视觉、相机跟随、音效
##
## 运行方式:
##   godot --headless --path . res://addons/logic-game-framework/example/hex-atb-battle/tests/frontend/smoke_frontend_main.tscn
##
## 退出码: 0 PASS / 1 FAIL, 输出标记: "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


const MAIN_SCENE := "res://addons/logic-game-framework/example/hex-atb-battle/frontend/demo_frontend.tscn"
## 超时时间（秒）。100x 加速下，典型一场 200 帧 battle 约 0.3s 真实时间。
const TIMEOUT_SEC := 30.0
## 播放加速倍率，压缩真实耗时。过高会让单帧推进的逻辑时间 > 动画持续时间导致视觉异常，
## 但 smoke test 不验证视觉，所以激进加速是安全的。
const PLAYBACK_SPEED := 100.0


var _main_scene: Node
var _world_view: FrontendWorldView
var _animator: FrontendBattleAnimator
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	print("=== Smoke Test: Frontend Main Scene Flow ===")
	print("Scene: %s" % MAIN_SCENE)
	print("Timeout: %.0fs, Speed: %.0fx" % [TIMEOUT_SEC, PLAYBACK_SPEED])
	print("")

	# 静音 Log，避免淹没测试输出（push_error 仍会由 Godot 自己走 stderr）
	Log.set_level(Log.LogLevel.WARNING)

	# Step 1: 加载并实例化 main.tscn
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("Failed to load " + MAIN_SCENE)
		return
	_main_scene = packed.instantiate()
	if _main_scene == null:
		_fail("Failed to instantiate main scene")
		return
	add_child(_main_scene)

	# 让 main._ready 跑完 (创建 WorldView / BattleAnimator 等)
	await get_tree().process_frame

	# Step 2: 定位 WorldView / BattleAnimator (main.gd 在 _setup_world_view_and_animator
	# 时设的 node name)
	_world_view = _main_scene.get_node_or_null("WorldView") as FrontendWorldView
	if _world_view == null:
		_fail("WorldView node not found under Main")
		return
	_animator = _main_scene.get_node_or_null("BattleAnimator") as FrontendBattleAnimator
	if _animator == null:
		_fail("BattleAnimator node not found under Main")
		return

	# Step 3: 同步触发 Start Battle (_on_start_battle_button_pressed 内部:
	# 创建 HexDemoWorldGameplayInstance -> WorldView.bind_world -> battle.start -> tick 跑完
	# -> battle_finished signal -> animator.play 同步触发)
	print("Step 1: Triggering start battle...")
	_main_scene.call("_on_start_battle_button_pressed")

	var total := _animator.get_total_frames()
	if total <= 0:
		_fail("Animator started but total_frames=%d (expected > 0)" % total)
		return
	var unit_count := _world_view.get_unit_view_count()
	if unit_count == 0:
		_fail("WorldView has no unit views after battle start")
		return
	print("  + Battle loaded: %d frames, %d unit views" % [total, unit_count])

	# Step 4: 加速播放并等 playback_ended
	# main.gd 的 _on_battle_finished 只 load 不 play(用户按 Play 才播放),
	# smoke 模拟 "用户按 Play" 显式触发。
	_animator.playback_ended.connect(_on_playback_ended, CONNECT_ONE_SHOT)
	_animator.set_speed(PLAYBACK_SPEED)
	_animator.play()
	print("Step 2: Playing at %.0fx ..." % PLAYBACK_SPEED)


func _process(delta: float) -> void:
	if _finished or _animator == null:
		return
	_elapsed += delta
	if _elapsed >= TIMEOUT_SEC:
		_fail("Playback did not end within %.0fs (current_frame=%d/%d)" % [
			TIMEOUT_SEC,
			_animator.get_current_frame(),
			_animator.get_total_frames(),
		])


func _on_playback_ended() -> void:
	if _finished:
		return
	print("Step 3: playback_ended signal received, asserting invariants...")

	# Invariant 1: is_ended() == true
	if not _animator.is_ended():
		_fail("playback_ended fired but animator.is_ended() is false")
		return

	# Invariant 2: current_frame 推进到总帧数
	var cur := _animator.get_current_frame()
	var tot := _animator.get_total_frames()
	if cur < tot:
		_fail("current_frame (%d) < total_frames (%d) at end" % [cur, tot])
		return

	# Invariant 3: WorldView 至少有一个 unit view
	var unit_count := _world_view.get_unit_view_count()
	if unit_count == 0:
		_fail("WorldView has no unit views after playback")
		return

	# Invariant 4: 所有 actor 的 visual_hp ∈ [0, max_hp]
	var snapshot := _animator.get_actors_snapshot()
	if snapshot.is_empty():
		_fail("animator.get_actors_snapshot() empty after playback")
		return
	for actor_id: String in snapshot.keys():
		var st: FrontendActorRenderState = snapshot[actor_id]
		if st.visual_hp < 0.0 or st.visual_hp > st.max_hp + 0.01:
			_fail("Actor %s hp out of range: %.2f / %.2f" % [actor_id, st.visual_hp, st.max_hp])
			return

	# Invariant 5: view ↔ logic 终态对账 (位置 / is_alive / hp / max_hp)
	# release build 下 demo._final_state 为空 → reconciler SKIPPED, smoke 仍 PASS。
	# 详见 addons/.../docs/reference/view-logic-reconciliation.md。
	var final_state: Dictionary = _main_scene.call("get_final_state")
	var report := await HexBattleViewLogicReconciler.reconcile(
		final_state, _animator, _world_view, get_tree()
	)
	if report.skipped:
		print("  + reconciliation   = SKIPPED (%s)" % report.skip_reason)
	elif not report.passed:
		_fail("view-logic reconcile: %s" % report.to_human_string())
		return
	else:
		print("  + reconciliation   = PASS (%d actors, %d ms settle, drift %.4f)" % [
			report.actor_count, report.settle_time_ms, report.settle_max_drift,
		])

	_pass(tot, cur, unit_count, snapshot.size())


func _pass(total_frames: int, current_frame: int, unit_count: int, actor_count: int) -> void:
	_finished = true
	print("  + is_ended         = true")
	print("  + frame            = %d / %d" % [current_frame, total_frames])
	print("  + unit views       = %d" % unit_count)
	print("  + actor snapshots  = %d" % actor_count)
	print("SMOKE_TEST_RESULT: PASS - frontend main scene flow ok")
	GameWorld.destroy()
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
