# 进阶技能开发规划（Phase 2+）

> 本文是 16 个示范技能之后的进阶技能讨论入口。
> 前置假设：[`remaining-skills-impl-plan.md`](remaining-skills-impl-plan.md) 覆盖的 Chain Lightning / Shadow Step / Stance / Demon Form / Summon Totem 已完成并回写 [`skill-implementation-progress.md`](skill-implementation-progress.md)。
> 来源：`.lomo-team/reference/inkmon-skill-design.md` 第九节 Phase 2+ 候选 + 当前 hex-atb-battle 已落地 pattern。
> 创建：2026-05-20 · Codex
> Gateway 方案：[`2026-05-22-hex-battle-gateway-contract.md`](../design-notes/2026-05-22-hex-battle-gateway-contract.md)。

## 目标

这批技能不是为了扩充最终技能池数量，而是补 16 技能之后仍缺的可复用机制范式：

- active-use gating / control status
- stun / silence control boundary
- board hazard / tile effect
- buff cleanup / dispel
- atomic position swap
- actual-damage-based follow-up
- hex-specific line / cone target shape

每个新技能必须能回答两个问题：

1. 它给未来 AI / 设计者留下了什么可模仿 pattern？
2. 它是否复用现有 LGF / hex battle 机制，而不是另起一套系统？

## 非目标

- 不做羁绊、商店、装备合成、升星等 meta 层系统。
- 不为了一个技能建立通用 StatusSystem / TileSystem / EquipmentSystem。
- 不把单技能私有逻辑提升成 public Primitive Action，除非至少两个以上技能能直接复用。
- 不改 core Timeline 语义；延迟、周期、链式响应继续优先走现有 Timeline / Action / Event 流。

## 候选总览

| 顺序 | 技能 / 机制 | 价值 | 新 pattern | 初始状态 |
|---|---|---|---|---|
| A | Stun / 眩晕 | P0 | hard control；阻止 Move / Strike / active skill 的下一次主动行动 | Gateway 已拍板；待实现 |
| B | Silence / 禁用技能 | P0 | soft control；区分 `cant_act` 与 `cant_skill` | Gateway 已拍板；待实现 |
| C | Fire Tile / 地形伤害格 | P0 | passable board hazard；tile effect lifecycle | 待 spike |
| D | Cleanse / Dispel | P1 | 按 tag / polarity 清理 buff/debuff | 待评审 |
| E | Swap / 位置交换 | P1 | 双 actor 原子占位交换 + 双 displacement event | 待评审 |
| F | Lifesteal / 吸血 | P1 | `actual_life_damage` 驱动 follow-up heal | 待评审 |
| G | Line / Cone AoE | P2 | hex shape TargetSelector | 待评审 |

状态：待评审 = 先讨论语义；待 spike = 先写探针确认底层可行性。

## 现有机制复用图

| 想做什么 | 优先复用 | 不先新增 |
|---|---|---|
| 眩晕 | ActiveGateway、`cant_act` gate tag、`TagComponentConfig`、`TimeDurationConfig` | Timeline cancel / interrupt system |
| 沉默 | ActiveGateway、`cant_skill` gate tag、`TagComponentConfig`、`TimeDurationConfig` | 全局 StatusSystem / Ability state machine |
| 地形伤害格 | `EnvironmentActor`、`CollisionProfile.blocks_path=false`、`TimelineData.periodic`、事件录像 | 独立 TileSystem，除非 spike 证明 grid occupant 模型不支持 passable overlay |
| 清除 debuff | `AbilitySet` ability 列表、buff `ability_tags(["buff","negative"])`、TimeDuration lifecycle | 直接改 buff component 内部字段 |
| 位置交换 | `HexWorldGameplayInstance.grid` 占位操作、`ActorDisplacedEvent`、`ActionLockStatus` | 用两次 PushAction 伪装 swap |
| 吸血 | `DamageEvent.actual_life_damage`、`HexBattleHealAction`、post-damage filter | 按 raw damage 直接加血 |
| 直线 / 扇形 AoE | `TargetSelector` 子类、`HexCoord` 邻接/方向、Fireball damage pattern | 新 AoE action / 新 damage pipeline |

