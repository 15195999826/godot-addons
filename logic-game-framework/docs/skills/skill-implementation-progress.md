# 技能实现进度追踪

> 实施 [`.lomo-team/reference/inkmon-skill-design.md`](../../.lomo-team/reference/inkmon-skill-design.md) 16 个示范技能的进度快照。
> 每完成一个技能就更新本文档。配合 `lgf-new-logic-skill` skill 使用 —— 实现新技能前先读这里的「pattern 速查」找最近的参考实现。

最后更新：2026-05-21

---

## 📊 总览

| Tier | 进度 | 说明 |
|---|---|---|
| Tier 1 — MVP | 🟢 6 / 6 | 核心 pattern 验证 |
| Tier 2 — 中级 | 🟢 6 / 6 | 多原语组合 |
| Tier 3 — 高级 | 🟡 3 / 4 (+1 spike) | 跨系统; Summon Totem spike closeout 完成, 路线 A 待正式 impl |
| **合计** | **15 / 16 (+1 spike)** | |

**当前焦点** ：暂无；remaining skills review closeout 已补 Chain Lightning frame metadata / caster-death regression、HexFacing 6 向覆盖、stack modifier notification、Action validator guardrail 与 Summon Totem spike 真实口径。
**下一个建议**：Summon Totem 正式 impl (per phase-05 §5.5 "待办") — `HexBattleSpawnActorAction` + 新 TOTEM character class + hex actor-level lifetime + summon_totem.gd + HexBattleTotemAttack(nearest enemy target selection)。Fire Tile / 地形伤害格排在它之后并复用同一个 spawn action 的 `OVERLAY` placement；正式做 Fire Tile 前补 `HexBattleActor.placement_mode` cleanup 与 all-`HexBattleActor` ability runtime tick。

---

## 🏗️ 基础设施 (非 16 技能项)

| 名称 | 状态 | 简述 | 主要文件 |
|---|---|---|---|
| 护盾系统 V1 | 🔵 已落地 | ShieldComponent + ShieldResolver + physical/magical/universal shield matrix, 不走 PreEventConfig | `components/shield_component.gd` + `utils/hex_battle_shield_resolver.gd` + `buffs/shield_buffs.gd` |
| EnvironmentActor 子系统 + AttributeSet 继承 (M1) | 🔵 已落地 | `HexBattleActor` 中间基类 / `Character` `Environment` 子类 / generator `_extends` 继承链 / StoneWall 起步 | `hex_battle_actor.gd` + `environment_actor.gd` + `environment/{stone_wall,collision_profile}.gd` + `attributes_config.gd` (含 `_extends`) + `attribute_set_generator_script.gd` |

---

## 🎯 Design 文档 16 技能映射

### Tier 1 — MVP

| # | 设计名 | 状态 | 落地名 | 主要文件 | scenario 测试 |
|---|---|---|---|---|---|
| 1 | Strike | 🔵 已落地 | strike | `skills/strike.gd` | `strike_scenario.gd` |
| 2 | Poison | 🔵 已落地 | poison | `skills/poison.gd` + `buffs/poison_buff.gd` + `actions/poison_tick_action.gd` | `poison_scenario.gd` |
| 3 | Ward | 🔵 V1 已落地 | ward | `skills/ward.gd` + `buffs/ward_buff.gd` + `buffs/shield_buffs.gd` + `components/shield_component.gd` + `utils/hex_battle_shield_resolver.gd` + `actions/apply_shield_action.gd` | `shield_basic_absorb` / `shield_full_absorb_no_thorns` / `shield_priority_order` / `shield_damage_type_matrix` |
| 4 | Knockback Punch | 🔵 已落地 | knockback_punch | `skills/knockback_punch.gd` + `actions/push_action.gd` + `events/battle_events.gd` (ActorDisplacedEvent + PushBlockedEvent) | `example/hex-atb-battle/tests/battle/smoke_knockback_punch.gd` (7 cases) |
| 5 | Expose | 🔵 已落地 | expose | `skills/expose.gd` + `buffs/expose_buff.gd` (PreEventConfig + TimeDurationConfig) | `expose_scenario.gd` |
| 6 | Execute | 🔵 已落地 | execute | `skills/execute.gd` + `utils/hex_battle_shield_resolver.gd` (sum_absorbable_capacity) + `visualizers/stage_cue_visualizer.gd` (execute_kill 特效) | `execute_scenario.gd` |

### Tier 2 — 中级

