# Skills & Systems — 设计与规划文档

inkmon 项目层的**技能/战斗系统**设计与持续演进路线图。

## 这里放什么

- 系统/机制级的设计方案（护盾、状态、AI 行为树等）
- 项目层既有流程的事实记录（如伤害管线）
- 已实现/未实现 feature 状态
- V2/V3 路线图与优先级
- 设计决策记录（为什么这样选、为什么不那样）
- 已知限制与待拍板的边界 case

## 这里**不**放什么

- LGF 框架层的架构推理 → 去 [`addons/logic-game-framework/docs/design-notes/`](../../addons/logic-game-framework/docs/design-notes/)
- 单技能的数值/行为细节 → 写在技能 `.gd` 文件头部注释
- 已修复 bug 的 post-mortem → 走 LGF 的 `design-notes/` 或 commit message

## 文档约定

- 一文件聚焦一个主题，命名 kebab-case `<topic>.md`
- 状态用 emoji 标识：🟢 已设计 · 🟡 实现中 · 🔵 已落地 · 🟠 V2 规划中 · ⚫ 已废弃
- 当前不分子目录。文档总数增长到出现明显跨类（如网络同步 / AI 行为树）再考虑拆分

## 文档分类（描述性，不是目录）

| 类型 | 用途 | 长什么样 |
|---|---|---|
| **系统设计** | 单一 feature / 机制的设计、消耗顺序、叠加策略、设计决策 Q&A、V2+ 路线图 | `shield-system.md` |
| **流程参考** | 项目层既有流程的事实记录，描述"现在是怎么跑的"。新增插入式步骤时回来更新 | `damage-pipeline.md` |
| **进度追踪** | 多技能 / 多系统的实施快照，每完成一个就更新；与 `.lomo-team/reference/` 下的设计文档配套 | `skill-implementation-progress.md` |

新文档落到哪一类靠判断：
- 在描述一个 **可独立替换 / 配置 / 扩展的子系统** → 系统设计
- 在描述一个 **多个子系统共用的执行流程或骨架** → 流程参考

## 当前清单

| 文档 | 状态 | 类型 | 内容 |
|---|---|---|---|
| [damage-pipeline.md](damage-pipeline.md) | 🔵 已落地 | 流程参考 | `apply_damage` 9 步流程、damage event 字段语义、插入式步骤清单 |
| [shield-system.md](shield-system.md) | 🔵 V1 已落地 | 系统设计 | 护盾机制、消耗顺序、叠加策略、设计决策 |
| [skill-implementation-progress.md](skill-implementation-progress.md) | 🟡 持续更新 | 进度追踪 | 16 张技能设计卡的落地状态 + Pattern 速查 + 偏离 design 文档之处 |
