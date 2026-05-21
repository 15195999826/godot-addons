# 剩余 5 技能可执行级实施方案（Phase 索引）

> 配套 [`skill-implementation-progress.md`](skill-implementation-progress.md) 与 [`.lomo-team/reference/inkmon-skill-design.md`](../../.lomo-team/reference/inkmon-skill-design.md)。
> 本文 = taxonomy 16 技能剩余 5 个的 **Phase 开发入口**；各 Phase 文档保留可执行级 align 方案正文。
> 创建：2026-05-18 · Opus 4.7；拆分：2026-05-20 · Codex

> 这份文档是开发入口。原 1300+ 行实施方案已经拆到 `remaining-skills-impl-plan/phase-*.md`，按 Phase 打开对应文档开发。

## Phase 顺序

| Phase | 文档 | 开发内容 | 状态 |
|---|---|---|---|
| 00 | [`phase-00-infrastructure.md`](remaining-skills-impl-plan/phase-00-infrastructure.md) | Action 分层/validator、LooseTagAction、TagComponentConfig、FlowAction、NoInstance lifecycle、DamageAction no-op、stack modifier、facing、execution_state | ✅ 已批准，先落 |
| 01 | [`phase-01-chain-lightning.md`](remaining-skills-impl-plan/phase-01-chain-lightning.md) | Chain Lightning：projectile `customData` 透传 + on-hit 链式发射 | ✅ 已批准 |
| 02 | [`phase-02-shadow-step.md`](remaining-skills-impl-plan/phase-02-shadow-step.md) | Shadow Step：logic-facing + teleport_success + delayed damage | ✅ 已批准 |
| 03 | [`phase-03-stance.md`](remaining-skills-impl-plan/phase-03-stance.md) | Stance：单 Ability + loose stance tags + NoInstance lifecycle cleanup | ✅ 已批准 |
| 04 | [`phase-04-demon-form.md`](remaining-skills-impl-plan/phase-04-demon-form.md) | Demon Form：stack-scaled StatModifier + scenario attribute snapshot + pulse VFX | ✅ 已批准 |
| 05 | [`phase-05-summon-totem-spike.md`](remaining-skills-impl-plan/phase-05-summon-totem-spike.md) | Summon Totem：spawn/remove/replay/TTL TDD spike | ✅ spike closeout；正式 impl 另起目标 |

状态：⬜ 待评审 · 🟡 需改(见该节末「评审意见」) · ✅ 已批准可落码

## 内容保真说明

- Phase 文档正文由拆分前长文档按章节切出；除每个 Phase 顶部新增的返回/上一阶段/下一阶段导航外，不主动改写各章节正文。
- 本入口索引不是原文完整副本：它保留全局决策、Phase 顺序和总检查，详细方案以各 Phase 文档为准。

## 开发建议

1. 先做 Phase 00，并按其中 §0.7 的内部顺序拆小提交。
2. Phase 01 可以在 `FlowAction.if_` 与 projectile `customData` 透传完成后先落。
3. Phase 02 需要 Phase 00 的 facing、execution-local state、DamageAction no-op 全部可用。
4. Phase 03 需要 `LooseTagAction`、`FlowAction.if_`、`NoInstanceConfig` lifecycle actions。
5. Phase 04 需要 stack-scaled StatModifier 和 scenario attribute snapshot。
6. Phase 05 spike closeout 已完成；本轮不直接实现正式图腾技能，正式 impl 另起目标。

## 收敛的全局决策

| 项 | 结论 | 依据 |
|---|---|---|
| 实施顺序 | 基础设施（Phase 00 / §0.7 顺序）→ Chain → Shadow → Stance → Demon → Totem(spike/TDD) | Chain/Shadow/Stance/Demon 都依赖前置小机制；Totem 先 TDD spike 再定正式 impl |
| schema 倾向 | 优先复用；Chain 允许补 projectile `customData` 透传 + `FlowAction.if_`；Shadow 引入 CharacterActor logic-facing + execution-local state；不扩 core Timeline | Chain=projectileHit 链式触发；Shadow=ActorDisplacedEvent + facing state + teleport_success；DamageAction 统一过滤 dead/invalid target |
| facing 归属 | `facing_direction` 是 CharacterActor 运行时状态，不进 `RawAttributeSet`，不放 `HexBattleActor` 基类 | AttributeSet 是 float/modifier/breakdown 数值管线；EnvironmentActor 暂无朝向语义 |
| Demon Form 实现 | 单 passive Ability：`StatModifierConfig.scale_by_stacks()` + periodic tick 只递增 stacks | 补完既有 `StatModifierComponent.scale_by_stacks` 半成品；属性加成仍通过 Ability/Component 建模，渲染层显示同一 Ability stacks |
| Summon Totem | TDD spike 已验证框架原语；正式 impl 另起目标 | 战斗中途 add_actor / replay / manual remove / TimeDurationConfig→NoInstance.on_remove lifecycle 均已覆盖；behavior placeholder 不计入完成 |
| crit 建模 | 「+X%」用 damage resolver ×系数，**不**强设 is_critical | DamageAction 无强制 crit 入口；resolver 系数是既有 pattern |

## 落码前总检查

- [ ] 当前 Phase 文档的「评审意见」= ✅，或明确是 spike/TDD 门
- [ ] submodule 内实现 → commit；外层 bump 指针（分阶段即提）
- [ ] `smoke_skill_scenarios` 全绿；PreEvent/damage 类 **重跑 5 次**稳定
- [ ] 表演层逐项勾完或显式声明跳过
- [ ] 回写 `skill-implementation-progress.md`（状态/落地名/文件/scenario/Pattern 速查/偏离记录/日期/下一个建议）
- [ ] `enforcing-lgf` Validation Checklist 过
