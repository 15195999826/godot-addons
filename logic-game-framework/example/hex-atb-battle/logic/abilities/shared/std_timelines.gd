## HexBattleStdTimelines - 标准节奏 timeline 共享库
##
## 收口规则(docs/plan/hex-skill-applayer-convergence-plan.md P4): 「500ms/HIT@300」
## 这类标准节奏是全局约定而非单技能个性, 收口为共享 TimelineData 实例; 有真实节奏
## 个性的技能(蓄力 / 多段 / 两阶段位移 / 召唤 / buff tick / precise_shot 快弓)保留自定义。
##
## 共享安全前提(收敛计划 P6 已核实): TimelineData 是纯数据资产(构造后无写点),
## 执行游标全在 AbilityExecutionInstance(每次施法新实例); 并发执行本就共享 registry
## 里同一引用。注册端双闸: registry 三态注册(同 id 异引用 assert) + tags.make_read_only()。
##
## replay 影响: 录像 timeline_id 字段显示 std_* 而非技能名; 定位技能用事件里的
## ability config_id。
class_name HexBattleStdTimelines


## 标准近战/单体施加节奏: HIT@300 / END@500(原 Strike 节奏, 19 个技能对齐)
static var MELEE_500 := TimelineData.new("std_melee_500", 500.0, {
	TimelineTags.HIT: 300.0,
	TimelineTags.END: 500.0,
})


## 标准投射物 cast 节奏: CAST@200 / LAUNCH@400 / END@600(fireball / chain_lightning)
static var CAST_LAUNCH_600 := TimelineData.new("std_cast_launch_600", 600.0, {
	TimelineTags.CAST: 200.0,
	TimelineTags.LAUNCH: 400.0,
	TimelineTags.END: 600.0,
})


## 标准投射物命中响应: END@100(投射物技能的 hit timeline, 命中即结算)
static var HIT_RESPONSE_100 := TimelineData.new("std_hit_response_100", 100.0, {
	TimelineTags.END: 100.0,
})