## Gateway 设计摘要

Gateway 是 hex battle example 层的“入口资格”规则，不是新的 core runtime system。完整方案见 [`2026-05-22-hex-battle-gateway-contract.md`](../design-notes/2026-05-22-hex-battle-gateway-contract.md)。

本批技能只实现 ActiveGateway；PassiveGateway / BuffGateway 先保留设计边界，等 Stun / Silence 跑通后再扩。

### ActiveGateway 合同

- hex battle 中，一个可主动释放的 Ability 必须有且仅有一个 `ActiveUseComponent`。
- `can_use_skill_on(actor, skill, target)` 可以读取唯一 `ActiveUseComponent` 的 gateway 配置，不需要 snapshot / profile 复制层。
- target eligibility 仍走 ability metadata + declarative query，不进 runtime `Condition`。
- dynamic actor-state gate 走 ActiveGateway runtime condition，例如 `cant_act`、`cant_skill`。
- `Move` 当前使用 `ActivateInstanceConfig`，AI 路径由 `CharacterActor.can_act()` 的 primary gate 阻止；未来玩家直控 move path 需要补自己的 action-lock gate。

### Tag 词表

状态 tag 分两层：

- semantic status tag：`stunned`、`silenced`、`rooted`
- functional gate tag：`cant_act`、`cant_skill`、`cant_move`、`cant_basic_attack`

Stun buff 应同时持有 semantic tag 与 gate tag，例如 `stunned` + `cant_act`。Cleanse / UI / immunity 读 semantic tag；Gateway 消费 gate tag。

## Phase A · Stun / 眩晕

### 价值

当前已有 `cant_act`，但它主要是 forced displacement 后的短时 action lock，还没有一个正式的“眩晕技能”作为 hard control 示例。Stun 应作为控制类技能的第一块基准：阻止目标下一次主动行动，包括 Move、Strike 和所有 active skill。

这能先把 hard control 语义立住，再和 Silence 的 soft control 对照，避免把 `cant_act` / `cant_skill` 混成一类状态。

### 初始方案

新增一个负面 buff，例如 `stun_buff`：

- buff tags：`["buff", "negative", "control", "stun"]`
- component tags：`cant_act`、`stunned`
- duration：短时，例如 1500-2000ms
- skill：`skill_stun` 命中目标后 apply buff

V1 语义：

- 阻止 Move / Strike / 所有 active skill 的下一次主动触发。
- 不取消已经 in-flight 的 ability timeline。
- 不冻结 buff tick / post-damage / deathrattle 这类被动响应。

### Chosen

复用 ActiveGateway 的 runtime condition。Stun 是释放前 gate，不是 runtime interrupt。

Stun buff 是状态生命周期所有者；它通过 `TagComponentConfig` 持有 `stunned` 与 `cant_act`。ActiveGateway 消费 `cant_act`，UI / cleanse / immunity 可以消费 `stunned` / `control`。

### Rejected

- 不引入 Timeline cancel：打断施法是 V2 问题，先不改 core Timeline 合同。
- 不新建 StatusSystem：现有 buff + tag + condition 足够表达 V1。
- 不把 Stun 写成 `cant_skill`：Stun 是 hard control，Silence 才是 soft control。

### 待拍板问题

- Stun duration 初始值用 1500ms 还是 2000ms？
- Stun 是否给前端单独 stage cue / floating text？
- Stun 是否允许已有 movement timeline 完成？V1 倾向允许，不中断 in-flight。
- Stun 是否应该复用 `cant_act`，还是新增 `cant_action`？当前倾向复用 `cant_act`。

### 验收

- 被 stun 的 actor 无法 Move / Strike / 释放任意 active skill，并产生 `AbilityActivateFailed`。
- 已经 in-flight 的 timeline 不被中途 cancel。
- stun duration 结束后，Move / Strike / active skill 恢复。
- buff tick / post-damage / deathrattle 不被 Stun 阻断。

