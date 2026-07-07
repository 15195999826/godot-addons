class_name DecisionOption
extends RefCounted
## 一个候选行为——「现在能做的一件事」。
## goal 是它的粗粒度形态：分层决策 = 先在 goal 粒度跑一次管线，再在
## 选中 goal 名下的具体行为上跑一次；框架不为此新增概念。


## 唯一 id，同时是管线的确定性排序键（重复 id 会被 Pipeline 断言拦截）。
var id: String = ""
## 项目自用载荷（活动定义引用 / 技能+目标组合等），框架不解释。
var payload: Dictionary = {}
## 类型化前置条件（如 { "type": "min_purse", "amount": 40 }）。框架不解释
## 内容；GoalBacktrackReasoner 经策略虚函数向项目询问满足与否/缺什么标签。
var requires: Array[Dictionary] = []
## 产出标签（供需表的供给侧，如 ["money"]）——GOAP-lite 回溯的匹配依据。
var provides: Array[String] = []


func _init(p_id: String = "", p_payload: Dictionary = {}) -> void:
	id = p_id
	payload = p_payload
