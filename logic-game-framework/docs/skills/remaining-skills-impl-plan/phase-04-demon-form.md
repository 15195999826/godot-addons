# 4 · Demon Form #15

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 上一阶段：[phase-03-stance.md](phase-03-stance.md)
> 下一阶段：[phase-05-summon-totem-spike.md](phase-05-summon-totem-spike.md)


**设计卡**：passive，每 3s 永久 +2 atk，无上限。

## 4.1 调研结论（关键澄清）

设计卡 §9「方案 B：Resolver 读 stacks」是**过时伪码**，但“直接在 tick action 里 `raw.add_modifier()`”也不是最终模型：它会绕过 Ability/Component 语义，渲染层也无法把成长状态解释成一个可展示的 buff/passive。Demon Form 应建模为单个 passive Ability：

- Ability 自身持有 stacks，表示已成长次数，也是渲染层显示数字。
- `StatModifierComponent` 负责提供 `atk +2 * stacks` 的属性加成。
- periodic tick action 只负责 `ability.add_stacks(1)`、emit `AbilityStacksChanged`、emit `stageCue(demon_form_pulse)`。
- 属性同步由补完后的 `StatModifierConfig.scale_by_stacks()` / `AbilityComponent.on_stacks_changed(...)` 自动完成。

因此本节需要先补完 `StatModifierComponent.scale_by_stacks` 的半成品能力，而不是为 Demon Form 新增专用属性修改逻辑。

按 §0.0 Action 分层合同，Demon Form 不新增 public `DemonFormTickAction`。tick 过程是 `passive_demon_form` 私有 routine，写成 `demon_form.gd` 内嵌 `_DemonFormTickAction extends Action.SkillLocalAction`。

## 4.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `stdlib/components/stat_modifier_config.gd` | 改：新增 `.scale_by_stacks()` 配置项 |
| `stdlib/components/stat_modifier_component.gd` | 改：`on_apply` / `on_stacks_changed` 按 stacks 同步 modifier value |
| `core/abilities/core/ability_component.gd` | 改：新增 `on_stacks_changed(context, old, new)` hook |
| `core/abilities/core/ability.gd` | 改：`add_stacks/remove_stacks/set_stacks` 在 stacks 真实变化后触发 component hook |
| `tests/stdlib/components/stat_modifier_component_test.gd` 或现有 stat modifier 测试 | 改/新建：验证 scale-by-stacks 初始值、add/remove/set stacks 后 update_modifier |
| `logic/skills/demon_form.gd` | 新建：passive config + `_DemonFormTickAction` SkillLocalAction |
| `logic/skills/all_skills.gd` | 改(+1 passive，带 tick timeline) |
| `frontend/visualizers/buff_visualizer.gd` | 改：`BUFF_REGISTRY` 注册 `passive_demon_form` |
| `frontend/visualizers/stage_cue_visualizer.gd` 或新增 self-vfx visualizer | 改/新建：支持 `demon_form_pulse` 周身特效 |
| `logic/scenario/skill_scenario_harness.gd` + `tests/battle/skill_scenarios/scenario_assert_context.gd` | 改：新增 final actor attribute snapshot / `final_actor_attribute(actor_id, attr_id)`，用于直接断言 atk |
| `tests/battle/skill_scenarios/demon_form_scenario.gd` | 新建 |
| `tests/frontend/...` | 新建/改：验证 Demon Form tick 产生周身特效 action |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 4.3 数值常量表

| 常量 | 值 |
|---|---|
| CONFIG_ID | `passive_demon_form` |
| TICK_TIMELINE_ID | `passive_demon_form_tick` |
| TICK_INTERVAL_MS | `3000.0` |
| ATK_PER_STACK | `2.0`（ADD_BASE atk，最终值 = stacks × 2） |
| 上限 | 无 |
| 挂载方式 | passive（scenario 用 `get_passives()`；demo 可绑某职业，评审定） |

## 4.4 代码骨架

`demon_form.gd` 内嵌 SkillLocalAction。tick action 不直接写属性，只增加 stacks；属性更新由 `StatModifierComponent.scale_by_stacks` 响应 stacks 变化完成：
```gdscript
class_name HexBattleDemonForm
const CONFIG_ID := "passive_demon_form"
const TICK_TIMELINE_ID := "passive_demon_form_tick"
const CUE_DEMON_FORM_PULSE := "demon_form_pulse"
const TICK_INTERVAL_MS := 3000.0
const ATK_PER_STACK := 2.0

class _DemonFormTickAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), CONFIG_ID)
		type = "demon_form_tick"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if ability == null or ability.is_expired():
			return ActionResult.create_success_result([], {})
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var actor := battle.get_character_actor(ability.owner_actor_id) if battle != null else null
		if actor == null or actor.is_dead():
			return ActionResult.create_success_result([], {})

		var stacks_before := ability.get_stacks()
		ability.add_stacks(1)
		var stacks_after := ability.get_stacks()
		ctx.event_collector.push(GameEvent.AbilityStacksChanged.create(
			ability.owner_actor_id, ability.id, ability.config_id, stacks_before, stacks_after).to_dict())
		ctx.event_collector.push(GameEvent.StageCue.create(
			ability.owner_actor_id,
			[ability.owner_actor_id],
			CUE_DEMON_FORM_PULSE,
			{ "stacks": stacks_after }
		).to_dict())
		return ActionResult.create_success_result([], { "demon_stacks": stacks_after })

static var DEMON_FORM_TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("恶魔形态")
	.description("每 3 秒永久 +2 攻击力，无上限")
	.ability_tags(["passive", "buff", "positive"])
	.stacks(0, 999999, Ability.OVERFLOW_CAP)
	.component_config(StatModifierConfig.builder()
		.modifier(HexBattleCharacterAttributeSet.atk_attribute, AttributeModifier.Type.ADD_BASE, ATK_PER_STACK)
		.scale_by_stacks()
		.build())
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_end([_DemonFormTickAction.new()])
		.build())
	.build())
```
`all_skills.gd`：`arr.append(_Entry.new(HexBattleDemonForm.ABILITY, [HexBattleDemonForm.DEMON_FORM_TICK_TIMELINE]))`

