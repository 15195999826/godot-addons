## RTS Pathfinding Validation smoke (P3.3 — 4 寻路验证 scenario 入口)
##
## 跑 4 个寻路验证 scenario 走 RtsScenarioHarness 框架, 全 PASS 才整体 PASS。
##
## 4 验证点:
##   1. scenario_pathfind_around_building — 绕 building footprint
##   2. scenario_8_units_no_overlap — 8 单位互避障 + formation
##   3. scenario_formation_preserved — 4 单位 formation 保形
##   4. scenario_dynamic_obstacle_repath — 中段动态障碍触发 stuck recovery + 绕行
##
## 任一 fail → 输出 [scenario_<name>] FAIL: <reason> + exit 1。
extends Node


const SCENARIO_PATHS: Array[String] = [
	"res://addons/logic-game-framework/example/rts-auto-battle/tests/battle/scenarios/scenario_pathfind_around_building.gd",
	"res://addons/logic-game-framework/example/rts-auto-battle/tests/battle/scenarios/scenario_8_units_no_overlap.gd",
	"res://addons/logic-game-framework/example/rts-auto-battle/tests/battle/scenarios/scenario_formation_preserved.gd",
	"res://addons/logic-game-framework/example/rts-auto-battle/tests/battle/scenarios/scenario_dynamic_obstacle_repath.gd",
]


func _ready() -> void:
	GameWorld.init()

	var summaries: Array[String] = []
	var any_failed: bool = false

	for path in SCENARIO_PATHS:
		var script: GDScript = load(path) as GDScript
		if script == null:
			print("SMOKE_TEST_RESULT: FAIL - failed to load scenario script: %s" % path)
			get_tree().quit(1)
			return
		var scenario: RtsScenario = script.new() as RtsScenario
		if scenario == null:
			print("SMOKE_TEST_RESULT: FAIL - script does not extend RtsScenario: %s" % path)
			get_tree().quit(1)
			return

		var result: Dictionary = RtsScenarioHarness.run(scenario, self)
		var name: String = result.get("scenario_name", "?") as String
		var success: bool = result.get("success", false)
		var ticks: int = int(result.get("ticks", 0))
		var fail_reason: String = result.get("fail_reason", "") as String

		if success:
			summaries.append("[%s] PASS ticks=%d events=%d cmds=%d" % [
				name, ticks, int(result.get("events_count", 0)),
				int(result.get("player_commands_count", 0)),
			])
		else:
			summaries.append("[%s] FAIL: %s (ticks=%d)" % [name, fail_reason, ticks])
			any_failed = true

	for s in summaries:
		print(s)

	GameWorld.destroy()

	if any_failed:
		print("SMOKE_TEST_RESULT: FAIL - one or more pathfinding scenarios failed (see above)")
		get_tree().quit(1)
	else:
		print("SMOKE_TEST_RESULT: PASS - 4/4 pathfinding scenarios passed")
		get_tree().quit(0)
