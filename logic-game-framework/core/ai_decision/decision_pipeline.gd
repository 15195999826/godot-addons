class_name DecisionPipeline
## 一次决策的组装与纪律执行（static 纯函数：无状态、不持有 RNG、不含
## 决策循环/执行/时机——那些全归调用方）。
##
## 框架卖的两条纪律在此强制执行：
## 1. 候选确定性：按 id 字典序排定（禁止依赖 Provider 的偶然生成序——
##    运行时偶然序会破坏 replay 可重现性），id 重复即断言。
## 2. 可解释性：非空结果必须带 reason_key——这是合同，不是项目自觉。
##
## 另执行 Snapshot 只读合同的机械检查（子类实现 content_hash 时生效）。


## 跑一次决策。空候选或 Reasoner 判无可行时返回 null（合法结果：
## 无事可做，idle 策略归调用方）。
static func run(snapshot: DecisionSnapshot, provider: OptionProvider,
		reasoner: Reasoner, rng: RandomNumberGenerator) -> DecisionResult:
	var options := provider.provide(snapshot)
	if options.is_empty():
		return null
	options.sort_custom(func(a: DecisionOption, b: DecisionOption) -> bool:
		return a.id < b.id)
	for i in options.size() - 1:
		Log.assert_crash(options[i].id != options[i + 1].id,
			"DecisionPipeline", "候选 id 重复: %s" % options[i].id)
	var hash_before := snapshot.content_hash()
	var result := reasoner.decide(snapshot, options, rng)
	if hash_before != 0:
		Log.assert_crash(snapshot.content_hash() == hash_before,
			"DecisionPipeline", "snapshot 在决策期间被修改（违反只读合同）")
	if result != null:
		Log.assert_crash(result.selected != null,
			"DecisionPipeline", "DecisionResult.selected 为空")
		Log.assert_crash(not result.reason_key.is_empty(),
			"DecisionPipeline", "reason_key 为空（违反可解释性合同）")
	return result
