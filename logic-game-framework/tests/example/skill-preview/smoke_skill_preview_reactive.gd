## Smoke test: 阶段 3 验证 skill_preview 响应式切换
##
## 目标：SkillPreviewWorldGI 常驻 + FrontendWorldView bind + FrontendBattleAnimator
## 连续跑 3 场战斗（每场之间 reset + 重新 add_actor + start_battle）都能：
##   - reset 后 view 数归 0（mutation signal 正确触发）
##   - re-configure_grid + re-add_actor 让 view 数重新铺满（reactive re-spawn）
##   - start_battle -> battle_finished 产出非空 timeline
##   - BattleAnimator.play(timeline, views) 跑到 playback_ended 不崩
##   - 场与场之间 WorldView / Animator 节点保持同一实例（不被重建）
##
## 不覆盖：像素视觉正确性、UI 输入、相机、preset。
##
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


const TIMEOUT_SEC := 30.0
const ANIM_SPEED := 50.0
const BATTLE_COUNT := 3


var _world: SkillPreviewWorldGI
var _world_view: FrontendWorldView
var _animator: FrontendBattleAnimator

## 存 Node 引用做 "是否同一实例" 断言。instance_id 在 node free 后可能被重用
## (罕见但非零概率), 直接比较 Node ref 语义更直白。
var _world_view_ref: FrontendWorldView = null
var _animator_ref: FrontendBattleAnimator = null

var _battles_done: int = 0
var _elapsed: float = 0.0
var _finished: bool = false
var _phase: String = "init"

# 用于 strike: caster + 1 dummy
var _caster_id: String = ""
var _target_id: String = ""


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: skill_preview reactive path ===")

	GameWorld.init()

	_world = SkillPreviewWorldGI.new()
	GameWorld.create_instance(func() -> GameplayInstance: return _world)
	_world.start()
	_world.battle_finished.connect(_on_battle_finished)

	_world_view = FrontendWorldView.new()
	_world_view.name = "WorldView"
	add_child(_world_view)
	_world_view.bind_world(_world)
	_world_view_ref = _world_view

	_animator = FrontendBattleAnimator.new()
	_animator.name = "BattleAnimator"
	add_child(_animator)
	_animator.playback_ended.connect(_on_anim_done)
	_animator.set_speed(ANIM_SPEED)
	_animator_ref = _animator

	_start_next_battle()


func _process(dt: float) -> void:
	if _finished:
		return
	_elapsed += dt
	if _elapsed > TIMEOUT_SEC:
		_fail("timeout %.1fs in phase=%s battles_done=%d" % [_elapsed, _phase, _battles_done])


func _start_next_battle() -> void:
	_phase = "rebuild"

	# reset: 上一场残留 actor / grid 全部清掉; view 数应归 0
	_world.reset()
	if _world_view.get_unit_view_count() != 0:
		_fail("reset 后 view 未归 0: %d" % _world_view.get_unit_view_count())
		return

	# 基础 grid + strike 技能 timeline
	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = 3
	cfg.orientation = GridMapConfig.Orientation.FLAT
	cfg.size = 1.0
	_world.configure_grid(cfg)

	var collision_detector := MobaCollisionDetector.new()
	_world.add_system(ProjectileSystem.new(collision_detector, GameWorld.event_collector, false))
	HexBattleAllSkills.register_all_timelines()

	# caster: WARRIOR@(0,0), dummy: WARRIOR@(1,0)
	var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	caster._display_name = "caster"
	_world.add_actor(caster)
	caster.set_team_id(0)
	caster.attribute_set.set_max_hp_base(100.0)
	caster.attribute_set.set_hp_base(100.0)
	_world.grid.place_occupant(HexCoord.new(0, 0), caster)
	caster.hex_position = HexCoord.new(0, 0)

	var dummy := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	dummy._display_name = "dummy"
	_world.add_actor(dummy)
	dummy.set_team_id(1)
	dummy.attribute_set.set_max_hp_base(100.0)
	dummy.attribute_set.set_hp_base(100.0)
	_world.grid.place_occupant(HexCoord.new(1, 0), dummy)
	dummy.hex_position = HexCoord.new(1, 0)

	_caster_id = caster.get_id()
	_target_id = dummy.get_id()

	var view_count := _world_view.get_unit_view_count()
	if view_count != 2:
		_fail("rebuild 后 view 数 != 2: %d (battle=%d)" % [view_count, _battles_done + 1])
		return

	# 每次 rebuild 应复用同一 WorldView/Animator 节点
	if _world_view != _world_view_ref or not is_instance_valid(_world_view):
		_fail("WorldView 被重建 (battle=%d)" % (_battles_done + 1))
		return
	if _animator != _animator_ref or not is_instance_valid(_animator):
		_fail("Animator 被重建 (battle=%d)" % (_battles_done + 1))
		return

	# 发动 strike: 新 actor_setups API, caster t=0 一条 keyframe
	_world.queue_preview([{
		"actor_id": _caster_id,
		"passives": [] as Array[AbilityConfig],
		"track": [{
			"time_ms": 0,
			"ability_config": HexBattleStrike.ABILITY,
			"target_id": _target_id,
		}],
	}], false)

	var participants: Array[Actor] = []
	for actor in _world.get_actors():
		participants.append(actor)
	_world.start_battle(participants)

	_phase = "ticking"
	# BATTLE_TICKS_PER_WORLD_FRAME = INT_MAX → 一口气跑完同步 emit battle_finished
	_world.tick(100.0)


func _on_battle_finished(timeline: Dictionary) -> void:
	if _finished:
		return
	if timeline.is_empty():
		_fail("battle %d: empty timeline" % (_battles_done + 1))
		return
	_phase = "animating"
	_animator.load(timeline, _world_view.get_unit_views())
	_animator.play()


func _on_anim_done() -> void:
	if _finished:
		return
	if _phase != "animating":
		_fail("playback_ended 在非 animating: phase=%s" % _phase)
		return

	_battles_done += 1
	print("[Smoke] battle %d / %d done, views=%d" % [
		_battles_done, BATTLE_COUNT, _world_view.get_unit_view_count(),
	])

	if _battles_done >= BATTLE_COUNT:
		# 验证最后一场结束后显式 reset 能让 view 归 0
		_world.reset()
		if _world_view.get_unit_view_count() != 0:
			_fail("final reset 后 view 未归 0: %d" % _world_view.get_unit_view_count())
			return
		_pass("3 场连续战斗 OK, view/animator 实例复用 + reset 归 0 验证通过")
		return

	_start_next_battle()


func _pass(reason: String) -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - %s" % reason)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	push_error("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
