class_name GoalBacktrackReasoner
extends Reasoner
## GOAP-lite：供需标签回溯——无谓词世界、无假未来模拟、链长封顶。
##
## 机制（本类实现，子类勿动）：按目标优先序逐个验证可行性——requires 全
## 满足即直接做；有缺口则沿 provides 供需表回溯找准备步（一次查表，非
## 搜索）；每步重验——只产出「当前该做的一步」，从不产出承诺执行的计划，
## 准备步完成后调用方对真实世界重新决策。
##
## 策略（项目实现，虚函数）：打分 _score / 条件判定 _is_requirement_met /
## 条件缺口标签 _requirement_tag；可覆写 _rank_goals（默认分降序 argmax，
## 需要随机趣味时覆写为加权抽取序）与 _reason_for。
## goal 粘性等偏置写在项目的 _score / _rank_goals 里，框架不管。


## 链长上限（含目标本身）。默认 2（准备步+目标）：两步链的因果一句话
## 说得清（「为了买剑先去挣钱」），三步起叙述与调试成本陡增。放宽 = 改参数。
var max_chain_depth: int = 2


func _init(p_max_chain_depth: int = 2) -> void:
	max_chain_depth = p_max_chain_depth


# ==================== 策略孔（项目实现） ====================

## 候选打分。目标与准备步共用同一把尺；粘性/偏置在此实现。
func _score(_option: DecisionOption, _snapshot: DecisionSnapshot) -> float:
	Log.assert_crash(false, "GoalBacktrackReasoner", "_score() 未实现")
	return 0.0


## 条件当前是否满足——对快照里的真实世界判断，永不预测未来。
func _is_requirement_met(_requirement: Dictionary, _snapshot: DecisionSnapshot) -> bool:
	Log.assert_crash(false, "GoalBacktrackReasoner", "_is_requirement_met() 未实现")
	return false


## 条件缺口对应的需求标签（供需表的需求侧，如 min_purse → "money"）。
func _requirement_tag(_requirement: Dictionary) -> String:
	Log.assert_crash(false, "GoalBacktrackReasoner", "_requirement_tag() 未实现")
	return ""


## 目标尝试序。默认：分降序、同分 id 字典序（确定性 argmax）。
## 需要随机趣味的项目覆写为加权抽取序（rng 在此用）。
func _rank_goals(options: Array[DecisionOption], scores: Dictionary,
		_snapshot: DecisionSnapshot, _rng: RandomNumberGenerator) -> Array[DecisionOption]:
	var ranked := options.duplicate()
	ranked.sort_custom(func(a: DecisionOption, b: DecisionOption) -> bool:
		var score_a: float = scores[a.id]
		var score_b: float = scores[b.id]
		if score_a != score_b:
			return score_a > score_b
		return a.id < b.id)
	return ranked


## 打分明细（breakdown 条目 parts 字段的来源，debug 下钻消费）。
## 默认空——不需要下钻的项目零成本；实现时通常与 _score 共享一次计算
## （怎么组织归项目，框架不强求缓存）。
func _score_parts(_option: DecisionOption, _snapshot: DecisionSnapshot) -> Dictionary:
	return {}


## reason_key 生成。默认 = 最终目标的 id；项目通常映射为权重因子。
func _reason_for(goal: DecisionOption, _snapshot: DecisionSnapshot) -> String:
	return goal.id


# ==================== 机制（框架实现） ====================

func decide(snapshot: DecisionSnapshot, options: Array[DecisionOption],
		rng: RandomNumberGenerator) -> DecisionResult:
	var scores := {}
	var breakdown_by_id := {}
	var breakdown: Array[Dictionary] = []
	for option in options:
		var option_score := _score(option, snapshot)
		scores[option.id] = option_score
		var entry := {
			"option_id": option.id, "score": option_score,
			"parts": _score_parts(option, snapshot), "rejected": "",
		}
		breakdown_by_id[option.id] = entry
		breakdown.append(entry)
	for goal in _rank_goals(options, scores, snapshot, rng):
		var chain := _plan(goal, options, scores, snapshot,
			{ goal.id: true }, max_chain_depth)
		if chain.is_empty():
			breakdown_by_id[goal.id]["rejected"] = "unreachable"
			continue
		var result := DecisionResult.new()
		result.selected = chain[0]
		result.reason_key = _reason_for(goal, snapshot)
		if chain.size() > 1:
			for link in chain:
				result.chain.append(link.id)
		result.breakdown = breakdown
		return result
	# 全部目标不可行：selected 留空、breakdown 保留（Pipeline 据此产出
	# NO_FEASIBLE_OPTION——「为什么发呆」的下钻数据，ADR 0022 修订）。
	var infeasible := DecisionResult.new()
	infeasible.breakdown = breakdown
	return infeasible


## 从 cursor 反推执行链（浅递归回溯——仍是供需查表，不模拟世界状态）。
## 可达性 = cursor 的**每个**未满足条件都能在预算内找到可行供给链——
## 任一缺口无解即整体不可达（防「挣了钱却发现装备槽永远腾不出」的白跑）；
## 某缺口的最优供给者自身不可行时，自动尝试次优（分降序、同分 id 字典序）。
## 返回 [当前步, ..., cursor]：当前步取第一个缺口的可行供给链头——多缺口
## 不产出树形计划，其余缺口靠每步重验在后续决策中自然轮到。
## budget = 单条路径的剩余长度（含 cursor 自身）；visited = 当前路径上的
## 节点（成环防护，分支间各自复制）。空 = 不可达。
func _plan(cursor: DecisionOption, options: Array[DecisionOption],
		scores: Dictionary, snapshot: DecisionSnapshot,
		visited: Dictionary, budget: int) -> Array[DecisionOption]:
	var unmet_list := _unmet_requirements(cursor, snapshot)
	if unmet_list.is_empty():
		return [cursor]
	if budget <= 1:
		return []
	var head_chain: Array[DecisionOption] = []
	for requirement in unmet_list:
		var tag := _requirement_tag(requirement)
		var solved: Array[DecisionOption] = []
		for provider in _ranked_providers(tag, options, scores, visited):
			var branch_visited := visited.duplicate()
			branch_visited[provider.id] = true
			solved = _plan(provider, options, scores, snapshot,
				branch_visited, budget - 1)
			if not solved.is_empty():
				break
		if solved.is_empty():
			return []
		if head_chain.is_empty():
			head_chain = solved
	var chain := head_chain.duplicate()
	chain.append(cursor)
	return chain


## requires 定义序里全部未满足的条件（定义序即遍历序，确定性）。
func _unmet_requirements(option: DecisionOption,
		snapshot: DecisionSnapshot) -> Array[Dictionary]:
	var unmet: Array[Dictionary] = []
	for requirement in option.requires:
		if not _is_requirement_met(requirement, snapshot):
			unmet.append(requirement)
	return unmet


## provides 含 tag 的候选，按分降序、同分 id 字典序（确定性兜底）；
## 跳过当前路径上已访问的（成环防护）。
func _ranked_providers(tag: String, options: Array[DecisionOption],
		scores: Dictionary, visited: Dictionary) -> Array[DecisionOption]:
	var providers: Array[DecisionOption] = []
	for option in options:
		if not visited.has(option.id) and option.provides.has(tag):
			providers.append(option)
	providers.sort_custom(func(a: DecisionOption, b: DecisionOption) -> bool:
		var score_a: float = scores[a.id]
		var score_b: float = scores[b.id]
		if score_a != score_b:
			return score_a > score_b
		return a.id < b.id)
	return providers