| # | 设计名 | 状态 | 落地名 | 主要文件 | scenario 测试 |
|---|---|---|---|---|---|
| 7 | Fireball | 🔵 已落地 | fireball | `skills/fireball.gd`（投射物形态） | `fireball_scenario.gd` |
| 8 | Decimating Smash | 🔵 已落地 | crushing_blow | `skills/crushing_blow.gd`（蓄力 / Timeline 多 keyframe） | `crushing_blow_scenario.gd` |
| 9 | Chain Lightning | 🔵 已落地 | chain_lightning | `skills/chain_lightning.gd` + `stdlib/systems/projectile_system.gd` (customData 透传) + `stdlib/actions/launch_projectile_action.gd` (customData) | `chain_lightning_scenario.gd` |
| 10 | Thorns | 🔵 已落地 | thorn | `skills/thorn.gd` + `actions/reflect_damage_action.gd` | `thorn_scenario.gd` |
| 11 | Mend | 🔵 已落地 | holy_heal | `skills/holy_heal.gd` + `actions/heal_action.gd` | `holy_heal_scenario.gd` |
| 12 | Shadow Step | 🔵 已落地 | shadow_step | `skills/shadow_step.gd` (内嵌 `_ShadowStepTeleportAction` SkillLocalAction) + `hex_facing.gd` (§0.3 facing) + `execution_context.gd` (§0.4 execution_state) | `shadow_step_scenario.gd` / `shadow_step_fallback_scenario.gd` / `shadow_step_blocked_scenario.gd` |

### Tier 3 — 高级

| # | 设计名 | 状态 | 落地名 | 主要文件 | scenario 测试 |
|---|---|---|---|---|---|
| 13 | Deathrattle: Explode | 🔵 已落地 | deathrattle_aoe | `skills/deathrattle_aoe.gd` | `deathrattle_aoe_scenario.gd` |
| 14 | Stance: Wrath/Calm | 🔵 已落地 | skill_stance | `skills/stance.gd` (单 Ability + Wrath/Calm loose tag + 2 PreEventConfig + §0.6 NoInstance lifecycle) | `stance_scenario.gd` |
| 15 | Demon Form | 🔵 已落地 | passive_demon_form | `skills/demon_form.gd` (passive + GRANTED_SELF periodic tick + 内嵌 `_DemonFormTickAction` SkillLocalAction) + §0.X `StatModifierConfig.scale_by_stacks()` | `demon_form_scenario.gd` |
| 16 | Summon Totem | 🟠 spike closeout 完成 / 路线 A 待 impl | (未) | (spike: `tests/battle/smoke_summon_spike.tscn` + `phase-05-summon-totem-spike.md` §5.5 结论) | — |

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
| 拦截伤害 / 减伤 | ward | **不走** PreEventConfig，走项目层 ShieldComponent + ShieldResolver；physical/magical/universal shield 由 `damage_types` 硬过滤；详见 [shield-system.md](shield-system.md) |
| 反伤被动 | thorn | PostEvent handler + actual_life_damage > 0 过滤 + 递归防护 |
| 治疗友军 | holy_heal | HealAction + 友方 selector |
| 增益 buff（攻击力 / 暴击等） | inspire_buff | apply_buff_action + AttributeModifierComponent |
| On Death 反应 | deathrattle_aoe | PostEvent on death event + 死亡 actor 上下文可用 |
| 移动 / 寻路 | move | start_move / apply_move 两阶段 action |
| forced displacement (击退/拉拽/推开) | knockback_punch | PushAction raycast N 格 + CollisionProfile 数据驱动结算 + ActorDisplacedEvent / PushBlockedEvent 拆事件;`distance` / `displacement_kind` 参数化让 pull / wind_torrent / N>1 直接复用 |
| 易伤 / 增伤 debuff(改受伤) | expose | PreEventConfig + Modification.multiply 在 pre_damage 阶段放大目标受伤;filter 仅"target == owner"维度;TimeDurationConfig 自动 expire;**LGF PreEvent modify_intent 第一个生产用例**(ward 已迁到 ShieldComponent) |

### Phase 00-04 落地的新 pattern (本轮加进 速查)

