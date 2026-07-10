## Surge Buff - 自施"涌动"buff(立即生效语义)
##
## stacks=3,挂上立即触发首 tick(3→2),之后每 2s 再 tick 一次,归零自动 expire。
## 用 GRANTED_SELF + on_timeline_start:挂上瞬间 fire 第一次 tick,跟 grant 进
## 同一个 collector frame。Poison 之前踩过同样坑,后被绕开;Surge 故意保留这个
## 模式来验证 frontend BuffVisualizer 在同帧 ADD+UPDATE 下的 stacks 显示序列。
##
## 此 buff 没有副作用 damage / heal — 计时器作用在 stacks 数字本身上。
class_name HexBattleSurgeBuff


const CONFIG_ID := "buff_surge"
const TICK_TIMELINE_ID := "buff_surge_tick"
const TICK_INTERVAL_MS := 2000.0
const DEFAULT_STACKS := 3
const MAX_STACKS := 999


static var SURGE_TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)


static var SURGE_BUFF := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("涌动")
	.description("挂上立即生效,3 stacks,每 2s 减 1")
	.ability_tags(["buff", "positive"])
	.stacks(DEFAULT_STACKS, MAX_STACKS, Ability.OVERFLOW_CAP)
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline(SURGE_TICK_TIMELINE)
		.on_timeline_start([HexBattleSurgeTickAction.new()])
		.build()
	)
	.build()
)