## Phase B · Silence / 禁用技能

### 价值

Silence 要表达的是“不能释放技能”，不等同于不能移动 / 不能普攻。它应在 Stun 之后讨论，用来建立 soft control pattern。

这能补一个重要边界：control status 不应该全部混成一个 `cant_act`。

### 初始方案

新增一个负面 buff，例如 `silence_buff`：

- buff tags：`["buff", "negative", "control", "silence"]`
- component tag：`cant_skill`
- duration：短时，例如 2000ms
- skill：`skill_silence` 命中目标后 apply buff

主动技能侧新增或复用 condition：

- basic `move` / `strike` 是否受影响需要拍板
- 非基础 active skill 默认加 `NoTagCondition("cant_skill")`

### Chosen

复用 ActiveGateway 的 runtime condition。Silence 是释放前 gate，不是 runtime cancel。

Silence buff 是状态生命周期所有者；它通过 `TagComponentConfig` 持有 `silenced` 与 `cant_skill`。ActiveGateway 根据 active ability 的 gateway / action kind 判定是否消费 `cant_skill`。

### Rejected

- 不直接用 `cant_act` 代替 silence：语义会变成 stun / stagger。
- 不取消已经 in-flight 的 ability timeline：这会碰 Timeline cancel 语义，当前不作为 V1。
- 不新建 StatusSystem：现有 buff + tag + condition 足够表达。

### 待拍板问题

- Silence 是否允许普攻？
- Silence 是否允许 Move？
- Silence 是否只挡 `ability_tags` 含 `skill` 的 active ability？
- 前端显示是否复用 buff icon / floating text，还是只进 log？

### 验收

- 被 silence 的 actor 释放非基础 skill 时产生 `AbilityActivateFailed`，reason 可读。
- silence 不影响已在执行中的 timeline。
- silence duration 结束后同一个 skill 可正常释放。
- 若约定允许 `move` / `strike`，必须有 scenario 单独证明。

## Phase C · Fire Tile / 地形伤害格

### 价值

16 技能里有 actor buff、projectile、summon、death reaction，但还没有“格子本身带规则”的 board-control pattern。Fire Tile 是 hex tactics 很核心的机制，也能为 trap、ice tile、poison cloud 留样板。

### Spike 优先

这里先 spike，不直接写正式技能。关键未知是 grid 是否允许 passable overlay：

- `EnvironmentActor` 目前能表达环境物，但 grid occupant 可能天然一格一个 occupant。
- `CollisionProfile.blocks_path=false` 能表达“不阻挡寻路”，但不等于能与 character 共格。
- 如果不能共格，Fire Tile 不应伪装成普通 EnvironmentActor。

### 初始路线

路线 A：passable `EnvironmentActor`

- `environment_kind = "fire_tile"`
- `blocks_path=false`
- 不阻挡 actor 站上去
- periodic tick 或 enter trigger 造成 fire damage

路线 B：battle-level tile effect registry

- battle 维护 `coord -> tile_effects`
- tick 时扫描站在 effect 上的 actors
- event stream 记录 tile placed / tile expired / tile tick damage

### Chosen 倾向

先 spike 路线 A。如果 grid occupancy 不支持 overlay，则转路线 B。

### Rejected

- 不把 Fire Tile 做成挂在 actor 身上的 burn buff：那是 DOT，不是 board hazard。
- 不用不可见 Actor 占格挡路：会把 hazard 误变成 wall。
- 不先做通用 TileSystem：除非 Fire Tile + Trap + Aura 同时需要。

### 待拍板问题

- Fire Tile 是 enter 触发、periodic 触发，还是二者都有？
- 伤害 attribution 归创建者、地形、还是空 source？
- 叠加多个 Fire Tile 是刷新 duration、叠层，还是并存？
- replay / frontend 需要哪些最小事件：placed、tick、expired？

### 验收

- actor 可站在 Fire Tile 上且寻路/占位不混乱。
- tick damage 走 `HexBattleDamageUtils.apply_damage`，能被护盾、death、post-damage 看到。
- replay event order 稳定；同 seed 重跑事件序列一致。

