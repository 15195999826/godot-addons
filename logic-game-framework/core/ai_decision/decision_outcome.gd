class_name DecisionOutcome
extends RefCounted
## 一次决策的 typed outcome（ADR 0022 修订）：Pipeline 恒返回本类型，取代
## 「null = 合法结果」——「他为什么发呆」必须能区分无候选与全不可行。
##
## status 三态：SELECTED（选中，result 非 null）/ NO_OPTIONS（Provider 无
## 候选）/ NO_FEASIBLE_OPTION（有候选但 Reasoner 判全不可行）。
## breakdown 恒携带：SELECTED 时与 result.breakdown 同一引用；
## NO_FEASIBLE_OPTION 保留全量打分明细（含 rejected 落选原因——未选中
## 时的下钻数据）；NO_OPTIONS 恒空（没有候选就没有明细）。


const SELECTED := "selected"
const NO_OPTIONS := "no_options"
const NO_FEASIBLE_OPTION := "no_feasible_option"


var status: String = NO_OPTIONS
## 选中时的完整决策结果；仅 SELECTED 非 null。
var result: DecisionResult = null
## 全量候选打分明细（条目约定同 DecisionResult.breakdown）。
var breakdown: Array[Dictionary] = []


static func selected(p_result: DecisionResult) -> DecisionOutcome:
	var outcome := DecisionOutcome.new()
	outcome.status = SELECTED
	outcome.result = p_result
	outcome.breakdown = p_result.breakdown
	return outcome


static func no_options() -> DecisionOutcome:
	return DecisionOutcome.new()


static func no_feasible(p_breakdown: Array[Dictionary]) -> DecisionOutcome:
	var outcome := DecisionOutcome.new()
	outcome.status = NO_FEASIBLE_OPTION
	outcome.breakdown = p_breakdown
	return outcome