| 想做什么 | 看哪个已落地技能 | 关键看点 |
|---|---|---|
| 链锁 / 跳目标 (projectile customData 透传 + on_hit hook 链发) | chain_lightning (#9) | `ProjectileSystem._emit_hit_event` 透传 customData; `DamageAction.on_hit(FlowAction.if_(has_next, [LaunchProjectileAction(custom_data)]))`; visited_actor_ids / hit_index / chain_id 经 projectile customData 漂洗;hit filter 含 ability_instance_id 防同 caster 多 chain 污染 |
| 瞬移突袭 (前段状态影响后段) | shadow_step (#12) | §0.4 ExecutionContext.set/get_execution_state CAST 阶段写 → HIT 阶段读;§0.3 HexFacing.face_actor_toward 落地后 face target;落点优先级 [背→背左→背右→侧后左→侧后右→正面];6 邻格全失败 teleport_success=false 保持原位 |
| 姿态切换 (单 Ability + loose tag) | stance (#14) | §0.6 NoInstanceConfig lifecycle (on_apply 默认 Wrath / on_remove 清两 tag);§0.2 FlowAction.if_(has_wrath, [W→C], [C→W]) 主动切换;2 PreEventConfig (incoming/outgoing) 读 stance tag → Modification.multiply。**V1 受控合同**:同 actor 不允许多实例 Stance;scenario_harness._fire_action 复用 existing ability (find_ability_by_config_id) |
| 永久叠 modifier (无上限 passive periodic tick) | demon_form (#15) | §0.X StatModifierConfig.scale_by_stacks() + StatModifierComponent.on_stacks_changed 走 RawAttributeSet.update_modifier 原子更新;TriggerConfig.GRANTED_SELF + periodic loop timeline + 内嵌 SkillLocalAction 只递增 stacks。**scenario harness**: passive 永不自停, smoke runner timeout 仅警告不失败 |
| 召唤 Actor (路线 A spike 验证) | summon_totem (#16) spike | `instance.add_actor + grid.place_occupant` + ability_set 手动 tick + `HexWorldGameplayInstance.remove_actor` 清 actor/grid + `TimeDurationConfig → NoInstance.on_remove` lifecycle 自清;recorder.record_frame(flush()) 让 mid-battle abilityGranted 进 replay。Phase 5 behavior placeholder 不计入完成。**正式 impl 待办**(per phase-05 §5.5):`HexBattleSpawnActorAction` + 新 TOTEM character class + hex actor-level lifetime(15s) + summon_totem.gd + HexBattleTotemAttack(3s cadence, nearest enemy target selection)。正式 Totem 不再用 lifetime Ability；Fire Tile 排在 Totem 正式实现之后并复用同一个 spawn action；Fire Tile 还要求 `HexBattleActor.placement_mode` 区分 `OCCUPANT`/`OVERLAY` cleanup，并让 EnvironmentActor ability runtime 被正式 battle tick。Fire Tile damage source 是 Fire Tile actor 自己，高 HP，完整 damage pipeline/post-damage，creator 仅 metadata 追溯。 |

### 还没有落地参考的 pattern (16 设计卡之外的)

(暂空 — 16 个设计卡全部已 cover 或 spike 完成)

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
| Expose 范式 | 拆 `ExposeAbility` 主动 + `ExposePreEventAbility` 拦截器(基于 tag) | 合并为单 buff ability(主动 grant `HexBattleExposeBuff`,buff 自带 PreEventConfig + TimeDurationConfig) | 与 Poison 同样的范式迁移:tag-based state → buff component state(LGF 后续约定 buff 可有状态) |
| Expose `cue_id` | design 卡未指定 | 复用 `melee_slash` 而非新增 `debuff_glow` cue 类型 | 表演层接入清单原则(SKILL.md §7.3)— 优先复用现有 cue,无专属视觉资产时不编新名 |
| Buff `ability_tags` 全量 | 散乱描述性 tag(`debuff` / `dot` / `poison` / `shield` / `ward` / `surge` / `inspire`) | **统一 positive / negative 二分**:`["buff","positive"]` 或 `["buff","negative"]` | 用户反馈"原 tag 写得意义不明",2026-05-04 随 Expose 落地一起收敛 4 个既有 buff(Poison/Ward/Surge/Inspire) |

---

## 📌 阶段标记（按 design 文档第八节 roadmap）

- [x] **阶段 1** — 核心 pattern（Strike / Poison / Ward）✅
- [x] **阶段 2** — 机制词典扩展（Expose / Knockback / Execute / Fireball）—— 全部已做
- [x] **阶段 3** — 复杂组合（Decimating Smash / Thorns / Chain Lightning / Mend）—— 全部已做 (2026-05-20 Phase 01 收 Chain Lightning)
- [~] **阶段 4** — 框架深度（Shadow Step / Deathrattle / Stance / Demon Form / Summon Totem）—— 4/5 已做 (Shadow Step / Stance / Demon Form / Deathrattle), Summon Totem TDD spike 完成 → 路线 A 待正式 impl

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
- 剩余 5 技能可执行级实施方案：[remaining-skills-impl-plan.md](remaining-skills-impl-plan.md)（Chain/Shadow/Stance/Demon/Totem，逐个评审）
- 护盾系统：[shield-system.md](shield-system.md)
- 伤害管线：[damage-pipeline.md](damage-pipeline.md)
- LGF 编码规范：`.claude/skills/enforcing-lgf/`
- 新技能落地工作流：`lgf-new-logic-skill` skill
