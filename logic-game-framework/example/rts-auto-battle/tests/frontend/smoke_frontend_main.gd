## RTS frontend smoke (P2.7 升级 director push 模式; P2.8 加 flying / 城堡战争布局)
##
## Headless 友好的前端冒烟: 加载 demo_rts_frontend.tscn, 让它跑 3 秒, 检查:
##   1. EXPECTED_VISUALIZERS 个 RtsUnitVisualizer 节点创建出来 (P2.8: 4v4 ground + 1 flying / 方 = 10)
##   2. 战斗推进 (至少一个 visualizer 还活着, 未一帧打完)
##   3. 退出码 0
##
## P2.7 改动: visualizer.actor 字段已删 (AC6: frontend 0 处 actor 直读). 改用 visualizer.actor_id
## + visualizer.get_render_is_dead() — 状态来自 RtsBattleDirector push 而非 polling.
##
## P2.8 改动: demo 升级为城堡战争布局 — 双方 crystal_tower + archer_tower (走 RtsBuildingVisualizer)
## + 4 个 ground unit + 1 flying_scout / 方; unit visualizer 数 = 4 ground + 1 flying = 5 / 方 = 10 总。
##
## 编辑器 F6 直接看 demo_rts_frontend.tscn 比此 smoke 更直观 — smoke 只确保 frontend 链不会因为
## visualizer / WorldView / Director 之类节点构造崩溃.
extends Node


const RUN_SECONDS: float = 3.0
const EXPECTED_VISUALIZERS: int = 10  # P2.8: 4 ground + 1 flying per team * 2 teams


var _demo_scene: Node = null


func _ready() -> void:
	var scene := load("res://addons/logic-game-framework/example/rts-auto-battle/frontend/demo_rts_frontend.tscn") as PackedScene
	if scene == null:
		_fail("failed to load demo scene")
		return
	_demo_scene = scene.instantiate()
	add_child(_demo_scene)

	# 让 demo _ready 链跑完: demo._ready 内部多步 wire (world / battle_map / director / world_view /
	# spawn / start_rts_battle / director.attach), 多 await 几帧确保 spawn 完
	for _i in range(5):
		await get_tree().physics_frame

	var visualizers_count: int = 0
	for child in _demo_scene.find_children("*", "Node2D", true, false):
		if child is RtsUnitVisualizer:
			visualizers_count += 1
	if visualizers_count != EXPECTED_VISUALIZERS:
		_fail("expected %d RtsUnitVisualizer nodes, got %d" % [EXPECTED_VISUALIZERS, visualizers_count])
		return

	# 让 demo 在主循环跑 RUN_SECONDS
	await get_tree().create_timer(RUN_SECONDS).timeout

	# 检查: 至少一个 visualizer 报告 actor 还活着 (P2.7 走 visualizer 自身 render state, 不读 actor)
	var alive_count: int = 0
	for child in _demo_scene.find_children("*", "Node2D", true, false):
		if child is RtsUnitVisualizer:
			var vis := child as RtsUnitVisualizer
			if vis.actor_id != "" and not vis.get_render_is_dead():
				alive_count += 1
	# 战斗 3 秒内不太可能全死光; 若 alive_count == 0 说明打太快或某 actor 链断了
	if alive_count == 0:
		_fail("no alive units after %.1fs (battle drained too fast or visualizer wiring broke)" % RUN_SECONDS)
		return

	print("frontend smoke: visualizers=%d alive_after_%.1fs=%d" % [visualizers_count, RUN_SECONDS, alive_count])
	print("SMOKE_TEST_RESULT: PASS - frontend stub renders 4v4 via director without script error")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
