class_name DecisionPipeline
## 一次决策的组装与纪律执行（static 纯函数：无状态、不持有 RNG、不含
## 决策循环/执行/时机——那些全归调用方）。
##
## 框架卖的三条纪律在此强制执行：
## 1. 候选确定性：按 id 字典序排定（禁止依赖 Provider 的偶然生成序——
##    运行时偶然序会破坏 replay 可重现性），id 重复即断言。
## 2. 可解释性：恒返回 DecisionOutcome（ADR 0022 修订，「null = 合法结果」
##    退役）——选中必带 reason_key；未选中也区分「无候选」与「全不可行」
##    并保留 breakdown。
## 3. Snapshot 只读：content_hash 在 Provider 之前采集、decide 之后复验
##    （子类实现 content_hash 时生效）——Provider 与 Reasoner 全程受检。


## 跑一次决策。恒返回 DecisionOutcome；idle 策略归调用方按 status 分流。
static func run(snapshot: DecisionSnapshot, provider: OptionProvider,
		reasoner: Reasoner, rng: RandomNumberGenerator) -> DecisionOutcome:
	var hash_before := snapshot.content_hash()
	var options := provider.provide(snapshot)
	if options.is_empty():
		_check_readonly(snapshot, hash_before)
		return DecisionOutcome.no_options()
	options.sort_custom(func(a: DecisionOption, b: DecisionOption) -> bool:
		return a.id < b.id)
	for i in options.size() - 1:
		Log.assert_crash(options[i].id != options[i + 1].id,
			"DecisionPipeline", "候选 id 重复: %s" % options[i].id)
	var result := reasoner.decide(snapshot, options, rng)
	_check_readonly(snapshot, hash_before)
	Log.assert_crash(result != null, "DecisionPipeline",
		"decide() 返回 null——判全不可行应返回 selected 为空的 DecisionResult（带 breakdown）")
	if result.selected == null:
		return DecisionOutcome.no_feasible(result.breakdown)
	Log.assert_crash(options.has(result.selected),
		"DecisionPipeline", "selected 不在候选集内（Reasoner 必须返回 Provider 产出的原实例）")
	Log.assert_crash(not result.reason_key.is_empty(),
		"DecisionPipeline", "reason_key 为空（违反可解释性合同）")
	return DecisionOutcome.selected(result)


## 只读合同的机械检查（hash 0 = 子类未实现 content_hash，跳过）。
static func _check_readonly(snapshot: DecisionSnapshot, hash_before: int) -> void:
	if hash_before != 0:
		Log.assert_crash(snapshot.content_hash() == hash_before,
			"DecisionPipeline", "snapshot 在决策期间被修改（违反只读合同）")
