## smoke_frontend_main - 前端场景加载 + 期望 view 创建冒烟（headless 友好）
##
## 加载 dota2_lane_battle.tscn，让私有 logic clock block 在主循环跑几秒，检查：
##   1. 场景实例化不崩；debug Label 存在且被填充
##   2. logic clock 推进（tick > 0）+ 快照含两波单位（8）
##   3. 战斗在推进（有单位存活或已分出胜负，且 recent events 有内容）
##   4. 退出码 0
## 编辑器 F6 打开 dota2_lane_battle.tscn 比此 smoke 更直观看 ARAM 对线 + 富 debug 面板。
extends Node


const SCENE_PATH := "res://addons/logic-game-framework/example/dota2-auto-battle/frontend/scene/dota2_lane_battle.tscn"
const RUN_SECONDS := 3.0
const EXPECTED_SPAWN := 8


var _scene: Node = null


func _ready() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("failed to load scene: %s" % SCENE_PATH)
		return
	_scene = packed.instantiate()
	add_child(_scene)

	# 让 _ready 链跑完（GameWorld / world / procedure / 首帧）。
	for _i in range(5):
		await get_tree().process_frame

	var debug_label := _scene.get_node_or_null("HUD/Debug") as Label
	if debug_label == null:
		_fail("debug Label HUD/Debug not found")
		return

	var first_frame: Dota2LogicFrame = _scene._latest_frame
	if first_frame == null:
		_fail("scene produced no logic frame after _ready")
		return
	if first_frame.actor_snapshots.size() != EXPECTED_SPAWN:
		_fail("expected %d actor snapshots, got %d" % [EXPECTED_SPAWN, first_frame.actor_snapshots.size()])
		return

	# 主循环跑 RUN_SECONDS：私有 logic clock block 推进战斗。
	await get_tree().create_timer(RUN_SECONDS).timeout

	var proc: Dota2AutoBattleProcedure = _scene._procedure
	if proc == null:
		_fail("scene procedure missing after run")
		return
	if proc.get_tick_index() <= 1:
		_fail("logic clock did not advance (tick=%d)" % proc.get_tick_index())
		return
	if String(debug_label.text).find("DOTA2 Auto Battle") < 0:
		_fail("debug panel not populated")
		return
	if _scene._recent_events.is_empty():
		_fail("no recent events surfaced to debug panel after %.1fs" % RUN_SECONDS)
		return

	print("SMOKE_TEST_RESULT: PASS - frontend scene loaded; logic clock advanced to tick=%d; debug panel + %d recent events; result=%s" % [
		proc.get_tick_index(), _scene._recent_events.size(), proc.get_result()])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
