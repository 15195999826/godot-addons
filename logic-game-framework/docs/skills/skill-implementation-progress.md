# 技能实现进度追踪

> 实施 [`.lomo-team/reference/inkmon-skill-design.md`](../../.lomo-team/reference/inkmon-skill-design.md) 16 个示范技能的进度快照。
> 每完成一个技能就更新本文档。配合 `lgf-new-logic-skill` skill 使用 —— 实现新技能前先读这里的「pattern 速查」找最近的参考实现。

最后更新：2026-04-25

---

## 📊 总览

| Tier | 进度 | 说明 |
|---|---|---|
| Tier 1 — MVP | 🟡 3 / 6 | 核心 pattern 验证 |
| Tier 2 — 中级 | 🟡 4 / 6 | 多原语组合 |
| Tier 3 — 高级 | 🟡 1 / 4 | 跨系统 |
| **合计** | **8 / 16** | |

**当前焦点** ：暂无；上一个落地的是 Ward (V1 护盾系统，2026-04-25)。
**下一个建议**：Tier 1 剩 Knockback Punch / Expose / Execute —— 优先把 Tier 1 补齐，再继续 Tier 2/3。

---

## 🎯 Design 文档 16 技能映射

### Tier 1 — MVP

| # | 设计名 | 状态 | 落地名 | 主要文件 | scenario 测试 |
|---|---|---|---|---|---|
| 1 | Strike | 🔵 已落地 | strike | `skills/strike.gd` | `strike_scenario.gd` |
| 2 | Poison | 🔵 已落地 | poison | `skills/poison.gd` + `buffs/poison_buff.gd` + `actions/poison_tick_action.gd` | `poison_scenario.gd` |
| 3 | Ward | 🔵 V1 已落地 | ward | `skills/ward.gd` + `buffs/ward_buff.gd` + `components/shield_component.gd` + `utils/hex_battle_shield_resolver.gd` + `actions/apply_shield_action.gd` | `shield_basic_absorb` / `shield_full_absorb_no_thorns` / `shield_priority_order` |
| 4 | Knockback Punch | ⚫ 未做 | — | — | — |
| 5 | Expose | ⚫ 未做 | — | — | — |
| 6 | Execute | ⚫ 未做 | — | — | — |

### Tier 2 — 中级

| # | 设计名 | 状态 | 落地名 | 主要文件 | scenario 测试 |
|---|---|---|---|---|---|
| 7 | Fireball | 🔵 已落地 | fireball | `skills/fireball.gd`（投射物形态） | `fireball_scenario.gd` |
| 8 | Decimating Smash | 🔵 已落地 | crushing_blow | `skills/crushing_blow.gd`（蓄力 / Timeline 多 keyframe） | `crushing_blow_scenario.gd` |
| 9 | Chain Lightning | ⚫ 未做 | — | — | — |
| 10 | Thorns | 🔵 已落地 | thorn | `skills/thorn.gd` + `actions/reflect_damage_action.gd` | `thorn_scenario.gd` |
| 11 | Mend | 🔵 已落地 | holy_heal | `skills/holy_heal.gd` + `actions/heal_action.gd` | `holy_heal_scenario.gd` |
| 12 | Shadow Step | ⚫ 未做 | — | — | — |

### Tier 3 — 高级

| # | 设计名 | 状态 | 落地名 | 主要文件 | scenario 测试 |
|---|---|---|---|---|---|
| 13 | Deathrattle: Explode | 🔵 已落地 | deathrattle_aoe | `skills/deathrattle_aoe.gd` | `deathrattle_aoe_scenario.gd` |
| 14 | Stance: Wrath/Calm | ⚫ 未做 | — | — | — |
| 15 | Demon Form | ⚫ 未做 | — | — | — |
| 16 | Summon Totem | ⚫ 未做 | — | — | — |

状态 emoji：🔵 已落地 · 🟡 实现中 · 🟠 已设计未实现 · ⚫ 未做

---

## 🧩 已落地但**不在** 16 张设计卡里的技能

设计文档之外、项目本身需要或作为 pattern 验证添加的：

| 落地名 | 用途 | 主要文件 |
|---|---|---|
| swift_strike | Strike 多段攻击变体（三连击），验证 Timeline 多 keyframe 在普攻形态下的用法 | `skills/swift_strike.gd` + `swift_strike_scenario.gd` |
| precise_shot | Strike 远程变体 + 投射物（追踪型）pattern | `skills/precise_shot.gd` + `precise_shot_scenario.gd` |
| move | 战术移动（不属于"技能"语义，是单位基础行动） | `skills/move.gd` + `actions/{start_move,apply_move}_action.gd` |
| vigor / vitality | passive 属性互相 scaling，**不是**机制示范，是验证 `AttributeSet` 循环依赖收敛机制的测试桩 | `skills/vigor.gd` / `skills/vitality.gd` |
| inspire_buff | 增益 buff 模板（与 design 11 Mend 配套用法） | `buffs/inspire_buff.gd` + `actions/apply_buff_action.gd` |
| cooldown_system | 技能冷却的项目层规则 | `skills/cooldown_system.gd` |
| skill_helpers | 技能间共享的工具函数 | `skills/skill_helpers.gd` |

> **重要**：Vigor / Vitality 不是技能模板，是 LGF 框架自我测试用的属性循环依赖对照例，**不要拿来当 pattern 模仿**。

---

## 🔍 Pattern 速查（实现新技能前先看这里）

按 design 文档的"想要的效果 → LGF 原语"再细化一层，加上"看哪个落地实例"。