## Phase D · Cleanse / Dispel

### 价值

Poison / Expose / Silence / Burn 这类负面效果会越来越多，需要一个“状态清理”的范式。Cleanse 是 buff/debuff 系统的反向操作，能验证 ability lifecycle cleanup 是否可靠。

### 初始方案

新增 `skill_cleanse`：

- target：最低血或最近友方，具体按 AI 策略拍板
- effect：移除目标身上 1 个或全部 negative buff
- 可选：治疗少量 HP，作为可见收益

### Chosen

按 buff `ability_tags(["buff","negative"])` 选择并 revoke/remove ability，让 buff 自己走 remove cleanup。

### Rejected

- 不直接删 tag：component tag / loose tag / buff state 来源不同，直接删 tag 容易漏 cleanup。
- 不做“万能清所有状态”：shield / stance / summon ownership 等 positive 或 structural 状态不应被误清。
- 不把 Cleanse 写成框架层 Primitive Action，先作为 skill-local routine；等多个技能需要时再抽。

### 待拍板问题

- 清 1 个 negative，还是清全部 negative？
- 清理顺序按剩余 duration、施加时间、固定 priority，还是 first found？
- Cleanse 是否能清控制类 negative，例如 silence？
- 是否保留 “cleanse + heal” 双效果？

### 验收

- 清理 Poison / Expose / Silence 至少两种不同实现形态。
- 被清理 buff 的 component cleanup 生效。
- 不误清 positive buff / shield / stance tag。

## Phase E · Swap / 位置交换

### 价值

Push / Shadow Step 都是单 actor 位移。Swap 验证两个 actor 的 grid occupancy 原子变化，以及 replay / frontend 如何表达同一 tick 的双位移。

### 初始方案

新增 `skill_swap`：

- 目标：一个敌人或友军，待拍板
- 效果：caster 与 target 交换 hex_position
- 事件：两个 `ActorDisplacedEvent`，带同一个 `swap_id`
- 失败：任一 actor dead / invalid / grid move 失败时整个 swap 不发生

### Chosen

写 skill-local `_SwapPositionsAction`，内部做原子校验和占位交换。等第二个 swap-like 技能出现，再考虑 public primitive。

### Rejected

- 不用两次 PushAction：push 是方向位移和碰撞结算，swap 是占位交换，事件语义不同。
- 不先抽 `TeleportAction`：Shadow Step 的 teleport 与 swap 失败语义不同，先保持 skill-local。
- 不允许半成功：一个 actor 换了、另一个没换会破坏 grid/world 一致性。

### 待拍板问题

- Swap 能否作用友方？
- Swap 是否给双方加短时 `cant_act`？
- Swap 是否要求 line of sight / range？
- 同一 tick 两个 swap 冲突时怎么处理：拒绝后到，还是按事件顺序？

### 验收

- 两个 actor 坐标互换，grid occupant 与 actor.hex_position 一致。
- 事件顺序稳定，frontend 可播放双 displacement。
- blocked / dead / invalid target 不产生半成功。

## Phase F · Lifesteal / 吸血

### 价值

Thorn 已覆盖受击后反应，Holy Heal 覆盖主动治疗，但还没有“伤害实际造成多少 → 后续治疗多少”的桥接 pattern。Lifesteal 能验证 `actual_life_damage`、shield、post-damage、heal action 的衔接。

### 初始方案

新增 `lifesteal_strike` 或 passive `bloodthirst`：

- 造成物理伤害
- 根据 `DamageEvent.actual_life_damage * ratio` 治疗 source
- shield 全吸收时不吸血
- target 死亡也可吸血，按实际掉血计算

### Chosen

使用 damage 结算后的 event 字段，优先挂在 `DamageAction.on_hit` 或 post-damage response 上；治疗走 `HexBattleHealAction`。

### Rejected

- 不按 raw damage 吸血：会无视护盾和减伤。
- 不在 PreDamage 阶段预估吸血：会和 shield / crit / expose 等后续修改冲突。
- 不让 reflected damage 触发 lifesteal，除非以后明确做 reflect-lifesteal 规则。

