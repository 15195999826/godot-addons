class_name Reasoner
extends RefCounted
## 接口：怎么选 + 为什么。算法与参数全归项目（机制与策略分离）——
## utility 加权 / 规则表 / GOAP-lite（见 GoalBacktrackReasoner）都只是
## 本接口的不同实现，共用同一套 Snapshot/Option/Result。
##
## 三条合同：
## 1. 恒返回非 null 的 DecisionResult（ADR 0022 修订，「null = 合法结果」
##    退役）：选中时 selected 与 reason_key 非空（Pipeline 校验）；判全部
##    不可行时返回 selected 为空的 DecisionResult 且 breakdown 仍须填——
##    Pipeline 据此产出 NO_FEASIBLE_OPTION（未选中的下钻数据）。
## 2. 不修改 snapshot 与 options（只读输入）。
## 3. 随机只用传入的 rng——框架与 Reasoner 都不持有随机源，
##    确定性责任在调用方（如区域 RNG 流）。


func decide(_snapshot: DecisionSnapshot, _options: Array[DecisionOption],
		_rng: RandomNumberGenerator) -> DecisionResult:
	Log.assert_crash(false, "Reasoner", "decide() 未实现（接口方法）")
	return null
