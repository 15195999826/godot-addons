## 技能 Timeline 定义
##
## Timeline 描述技能执行的时间轴，定义各个动作点（Tag）的时间。
## 使用 TimelineTags 常量定义 tag 名称，避免硬编码字符串。
class_name HexBattleSkillTimelines


# ========== Timeline ID 常量 ==========
## 使用类属性风格，支持 IDE 自动补全
class TIMELINE_ID:
	const MOVE := "action_move"
	const SLASH := "skill_slash"
	const PRECISE_SHOT := "skill_precise_shot"
	const PRECISE_SHOT_HIT := "skill_precise_shot_hit"  # 投射物命中响应
	const FIREBALL := "skill_fireball"
	const FIREBALL_HIT := "skill_fireball_hit"  # 投射物命中响应
	const CRUSHING_BLOW := "skill_crushing_blow"
	const SWIFT_STRIKE := "skill_swift_strike"
	const HOLY_HEAL := "skill_holy_heal"


# ========== Timeline 定义 ==========

## 移动 Timeline（两阶段）
## - 0ms: 开始移动，预订目标格子（激活时立即触发）
## - 100ms: 应用移动，实际到达目标格子
## - 200ms: 结束
static var MOVE_TIMELINE := TimelineData.new(
	TIMELINE_ID.MOVE,
	200.0,
	{
		TimelineTags.START: 0.0,      # 0ms 时执行 StartMoveAction（立即预订）
		TimelineTags.EXECUTE: 100.0,  # 100ms 时执行 ApplyMoveAction（实际移动）
		TimelineTags.END: 200.0,
	}
)


## 横扫斩 Timeline
## - 近战攻击，0ms 发送动画提示，0.3s 时命中
static var SLASH_TIMELINE := TimelineData.new(
	TIMELINE_ID.SLASH,
	500.0,
	{
		TimelineTags.START: 0.0,  # 0ms 发送 stageCue 给表演层
		TimelineTags.HIT: 300.0,  # 300ms 时造成伤害
		TimelineTags.END: 500.0,
	}
)


## 精准射击 Timeline（发射阶段）
## - 远程攻击，0ms 发送动画提示，0.3s 发射箭矢
## - 注意：伤害由投射物命中事件触发，不在此 Timeline 中
static var PRECISE_SHOT_TIMELINE := TimelineData.new(
	TIMELINE_ID.PRECISE_SHOT,
	500.0,  # 发射后 Timeline 结束，投射物继续飞行
	{
		TimelineTags.START: 0.0,     # 0ms 发送 stageCue 给表演层
		TimelineTags.LAUNCH: 300.0,  # 300ms 时发射箭矢
		TimelineTags.END: 500.0,
	}
)


## 精准射击命中 Timeline（投射物命中响应）
## - 投射物命中后立即触发伤害
static var PRECISE_SHOT_HIT_TIMELINE := TimelineData.new(
	TIMELINE_ID.PRECISE_SHOT_HIT,
	100.0,  # 快速执行
	{
		TimelineTags.HIT: 0.0,   # 立即造成伤害
		TimelineTags.END: 100.0,
	}
)


## 火球术 Timeline（发射阶段）
## - 远程魔法，0ms 发送动画提示，0.2s 施法，0.4s 发射火球
## - 注意：伤害由投射物命中事件触发，不在此 Timeline 中
static var FIREBALL_TIMELINE := TimelineData.new(
	TIMELINE_ID.FIREBALL,
	600.0,  # 发射后 Timeline 结束，投射物继续飞行
	{
		TimelineTags.START: 0.0,     # 0ms 发送 stageCue 给表演层
		TimelineTags.CAST: 200.0,    # 施法动作
		TimelineTags.LAUNCH: 400.0,  # 400ms 时发射火球
		TimelineTags.END: 600.0,
	}
)


## 火球术命中 Timeline（投射物命中响应）
## - 投射物命中后立即触发伤害
static var FIREBALL_HIT_TIMELINE := TimelineData.new(
	TIMELINE_ID.FIREBALL_HIT,
	100.0,  # 快速执行
	{
		TimelineTags.HIT: 0.0,   # 立即造成伤害
		TimelineTags.END: 100.0,
	}
)


## 毁灭重击 Timeline
## - 近战重击，0ms 发送动画提示，0.3s 蓄力，0.6s 时命中
static var CRUSHING_BLOW_TIMELINE := TimelineData.new(
	TIMELINE_ID.CRUSHING_BLOW,
	1000.0,
	{
		TimelineTags.START: 0.0,     # 0ms 发送 stageCue 给表演层
		TimelineTags.WINDUP: 300.0,  # 蓄力
		TimelineTags.HIT: 600.0,     # 命中
		TimelineTags.END: 1000.0,
	}
)


## 疾风连刺 Timeline
## - 快速近战，0ms 发送动画提示，多段伤害
static var SWIFT_STRIKE_TIMELINE := TimelineData.new(
	TIMELINE_ID.SWIFT_STRIKE,
	400.0,
	{
		TimelineTags.START: 0.0,   # 0ms 发送 stageCue 给表演层
		TimelineTags.HIT1: 100.0,  # 第一击
		TimelineTags.HIT2: 200.0,  # 第二击
		TimelineTags.HIT3: 300.0,  # 第三击
		TimelineTags.END: 400.0,
	}
)


## 圣光治愈 Timeline
## - 远程治疗，0ms 发送动画提示，0.4s 时生效
static var HOLY_HEAL_TIMELINE := TimelineData.new(
	TIMELINE_ID.HOLY_HEAL,
	600.0,
	{
		TimelineTags.START: 0.0,   # 0ms 发送 stageCue 给表演层
		TimelineTags.HEAL: 400.0,  # 治疗生效
		TimelineTags.END: 600.0,
	}
)


## 所有 Timeline
static func get_all_timelines() -> Array[TimelineData]:
	return [
		MOVE_TIMELINE,
		SLASH_TIMELINE,
		PRECISE_SHOT_TIMELINE,
		PRECISE_SHOT_HIT_TIMELINE,
		FIREBALL_TIMELINE,
		FIREBALL_HIT_TIMELINE,
		CRUSHING_BLOW_TIMELINE,
		SWIFT_STRIKE_TIMELINE,
		HOLY_HEAL_TIMELINE,
	]


## 根据 ID 获取 Timeline
static func get_timeline(timeline_id: String) -> TimelineData:
	for timeline in get_all_timelines():
		if timeline.id == timeline_id:
			return timeline
	return null

