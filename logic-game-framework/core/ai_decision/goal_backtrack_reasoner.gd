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
			"parts": {}, "rejected": "",
		}
		breakdown_by_id[option.id] = entry
		breakdown.append(entry)
	for goal in _rank_goals(options, scores, snapshot, rng):
		var chain := _resolve_chain(goal, options, scores, snapshot)
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
	return null


## 从目标反推当前该做的一步。返回 [当前步, ..., goal]；空 = 当前不可达
## （缺口无供给 / 超链长 / 供需成环）。
func _resolve_chain(goal: DecisionOption, options: Array[DecisionOption],
		scores: Dictionary, snapshot: DecisionSnapshot) -> Array[DecisionOption]:
	var chain: Array[DecisionOption] = [goal]
	var visited := { goal.id: true }
	var cursor := goal
	while true:
		var unmet := _first_unmet(cursor, snapshot)
		if unmet.is_empty():
			return chain
		if chain.size() >= max_chain_depth:
			return []
		var tag := _requirement_tag(unmet)
		var prep := _best_provider(tag, options, scores, visited)
		if prep == null:
			return []
		chain.push_front(prep)
		visited[prep.id] = true
		cursor = prep
	return []


## requires 定义序里第一个未满足的条件；全满足返回 {}（值类型无结果惯例）。
func _first_unmet(option: DecisionOption, snapshot: DecisionSnapshot) -> Dictionary:
	for requirement in option.requires:
		if not _is_requirement_met(requirement, snapshot):
			return requirement
	return {}


## provides 含 tag 的候选中分最高者（同分 id 字典序；跳过链上已访问的——
## 供需成环的防护）。无供给者返回 null。
func _best_provider(tag: String, options: Array[DecisionOption],
		scores: Dictionary, visited: Dictionary) -> DecisionOption:
	var best: DecisionOption = null
	for option in options:
		if visited.has(option.id) or not option.provides.has(tag):
			continue
		if best == null:
			best = option
			continue
		var option_score: float = scores[option.id]
		var best_score: float = scores[best.id]
		if option_score > best_score \
				or (option_score == best_score and option.id < best.id):
			best = option
	return best
