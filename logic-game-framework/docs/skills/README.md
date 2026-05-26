# Skills & Systems Docs

inkmon 项目层的技能 / 战斗系统设计、完成记录和后续路线入口。

## 先看这里

| 你要做什么 | 入口 |
|---|---|
| 讨论后续技能 / 装备能力扩展 | [equipment-attack-effects-next-stage.md](equipment-attack-effects-next-stage.md) |
| 查已经落地了哪些技能和 pattern | [skill-implementation-progress.md](skill-implementation-progress.md) |
| 查 SkillPreview + ItemSystem 接入历史 | [skill-preview-item-system-plan.md](skill-preview-item-system-plan.md) |
| 查稳定系统参考 | [damage-pipeline.md](damage-pipeline.md), [shield-system.md](shield-system.md) |

## 信息架构

这里不维护一个巨型“已完成”正文。已完成内容只在 README 和进度文档里做短索引，细节继续留在原计划、progress、scenario 和 commit 里。

| 分类 | 用法 | 维护规则 |
|---|---|---|
| Current | 当前正准备讨论 / 开发的目标 | 只能有少数入口，避免并行焦点过多 |
| Completed | 已完成里程碑索引和 pattern 速查 | 只写摘要 + 链接，不复制长方案正文 |
| Future | 未来可能做、但还未拍板的 backlog | 写清 open question 和 non-goal，不提前落成实施方案 |
| Reference | 已稳定系统的事实文档 | 代码 contract 变化后同步更新 |

## Current

当前没有已确认的新开发 goal；下表只列最近可继续讨论的扩展入口。

| 文档 | 状态 | 内容 |
|---|---|---|
| [equipment-attack-effects-next-stage.md](equipment-attack-effects-next-stage.md) | 🟠 V2+ 扩展候选 | Phase G V1 已落地；后续只保留 on-hit 样例、DevAgent/replay 可观测字段、多攻击特效策略等扩展入口 |

## Completed

| 文档 | 状态 | 内容 |
|---|---|---|
| [skill-implementation-progress.md](skill-implementation-progress.md) | 🔵 已完成索引，持续维护 | 16 张设计卡 + Phase 2+ + 已落地 pattern 速查 |
| [remaining-skills-impl-plan.md](remaining-skills-impl-plan.md) | 🔵 历史 Phase 索引 | Chain / Shadow Step / Stance / Demon Form / Summon Totem spike 的旧执行拆分 |
| [advanced-skills-impl-plan.md](advanced-skills-impl-plan.md) | 🔵 历史规划归档 | Stun / Silence / Break / Fire Tile / Cleanse / Swap / Lifesteal / Line-Cone 的 Phase 2+ 设计来源 |
| [advanced-skills-next-batch.md](advanced-skills-next-batch.md) | 🔵 已完成批次归档 | `HexBattleGeneralPassive`、`attack_lifesteal_pct`、Cone AoE、SkillPreview debug area / facing 回归 |
| [skill-preview-item-system-plan.md](skill-preview-item-system-plan.md) | 🔵 已完成归档 | item-preview sandbox 到 SkillPreview Phase F 的 ItemSystem / inventory integration 设计记录 |
| [shield-system.md](shield-system.md) | 🔵 V1 已落地 | ShieldComponent + ShieldResolver + shield matrix |
| [damage-pipeline.md](damage-pipeline.md) | 🔵 已落地 | `apply_damage` 9 步流程和 damage event 字段语义 |

## Future

| 主题 | 现在状态 | 放在哪 |
|---|---|---|
| Equipment attack effects post-V1 | Phase G V1 已完成 equipment-granted passive + `PreBasicAttackEvent` + Daedalus-like critical strike；下一轮只讨论后置 on-hit / replay observability / 多来源策略 | [equipment-attack-effects-next-stage.md](equipment-attack-effects-next-stage.md) |
| Break post-V1 | accepted descope：late-grant passive、tick duration 短路、AbilityDisabled/Enabled GameEvent、serialize disabled sources | [skill-implementation-progress.md](skill-implementation-progress.md) |
| Fire Tile post-V1 | placement mode 字段、双线 tick 拆分等设计保留项 | [skill-implementation-progress.md](skill-implementation-progress.md) |
| 完整装备系统 | affix、durability、cooldown、grant/revoke item ability policy、多攻击特效 / 多暴击规则来源策略 | [equipment-attack-effects-next-stage.md](equipment-attack-effects-next-stage.md) |

## 文档约定

- 一文件聚焦一个主题，命名 kebab-case `<topic>.md`。
- 状态用 emoji 标识：🟡 当前 / 进行中，🔵 已落地 / 归档，🟠 未来规划，⚫ 废弃。
- Completed 只做短索引。如果某段 completed 内容开始变长，拆成 milestone archive，不要塞进一个总文档。
- 单技能的数值 / 行为细节优先写在技能 `.gd` 文件头部注释或 scenario 里。
- LGF 框架层架构推理放到 [`../design-notes/`](../design-notes/)。
