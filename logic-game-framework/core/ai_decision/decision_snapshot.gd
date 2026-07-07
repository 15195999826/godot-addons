class_name DecisionSnapshot
extends RefCounted
## AI 眼中的世界切片——一次决策的唯一输入。项目子类化装具体字段。
##
## 三条合同：
## 1. 只读：构造完成后，决策期间（DecisionPipeline.run 全程）禁止修改。
##    子类可选实现 content_hash()，实现后 Pipeline 会在 decide 前后比对断言。
## 2. 切片：只装本次决策需要看的信息，禁止整世界拷贝——大小 ∝ 决策所需，
##    不 ∝ 世界大小。多 agent 共享的世界侧数据应由调用方构建一次复用
##    （共享切片 + per-agent 轻量追加）。
## 3. 感知地基：「这个 AI 看见什么」= 子类构造时的过滤策略。感知规则
##    （视野/情报传播等）归项目，加过滤不动框架。


## 可选的内容指纹。返回 0 = 不参与只读校验；返回非 0 时 Pipeline 在
## decide 前后比对，不一致即断言失败（只读合同的机械检查）。
func content_hash() -> int:
	return 0
