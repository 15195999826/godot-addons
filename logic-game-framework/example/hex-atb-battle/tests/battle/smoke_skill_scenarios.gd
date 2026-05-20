## SkillScenario Runner - 扫描并执行所有 scenario，汇总 PASS/FAIL
##
## 扫 `addons/logic-game-framework/example/hex-atb-battle/tests/battle/skill_scenarios/`
## 下除基础设施文件外的所有 *.gd:
##   - 加载脚本
##   - 若类继承 SkillScenario → new() 实例 → 跑一次
##   - 收集 ScenarioAssertContext 的断言结果
##
## 输出:
##   每个 scenario 单独一行 PASS/FAIL；
##   末尾一行 `SMOKE_TEST_RESULT: PASS|FAIL - <N>/<M> scenarios passed`。
##
## 退出码:全部绿 → 0,否则 1。
extends Node


const SCENARIOS_DIR := "res://addons/logic-game-framework/example/hex-atb-battle/tests/battle/skill_scenarios/"
## 基础设施脚本不是 scenario，跳过
const INFRASTRUCTURE_FILES: Array[String] = [
	"skill_scenario.gd",
	"scenario_assert_context.gd",
]


var _results: Array[Dictionary] = []  # [{name, pass, failures}]


func _ready() -> void:
	print("=== Skill Scenarios Runner ===")
	print("Scanning %s" % SCENARIOS_DIR)
	print("")

	var scenario_paths := _find_scenario_paths()
	if scenario_paths.is_empty():
		print("SMOKE_TEST_RESULT: FAIL - no scenarios found under %s" % SCENARIOS_DIR)
		get_tree().quit(1)
		return

	for path in scenario_paths:
		_run_scenario(path)

	_report_and_exit()


func _find_scenario_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(SCENARIOS_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".gd"):
			if not INFRASTRUCTURE_FILES.has(fname):
				paths.append(SCENARIOS_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func _run_scenario(path: String) -> void:
	var script := load(path) as GDScript
	if script == null:
		_results.append({"name": path, "pass": false, "failures": ["Failed to load script"]})
		return

	var instance = script.new()
	if not (instance is SkillScenario):
		# 不是 scenario 子类,跳过(允许 scenarios 目录下有辅助文件)
		return

	var scenario: SkillScenario = instance
	var scenario_name := scenario.get_name()
	print("→ %s" % scenario_name)

	var actions := scenario.get_actions()
	if actions.is_empty():
		_results.append({"name": scenario_name, "pass": false, "failures": ["get_actions() returned empty (did you set get_active_skill or override get_actions?)"]})
		return

	var scene_config := scenario.get_scene_config()
	# 注入 caster_passives 到 scene_config
	var passives := scenario.get_passives()
	if not passives.is_empty():
		scene_config = scene_config.duplicate()
		scene_config["caster_passives"] = passives

	var result := HexBattleSkillScenarioHarness.run_with_actions(
		scene_config, actions, scenario.get_max_ticks()
	)

	# Phase 04: passive periodic timeline (如 Demon Form) 永不自停, max_ticks 触发 timeout
	# 但 replay 数据仍可消费; scenario 自行 assert 即可。其它 preview 失败 (early crash /
	# missing replay) 仍 fail。
	if not result.get("success", false):
		var errors: Array = result.get("errors", [])
		var only_timeout := errors.size() == 1 and str(errors[0]).begins_with("Preview timed out")
		if not only_timeout or result.get("replay", {}).is_empty():
			_results.append({
				"name": scenario_name,
				"pass": false,
				"failures": ["preview failed: %s" % str(errors)],
			})
			return

	var ctx := ScenarioAssertContext.new(result)
	scenario.assert_replay(ctx)

	_results.append({
		"name": scenario_name,
		"pass": ctx.is_pass(),
		"failures": ctx.get_failures(),
	})


func _report_and_exit() -> void:
	print("")
	print("--- Summary ---")
	var pass_count := 0
	for res in _results:
		var status := "PASS" if res["pass"] else "FAIL"
		print("  [%s] %s" % [status, res["name"]])
		if not res["pass"]:
			for f in res["failures"]:
				print("    · %s" % f)
		if res["pass"]:
			pass_count += 1

	var total: int = _results.size()
	var all_pass := pass_count == total

	print("")
	var marker := "PASS" if all_pass else "FAIL"
	print("SMOKE_TEST_RESULT: %s - %d/%d scenarios passed" % [marker, pass_count, total])
	get_tree().quit(0 if all_pass else 1)
