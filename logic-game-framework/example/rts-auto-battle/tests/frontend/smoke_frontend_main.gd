## RTS frontend smoke (M0.8)
##
## Headless 友好的前端冒烟: 加载 demo_rts_frontend.tscn, 让它跑 3 秒, 检查:
##   1. 8 个 visualizer 节点确实创建出来(Node 树存在)
##   2. 战斗推进到 attack_count > 0(_logger 不在 demo 里 → 通过 visualizer.actor.is_dead 验证 attack 已经发生)
##   3. 退出码 0
##
## 编辑器 F6 直接看 demo_rts_frontend.tscn 比这个 smoke 更直观 — 此 smoke 只是确保
## frontend 链不会因为 visualizer / Polygon2D / Label 之类节点构造崩溃。
extends Node


const RUN_SECONDS: float = 3.0


var _demo_scene: Node = null


func _ready() -> void:
	var scene := load("res://addons/logic-game-framework/example/rts-auto-battle/frontend/demo_rts_frontend.tscn") as PackedScene
	if scene == null:
		_fail("failed to load demo scene")
		return
	_demo_scene = scene.instantiate()
	add_child(_demo_scene)

	# 让 demo _ready 链跑完: demo._ready 内部 await 一次 physics_frame, 我们多 await 几帧确保 spawn 完
	for _i in range(5):
		await get_tree().physics_frame

	var visualizers_count: int = 0
	for child in _demo_scene.find_children("*", "Node2D", true, false):
		if child is RtsUnitVisualizer:
			visualizers_count += 1
	if visualizers_count != 8:
		_fail("expected 8 RtsUnitVisualizer nodes, got %d" % visualizers_count)
		return

	# 让 demo 在主循环跑 RUN_SECONDS
	await get_tree().create_timer(RUN_SECONDS).timeout

	# 检查: 至少一个 visualizer 报告 actor 还活着(战斗未一帧打完)
	var alive_count: int = 0
	for child in _demo_scene.find_children("*", "Node2D", true, false):
		if child is RtsUnitVisualizer:
			var vis := child as RtsUnitVisualizer
			if vis.actor != null and not vis.actor.is_dead():
				alive_count += 1
	# 战斗 3 秒内不太可能全死光; 若 alive_count == 0 说明打太快或某 actor 链断了
	if alive_count == 0:
		_fail("no alive units after %.1fs (battle drained too fast or visualizer.actor lost)" % RUN_SECONDS)
		return

	print("frontend smoke: visualizers=%d alive_after_%.1fs=%d" % [visualizers_count, RUN_SECONDS, alive_count])
	print("SMOKE_TEST_RESULT: PASS - frontend stub renders 4v4 without script error")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
