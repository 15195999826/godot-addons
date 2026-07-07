extends Node

## ai_decision 模块单元测试：Pipeline 确定性合同 + GoalBacktrackReasoner
## 回溯机制（headless，不依赖任何游戏内容）。


func _init() -> void:
	TestFramework.register_test("Pipeline - 空候选返回 null", _test_empty_options)
	TestFramework.register_test("Pipeline - 乱序输入与有序输入同结果（确定性）", _test_order_independence)
	TestFramework.register_test("Pipeline - 同 seed 双跑同结果", _test_same_seed_same_result)
	TestFramework.register_test("Pipeline - snapshot 只读校验通过（content_hash 路径）", _test_snapshot_hash_ok)
	TestFramework.register_test("Backtrack - requires 满足时直接选目标, chain 为空", _test_direct_goal)
	TestFramework.register_test("Backtrack - requires 缺口回溯到准备步, chain 正确", _test_backtrack_chain)
	TestFramework.register_test("Backtrack - depth=1 禁回溯, 落到次优可行目标", _test_depth_limit)
	TestFramework.register_test("Backtrack - 缺口无供给者, 目标标记 unreachable", _test_no_provider)
	TestFramework.register_test("Backtrack - 供需成环不死循环, 全不可行返回可行兜底", _test_cycle_guard)
	TestFramework.register_test("Backtrack - 同分供给者按 id 字典序（确定性兜底）", _test_provider_tiebreak)
	TestFramework.register_test("Backtrack - breakdown 条目齐全", _test_breakdown_complete)


# ============================================================
# 测试替身
# ============================================================

## 测试快照：has_money 一个事实 + 内容指纹（只读合同路径）。
class SnapshotStub:
	extends DecisionSnapshot

	var has_money: bool = false

	func _init(p_has_money: bool) -> void:
		has_money = p_has_money

	func content_hash() -> int:
		return hash(has_money)


## 测试 Provider：按固定描述表生成候选（provide 每次新建实例，模拟真实用法）。
class ProviderStub:
	extends OptionProvider

	## 每条: { id, score, requires: Array[Dictionary], provides: Array }
	var specs: Array[Dictionary] = []
	var reverse_order: bool = false

	func _init(p_specs: Array[Dictionary], p_reverse := false) -> void:
		specs = p_specs
		reverse_order = p_reverse

	func provide(_snapshot: DecisionSnapshot) -> Array[DecisionOption]:
		var options: Array[DecisionOption] = []
		for spec in specs:
			var option := DecisionOption.new(str(spec["id"]), { "score": spec["score"] })
			var raw_requires: Array = spec.get("requires", []) as Array
			for requirement in raw_requires:
				option.requires.append(requirement as Dictionary)
			var raw_provides: Array = spec.get("provides", []) as Array
			for tag in raw_provides:
				option.provides.append(str(tag))
			options.append(option)
		if reverse_order:
			options.reverse()
		return options


## 测试 Reasoner：打分读 payload["score"]；条件只认 {type:"money"}，
## 满足与否读快照 has_money；缺口标签固定 "money"。
class BacktrackStub:
	extends GoalBacktrackReasoner

	func _init(p_max_chain_depth: int = 2) -> void:
		super._init(p_max_chain_depth)

	func _score(option: DecisionOption, _snapshot: DecisionSnapshot) -> float:
		return option.payload["score"] as float

	func _is_requirement_met(requirement: Dictionary, snapshot: DecisionSnapshot) -> bool:
		if str(requirement["type"]) == "money":
			return (snapshot as SnapshotStub).has_money
		return true

	func _requirement_tag(requirement: Dictionary) -> String:
		return str(requirement["type"])


## 标准小世界：买剑（高分，要钱）/ 挣钱（低分，供钱）/ 散步（中分，无门槛）。
func _standard_specs() -> Array[Dictionary]:
	return [
		{ "id": "buy_sword", "score": 100.0,
			"requires": [ { "type": "money" } ], "provides": [] },
		{ "id": "earn_money", "score": 10.0, "requires": [], "provides": ["money"] },
		{ "id": "stroll", "score": 20.0, "requires": [], "provides": [] },
	]


func _run(specs: Array[Dictionary], has_money: bool, depth := 2,
		reverse := false, seed_value := 1234) -> DecisionResult:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return DecisionPipeline.run(SnapshotStub.new(has_money),
		ProviderStub.new(specs, reverse), BacktrackStub.new(depth), rng)


# ============================================================
# Pipeline 合同
# ============================================================

func _test_empty_options() -> void:
	var empty_specs: Array[Dictionary] = []
	var result := _run(empty_specs, true)
	TestFramework.assert_true(result == null, "空候选应返回 null")


