class_name DecisionResult
extends RefCounted
## 一次决策的产出：最终打算做什么 + 为什么 + 全过程明细。


## 选中的候选（当前该做的一步——GOAP-lite 下是链条的第一步，不是最终目标）。
var selected: DecisionOption = null
## 叙述因子（可解释性合同：非空，Pipeline 校验）。项目通常映射为
## 权重来源（"personality:greedy"）或目标 id，供叙述/通知/debug 消费。
var reason_key: String = ""
## GOAP-lite 回溯链的 option id 序列：[当前步, ..., 最终目标]。
## 空 = 直接决策（选中项自身即目标）。
var chain: Array[String] = []
## 全量候选打分明细，debug 消费（调用方分流：不进事件流/录制/存档）。
## 条目约定（debug UI 统一消费）：
##   { "option_id": String, "score": float, "parts": Dictionary,
##     "rejected": String }    # rejected 非空 = 落选原因（如 "unreachable"）
var breakdown: Array[Dictionary] = []