## 4.5 scenario

caster 挂 Demon Form passive（`get_passives`），无敌人或弱敌防早死，跑足 ~10s（max_ticks 调够）。先补 scenario attribute snapshot：harness 在 `GameWorld.destroy` 前记录每个 final actor 的关键属性，`ScenarioAssertContext.final_actor_attribute(actor_id, "atk")` 可直接读取。断言：caster `atk` 终值 = 初始 atk + floor(经过 ms / 3000) × 2；`passive_demon_form` 的 stacks 与 tick 次数一致；`AbilityStacksChanged` 事件数与 tick 次数一致；每次 tick 产生一个 `stageCue(demon_form_pulse)`。

说明：不要把“打不死的木桩，看伤害台阶”作为主断言。那是没有属性快照时的临时兜底，覆盖面差且受 crit / damage modifier 干扰；Demon Form 是补齐 scenario 属性断言能力的合适时机。

## 4.6 新机制清单

技能自身无专用新机制，但需要补完一个已有半成品基础能力：`StatModifierConfig.scale_by_stacks()`。这是通用能力，不属于 Demon Form 专用 Action/Component。

实现合同：
- `scale_by_stacks` 是 `StatModifierConfig` 配置项，不再是外部直接调用的 component 方法。
- `AbilityComponent` 新增 `on_stacks_changed(context, old_stacks, new_stacks)` 默认 no-op。
- `Ability.add_stacks/remove_stacks/set_stacks` 在 stacks 真实变化后同步触发 component hook。
- `StatModifierComponent` 若启用 `scale_by_stacks`，`on_apply` 初始 modifier value = `config.value * ability.stacks`；`on_stacks_changed` 通过 `RawAttributeSet.update_modifier(modifier.id, config.value * new_stacks)` 原子更新已添加 modifier。
- `AbilityStacksChanged` 事件仍由业务 action 主动 emit，不放进 `Ability.add_stacks()` 自动广播。
- `RawAttributeSet.update_modifier(modifier.id, new_value)` 已存在，优先使用原子更新；不要 fallback 成 remove+add，避免 modifier breakdown 闪烁和 dirty 两次。
- `on_stacks_changed` 不允许再调用 `add_stacks/remove_stacks/set_stacks`。实现上可在 Ability 内加 `_notifying_stacks_changed` reentrance guard，递归时 `Log.assert_crash`，避免 hook 触发 hook 的隐性死循环。

边界：本机制只表达 Ability stacks → modifier value；属性 A → 属性 B 的动态依赖继续使用 `DynamicStatModifierComponentConfig`。

## 4.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | **必接 +1**：`passive_demon_form` short "D" 暗红 `Color(0.6,0.1,0.1)`，PrimarySource.STACKS（显示叠层数=已 tick 次数） |
| StageCue / self VFX | **必接 +1**：每次 tick 由 `_DemonFormTickAction` push `stageCue`，`cue_id="demon_form_pulse"`，target 为 caster 自己，params 带 `{ "stacks": stacks_after }` |
| 周身特效表现 | caster 周身暗红 pulse / aura burst，短时长，不位移、不需要目标，不影响 timeline 逻辑 |
| default_registry | 若新增独立 visualizer，必须注册；若扩展 `StageCueVisualizer`，直接在 registry 既有注册链生效 |
| projectile | N/A |

说明：周身特效是 presentation concern，但触发时机必须来自逻辑 tick 事件流，保证 replay 中每次 Demon Form 成长都能复现同一特效。不要从前端单纯观察 buff primary 数字变化后自行猜测播放；应消费 `stageCue(demon_form_pulse)` 或等价的显式 visual event。

> **评审意见**：已批准。Demon Form 从“tick 直接 add modifier / 多个隐藏 buff”收敛为“单 passive Ability + `StatModifierConfig.scale_by_stacks()`”。先补完 stack-scaled StatModifier 基础设施：`scale_by_stacks` 作为 config 项，`AbilityComponent.on_stacks_changed` 作为同步 hook，`StatModifierComponent` 用 `RawAttributeSet.update_modifier()` 原子更新已添加 modifier。Demon tick action 只递增 stacks、发 `AbilityStacksChanged`、发 `stageCue(demon_form_pulse)`；前端显示 `D + stacks` 并播放周身暗红 pulse。