### 待拍板问题

- Lifesteal 是 active skill、passive buff，还是二者都要？
- 是否允许 overheal 触发 `on_overheal`？
- 自伤是否触发 lifesteal？
- reflected damage 是否显式排除？

### 验收

- shield 全吸收时吸血 = 0。
- 部分吸收时按 `actual_life_damage` 吸血。
- heal event 进入 replay，source / target 字段正确。

## Phase G · Line / Cone AoE

### 价值

Fireball 覆盖了范围多目标，但 line / cone 是 hex tactics 的常见空间表达。这个 phase 主要补 TargetSelector shape，而不是补新伤害机制。

### 初始方案

二选一先做：

- `piercing_line`：沿 caster facing 或 caster→target 方向取 N 格，命中线上所有敌人。
- `flame_cone`：以 target direction 为中心，取 60/120 度扇形。

### Chosen

新增 example-local TargetSelector 子类，复用 Fireball / DamageAction 伤害结算。

### Rejected

- 不新增 AoEAction：形状选择是 TargetSelector 责任，伤害仍是 DamageAction。
- 不把 line / cone 全部一次做完：先做一个最能证明方向语义的 shape。
- 不依赖前端猜形状：如果需要表演，逻辑事件或 stage cue 要带 shape params。

### 待拍板问题

- 方向来自 caster facing，还是 caster→target？
- line 是否穿透阻挡墙？
- cone 是否包含中心线两侧等距格？
- 是否需要 hit order，还是同 tick 无序多目标即可？

### 验收

- TargetSelector 单测 / scenario 覆盖 6 个方向。
- 有 wall / occupied actor 时语义明确。
- 多目标 damage event 数量和目标集合稳定。

## 暂缓项

| 候选 | 暂缓原因 |
|---|---|
| Pull | `PushAction` 已预留 distance / displacement_kind，新增 pattern 较少；可作为 Swap 前的小回归，不作为主 phase |
| Counter | 与 Thorn 的 PostDamage 反应重叠；等需要“防御姿态 + 反击”再做 |
| Flame Barrier | Thorns 变体，收益低 |
| Corpse / Exhume | 需要 corpse lifecycle，容易引入新系统；除非 Deathrattle + Summon 后明确需要 |
| Summon Wall | 与 Summon Totem / EnvironmentActor 重叠；等 Fire Tile spike 后再看 board object 统一策略 |
| Equipment On Hit | 属于装备系统，不放 LGF example 当前阶段 |
| Synergy / Star Level | 属于 inkmon meta 层，不放进技能示范库 |

## 推荐讨论顺序

1. 先拍板 Stun 语义：是否只阻止后续主动行动、不打断 in-flight timeline。
2. 再拍板 Silence 语义：`cant_skill` 是否存在、普攻/移动是否允许。
3. 决定 Fire Tile 是否进入 spike：这会影响后续 Trap / Wall / Hazard 的表示方式。
4. Cleanse 与 Stun / Silence 可以成对设计：一个移除 negative control，一个验证 cleanup。
5. Swap 与 Line/Cone 都依赖方向/坐标语义，建议等 Shadow Step 的 facing 基础设施落地后再评审。
6. Lifesteal 独立性较强，可在 damage pipeline 稳定时穿插实现。

## 落码前总检查

- [ ] 16 技能全部完成，`skill-implementation-progress.md` 已更新到 16 / 16。
- [ ] 当前进阶技能的 Chosen / Rejected / 待拍板问题已收敛。
- [ ] 明确它补的是新 pattern，不是已有技能换皮。
- [ ] 新 public Action / Condition / TargetSelector 必须登记 rationale；技能私有逻辑优先 SkillLocalAction。
- [ ] scenario 覆盖成功、失败、边界三类 case。
- [ ] 若涉及 grid / actor lifecycle / replay，先写 spike 或最小红测。
- [ ] 回写 `skill-implementation-progress.md` 的 Phase 2+ 区域或新增进阶进度表。