func _test_order_independence() -> void:
	var forward := _run(_standard_specs(), false, 2, false)
	var reversed_input := _run(_standard_specs(), false, 2, true)
	TestFramework.assert_equal(forward.selected.id, reversed_input.selected.id)
	TestFramework.assert_equal(forward.chain, reversed_input.chain)


func _test_same_seed_same_result() -> void:
	var first := _run(_standard_specs(), true, 2, false, 42)
	var second := _run(_standard_specs(), true, 2, false, 42)
	TestFramework.assert_equal(first.selected.id, second.selected.id)
	TestFramework.assert_equal(first.reason_key, second.reason_key)


func _test_snapshot_hash_ok() -> void:
	# SnapshotStub 实现了 content_hash；decide 不改快照 → 只读校验静默通过。
	var result := _run(_standard_specs(), true)
	TestFramework.assert_true(result != null, "只读校验不应误伤正常决策")


# ============================================================
# GoalBacktrackReasoner 机制
# ============================================================

func _test_direct_goal() -> void:
	var result := _run(_standard_specs(), true)
	TestFramework.assert_equal("buy_sword", result.selected.id)
	TestFramework.assert_true(result.chain.is_empty(), "直接可行不应有回溯链")
	TestFramework.assert_equal("buy_sword", result.reason_key)


func _test_backtrack_chain() -> void:
	var result := _run(_standard_specs(), false)
	TestFramework.assert_equal("earn_money", result.selected.id)
	var expected_chain: Array[String] = ["earn_money", "buy_sword"]
	TestFramework.assert_equal(expected_chain, result.chain)
	# reason 应继承最终目标（为了买剑），不是准备步
	TestFramework.assert_equal("buy_sword", result.reason_key)


func _test_depth_limit() -> void:
	var result := _run(_standard_specs(), false, 1)
	# depth=1 禁回溯, buy_sword 不可达, 应落到次优可行目标
	TestFramework.assert_equal("stroll", result.selected.id)


func _test_no_provider() -> void:
	var specs: Array[Dictionary] = [
		{ "id": "buy_sword", "score": 100.0,
			"requires": [ { "type": "money" } ], "provides": [] },
		{ "id": "stroll", "score": 20.0, "requires": [], "provides": [] },
	]
	var result := _run(specs, false)
	TestFramework.assert_equal("stroll", result.selected.id)
	for entry in result.breakdown:
		if str(entry["option_id"]) == "buy_sword":
			TestFramework.assert_equal("unreachable", entry["rejected"])


func _test_cycle_guard() -> void:
	# a 要 x 供 y；b 要 y 供 x——互为前置的环。走不通但绝不能死循环。
	var specs: Array[Dictionary] = [
		{ "id": "a", "score": 100.0,
			"requires": [ { "type": "x" } ], "provides": ["y"] },
		{ "id": "b", "score": 90.0,
			"requires": [ { "type": "y" } ], "provides": ["x"] },
		{ "id": "stroll", "score": 1.0, "requires": [], "provides": [] },
	]
	# BacktrackStub 对非 money 条件一律返回 true？不——它 return true 会让
	# a/b 直接可行。这里需要 x/y 永不满足的替身。
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var result := DecisionPipeline.run(SnapshotStub.new(false),
		ProviderStub.new(specs), CycleStub.new(3), rng)
	TestFramework.assert_true(result != null, "环防护后应落到可行兜底")
	TestFramework.assert_equal("stroll", result.selected.id)


## 环测试替身：x/y 条件永不满足（深度放到 3 以证明是环防护挡住而非链长）。
class CycleStub:
	extends GoalBacktrackReasoner

	func _init(p_max_chain_depth: int = 3) -> void:
		super._init(p_max_chain_depth)

	func _score(option: DecisionOption, _snapshot: DecisionSnapshot) -> float:
		return option.payload["score"] as float

	func _is_requirement_met(_requirement: Dictionary, _snapshot: DecisionSnapshot) -> bool:
		return false

	func _requirement_tag(requirement: Dictionary) -> String:
		return str(requirement["type"])


func _test_provider_tiebreak() -> void:
	var specs: Array[Dictionary] = [
		{ "id": "buy_sword", "score": 100.0,
			"requires": [ { "type": "money" } ], "provides": [] },
		{ "id": "work_b", "score": 10.0, "requires": [], "provides": ["money"] },
		{ "id": "work_a", "score": 10.0, "requires": [], "provides": ["money"] },
	]
	var result := _run(specs, false)
	# 同分供给者应按 id 字典序取小（确定性兜底）
	TestFramework.assert_equal("work_a", result.selected.id)


func _test_breakdown_complete() -> void:
	var result := _run(_standard_specs(), false)
	TestFramework.assert_equal(3, result.breakdown.size())
	for entry in result.breakdown:
		TestFramework.assert_true(entry.has("option_id") and entry.has("score")
			and entry.has("parts") and entry.has("rejected"),
			"breakdown 条目字段约定齐全")