| 想做什么 | 看哪个已落地技能 | 关键看点 |
|---|---|---|
| 一次性近战伤害 | strike | 最简 Action + DamageEvent push |
| 多段近战 / 三连击 | swift_strike | Timeline 多 keyframe 顺序 |
| 远程 + 投射物（追踪型） | precise_shot / fireball | projectile system + projectileHit 事件二阶 timeline |
| AoE 魔法 | fireball | 投射物落点 + 多目标 push |
| 蓄力 / 多阶段 | crushing_blow | Timeline START → WINDUP → HIT → END |
| DOT（中毒/燃烧/流血） | poison | Timeline periodic + buff ability + tick action 状态走 buff |
| 拦截伤害 / 减伤 | ward | **不走** PreEventConfig，走项目层 ShieldComponent + ShieldResolver；详见 [shield-system.md](shield-system.md) |
| 反伤被动 | thorn | PostEvent handler + actual_life_damage > 0 过滤 + 递归防护 |
| 治疗友军 | holy_heal | HealAction + 友方 selector |
| 增益 buff（攻击力 / 暴击等） | inspire_buff | apply_buff_action + AttributeModifierComponent |
| On Death 反应 | deathrattle_aoe | PostEvent on death event + 死亡 actor 上下文可用 |
| 移动 / 寻路 | move | start_move / apply_move 两阶段 action |

### 还没有落地参考的 pattern（做的时候记得回来填）

| 想做什么 | design 对应技能 | 备注 |
|---|---|---|
| hex 推 / 拉 / 位移 | Knockback Punch (#4) | UGridMap 方向计算 + 碰撞额外伤害 |
| 易伤 / 增伤 debuff | Expose (#5) | 对比 Poison：不直接扣血而是改受伤 |
| 条件分支伤害 / 斩杀 | Execute (#6) | Condition + 分支 Action |
| 链锁 / 跳目标 | Chain Lightning (#9) | 动态目标选择 + visited 用 local var |
| 瞬移突袭 | Shadow Step (#12) | 坐标计算 + 失败容错 |
| 姿态切换 | Stance (#14) | Ability 动态 add/remove + AttributeModifier |
| 永久叠 modifier | Demon Form (#15) | tag stacks 无上限 + Resolver 动态读 |
| 召唤 Actor | Summon Totem (#16) | add_actor + _on_id_assigned + tower_attribute_set |

---

## 🛣️ 偏离 design 文档的地方（重要）

design 文档写的时候 LGF 框架还在演进，落地时部分 pattern 调整了。**模仿时以下面"实际落地"为准，不要照搬 design 文档**：

| 项 | design 文档怎么写的 | 实际落地 | 原因 |
|---|---|---|---|
| 护盾（Ward） | `PreEventConfig` handler + `tag_container.get_stacks("ward")` 存盾值 | 项目层独立 `ShieldComponent` + `ShieldResolver`，**完全不走** PreEventConfig | 见 [shield-system.md 设计决策记录](shield-system.md#-设计决策记录)：PreEvent 顺序不可控、无消耗记录通道、无法表达破裂触发 |
| Poison 的 stacks 状态 | `tag_container` | `poison_buff` ability 自己持状态（buff component 持有可变状态符合 LGF 范式） | LGF 后续明确 buff/component 可有状态，AbilitySet 不再用作通用状态袋 |
| 蓄力技能（Decimating Smash） | 落地名 `decimating_smash` | 实际叫 `crushing_blow` | 命名调整 |
| Mend | 落地名 `mend` | 实际叫 `holy_heal` | 命名调整 |
| Thorns | 落地名 `thorns` | 实际叫 `thorn`（单数） | 命名调整 + reflect_damage_action 抽出复用 |
| Strike 变体 | "远程版 / 多段攻击 / 武器系数"列为变体方向 | swift_strike / precise_shot 已作为独立技能落地 | 提前实现以验证 projectile / multi-keyframe pattern |

---

## 📌 阶段标记（按 design 文档第八节 roadmap）

- [x] **阶段 1** — 核心 pattern（Strike / Poison / Ward）✅
- [ ] **阶段 2** — 机制词典扩展（Expose / Knockback / Execute / Fireball）—— Fireball 已做，剩 3 个
- [ ] **阶段 3** — 复杂组合（Decimating Smash / Thorns / Chain Lightning / Mend）—— Decimating ≈ Crushing Blow / Thorns / Mend ≈ Holy Heal 已做，剩 Chain Lightning
- [ ] **阶段 4** — 框架深度（Shadow Step / Deathrattle / Stance / Demon Form / Summon Totem）—— Deathrattle 已做，剩 4 个

---

## 🔄 维护约定

每完成一个技能：
1. 更新对应行的「状态」「落地名」「主要文件」「scenario 测试」
2. 在 **Pattern 速查** 表里加 / 改对应行（如果它代表新 pattern）
3. 如果实现偏离了 design 文档的 LGF 拆解，加一行到「偏离 design 文档的地方」
4. 更新顶部「最后更新」日期
5. 更新「当前焦点」「下一个建议」

每次开始新技能前：
1. 读「Pattern 速查」找最近的参考
2. 读对应已落地技能的 .gd 文件 + scenario
3. 读「偏离 design 文档的地方」确认现状
4. 再去看 design 文档第五/六/七节的设计卡

---

## 📚 相关文档

- 设计输入：[`.lomo-team/reference/inkmon-skill-design.md`](../../.lomo-team/reference/inkmon-skill-design.md)
- 护盾系统：[shield-system.md](shield-system.md)
- 伤害管线：[damage-pipeline.md](damage-pipeline.md)
- LGF 编码规范：`.claude/skills/enforcing-lgf/`
- 新技能落地工作流：`lgf-new-logic-skill` skill
