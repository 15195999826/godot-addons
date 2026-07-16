class_name OptionProvider
extends RefCounted
## 接口：列出「本轮值得考虑的选择」——不承诺当前可执行（ADR 0022 修订：
## 软条件不满足的目标也该在场，planner 必须看到暂不可行的目标才能回溯
## 准备步；硬门槛过滤是项目策略）。项目实现（候选从哪来是项目知识：
## 相位骨架/习性补丁/镇况门槛，或技能表/目标组合……）。
##
## 返回的候选无需预排序——Pipeline 会按 id 字典序排定（确定性由框架
## 保证，禁止依赖生成顺序）；但 id 必须唯一。
## 每次 provide 应新建 DecisionOption 实例：option/payload 是引用共享，
## 跨决策复用实例会让下游误写造成污染（GDScript 无 freeze，靠此纪律）。


func provide(_snapshot: DecisionSnapshot) -> Array[DecisionOption]:
	Log.assert_crash(false, "OptionProvider", "provide() 未实现（接口方法）")
	return []
