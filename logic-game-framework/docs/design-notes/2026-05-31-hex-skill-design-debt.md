# Hex-ATB-Battle 技能层设计债清单 (Claude × Codex 双审共识 → grill 拍板)

> 本文记录 2026-05-31 一轮"hex 技能设计评审": Claude 多 agent workflow 产出 → Codex 静态复核对抗式核验 → 与用户 grill 逐条拍板。**多数"设计债"经 grill 后被撤销/降级**(详见各条 ❌/🟢 标记), 因为 hex 定位 = **技能展示 + AI 沙盒**, 非可平衡的可玩对战 (见 CONTEXT.md), balance 类问题按"范式一致/可预测/可introspect"验收而非"数值公平"。

## 📌 最终实现状态 (2026-05-31)

**已实现并测过** (commit 见 CHANGELOG):
- A 批: SkillValidator P0-1 合同 (create_ability_config → static var ABILITY) + 新-1 字段名 + 新-2 projectile 命中伤害可见 + 回归测试。
- A 批补: SkillValidator **Stage5 advisory** (warn-only: determinism token 扫描 + cooldown 边界 + cant_act/silence 门控存在性, strike/move 具名豁免) + test Part C。
- B 批: `lifesteal.gd` schema guard; `piercing_line.gd` anchor 语义注释。
- 可读性: `HexBattleBuffTags` const (P1-5a, cleanse + 6 buff 改引用); `HexBattleSkillHelpers.caster_atk_damage(mult)` (P2-12.1, 9 文件消重复闭包); `cooldown_system` 加 `apply_standard_active_gating` / `apply_basic_attack_gating` helper (P1-2, 仅就位, 28 技能迁移见 [future doc](../future/2026-05-31-condition-bundle-helper-migration.md)); fireball/precise_shot CFG_DAMAGE 双字面量收敛为 DAMAGE const + 巧合注释 (P2-6)。
- bug 修: precise_shot 命中伤害 MAGICAL → PHYSICAL。
- nit: stance `.meta(RANGE, 0)`; expose_buff "有意叠加"注释 (P2-7); summon_totem "空放"注释 (P2-8); fireball/grid_cone "投射物/几何模板"注释含为何不抽 factory/AreaGeometry (P2-12.2/.3)。

**grill 后撤销/不做**: D1 damage scaling 统一 (撤销, scaling vs flat 由技能设计自定) / D2+P2-11 grid_cone RANGE 不一致 (误判撤回) / P1-3 未播种 shuffle (沙盒+事件回放, 不修) / P2-9 piercing fizzle (误判) / P2-12.3 projectile factory (不抽, 改注释) / P2-12.2 AreaGeometry (不抽, 改注释)。

**仍待办** (留文档, 未实现): P1-2 的 28 技能迁移到 helper ([future doc](../future/2026-05-31-condition-bundle-helper-migration.md))。

---

> 以下为评审原始清单 (含已撤销项的推翻理由, 保留供追溯)。

---

## 范围 / 前置

- **范围**: `example/hex-atb-battle` 的 30 个 active ability (`logic/abilities/active/*.gd`) + 其共享基础设施 (`logic/abilities/shared/`, `logic/actions/`, `logic/target_selectors.gd`, `core/hex_world_gameplay_instance.gd`, `core/hex_battle_procedure.gd`)。
- **架构前置**: 技能 = `class_name HexBattle*` 导出 `static var ABILITY := AbilityConfig.builder()...build()`, 无 .tres 数据层, 全声明式。执行链 `ABILITY_ACTIVATE_EVENT → active_use timeline → on_tag([Actions]) → 共享 Action.execute → pre/post event`。投射物技能额外挂 `component_config(ActivateInstanceConfig).trigger(PROJECTILE_HIT_EVENT)` 跑 hit-timeline。
- **依赖前轮决策**:
  - [[2026-04-26]] 死者留 world 不主动 remove (死者 `get_actor()` 非 null, `hex_position` 字段保留, 只清 grid occupant) —— 这条直接决定了 P2-9 是 low 语义瑕疵而非 bug。
  - [[2026-04-29-target-policy-environment-opt-in]] `ALLOWED_TARGET_KINDS` metadata + `can_use_skill_on` 消费 —— P2-10/P2-11 的 RANGE 语义建立在此 gate 上。

## 背景

本轮初衷是"分析 hex 技能设计有无改进点"。多 agent workflow 产出 58 cluster + 55 cross-cutting findings, 对抗式验证后人工与 Codex 双向仲裁, 推翻了若干误报 (见末尾"已推翻"), 收敛成下面这份共识清单。核心判断: **架构干净, 但约定一致性全靠逐文件手抄维持 —— 没有任何共享 helper 固化"标准技能骨架"**。

---

## 设计债清单 (按共识 severity)

### ❌ P1-3 · 默认 demo 未播种 `shuffle()` 落子 — 确认非问题, 不修 (2026-05-31 grill)

> **撤回**: 原标 high, 理由"破坏 bit-identical replay"。两个事实推翻:
> 1. **hex 是沙盒** (见 CONTEXT.md), 不是要复现的可玩对战。
> 2. **hex 的 replay = 事件流回放 (录视频), 不是 seed 重模拟 (记菜谱)** —— `_save_replay` 存 event_collector 收集的事件, animator/director 直接回放; 不依赖"同 seed 重跑同一局"。hex **没有** bit-identical replay 测试 (那是 RTS 的契约, `smoke_replay_bit_identical`, P2.7 AC10)。
> 故未播种 shuffle **不破坏任何现存契约**: 录像照放, 每局布局不同正是 demo 想要的。用户确认 frontend-demo 随机战斗"就是这样, 随便弄弄的"。真需要"可复现随机局"的用 `HexRandomDemoWorldGameplayInstance` (已 seeded)。**不修。**

### 🟡 P1-5a · cleanse 负面分类全靠未命名空间裸字符串 (medium)

- **现象**: `cleanse.gd:69-71` (`has_ability_tag("buff")` / `"negative"`) + `:101-103` (`"control"` / `"passive_break"`) 用裸字符串匹配 debuff 分类。每个 debuff producer (break/expose/poison/silence/stun buff) 各自硬抄这些 tag 字符串。
- **关键**: `"control"` 已有具名 const `action_lock_status.gd:15 TAG_CONTROL`, 但 cleanse + 各 buff 仍有 ~6 处字符串副本 —— live dual-source。新加 debuff 漏写/typo `"negative"` → 对 cleanse 静默不可见, 无报错。
- **改法**: 集中成 `HexBattleBuffTags` const 类 (`TAG_BUFF` / `TAG_NEGATIVE` / `TAG_CONTROL` (复用现有) / `TAG_PASSIVE_BREAK`), cleanse + 6 个 buff 全改引用。
- **影响面**: 跨 7 文件 (cleanse + 6 buff), 改 tag 声明会动 `ability_tags([...])` 列表 —— 需跑 `cleanse_priority_scenario` / `cleanse_self_scenario` + 各 buff scenario 确认 tag 匹配不变。

> **P1-5b (lifesteal schema guard) 已在 B 批实现** (`lifesteal.gd:55-61` 加 `Log.assert_crash`)。此处仅留 P1-5a 文档化。

### 🟢 P2-6 · damage scaling 模型: scaling vs flat = 技能设计自定 (decided 2026-05-31, 降级 low)

> **决议 (grill 拍板)**: **撤销"统一/对齐 scaling"的提法。** 技能用 caster.atk-scaled 还是固定值, 是**技能设计本身的选择, 不立全局规则去拉平** —— 固定伤害的火球 (谁放都 80) 与随 atk 成长的普攻是两种正当设计。原 finding 把"设计选择"误判成"漂移", 撤回。CrushingBlow/SwiftStrike **不需要**改成 atk-scaled (它们就是 flat-by-design)。

剩下的只是**纯可读性**改动 (不改任何数值 / 行为, 优先级 low):

- **现状真问题**: 不在"该不该统一", 而在"代码看不出哪个是故意的", 且有 7 份 byte-identical 复制:
  - atk-scaled `_CASTER_ATK_DAMAGE` 闭包 byte-identical 抄 **7 份** (strike / angle_cone / grid_cone / knockback_punch / lifesteal / piercing_line / wall_breaker); shadow_step 同闭包 `×1.5` (`_ATK_X15`); execute fallback 再抄一份。改 atk 取值方式要动 9 处。
  - fireball flat `80.0` 恰 == Mage atk 80 (纯巧合), 掩盖"本技能不 scale"事实, 可能误导下个作者/AI 以为"固定值要等于 atk"。
- **改法 (low, 可读性)**:
  1. 抽 `HexBattleSkillHelpers.caster_atk_damage(mult := 1.0)` (顺带消 9 处复制; shadow_step 传 1.5) + `flat_damage(x)` 两个具名 helper —— 让"随 atk"和"固定值"各有一个一眼可辨的写法。这同时是 P2-12.1。
  2. fireball (及任何 flat==某 atk 巧合的技能) 文件头加一行注释: "固定值, 与 X atk 相等是巧合, 不随属性缩放"。
- **不做**: 不强制任何技能改 scaling 模型; 不立"普攻必须 atk-scaled"规则。

### 🟢 P2-7 · expose 永久 + 1.5^N 指数叠加 — 有意设计, 仅补注释 (decided 2026-05-31)

> **决议 (grill 拍板)**: expose (增伤标记: 目标受伤 ×1.5) 的**可叠加是有意设计** (用户确认要"放多次更强", 选 A)。与 poison 同属框架明文的"多实例并存"范式 (`apply_buff_action.gd:6-7` 明写不合并; `poison_buff.gd:9-11` 同语义)。`grant_ability` 用 `id` 去重而非 `config_id` (`ability_set.gd:63-66`), 所以同 config 多实例正常并存, 各挂一个 +50% PreEvent → N 实例 = 1.5^N; cooldown 4000ms < duration 5000ms → 单施法者可永久续。
> 沙盒标准三项全过: 一致 (与 poison 同范式) / 可预测 (确定 1.5^N, 无随机) / 数值公平不适用 (沙盒)。**非 bug, 不改行为。**
- **唯一动作 (low, 纯注释)**: ExposeBuff 抄 poison 的"叠加语义注释" —— 点明"多实例指数叠加 + cooldown<duration 可永久 = 有意设计", 免得下一个 reviewer/AI 再当 bug 提。`expose_buff.gd` 已有部分注释 (`:5-7`), 补一句"这是 intended, 非缺陷"即可。

### 🟡 P2-8 · summon_totem 付了 8s cooldown 仍可 whiff (medium)

- **现象**: cost 在 activation 付 (`active_use_component.gd:46`), spawn 在 HIT (t=400ms) resolve (`summon_totem.gd:46`); 6 邻格全占满 → `spawn_actor_action.gd:47-49` 返回 success no-op (`spawn_failed:"no_free_neighbor"`), 不 abort 不退费。AI 只查 RANGE+cooldown, 会在拥挤棋盘把图腾烧成保证 no-op。
- **改法**: `_find_free_neighbor` 加 ring-2 / self fallback, 或把 spawn-feasibility 做成 cast-eligibility predicate (`can_use_skill_*` 阶段查邻格有空)。

### 🟢 P2-10 · coord 技能 (cone/line) 绕过 `can_use_skill_on` (降级 low — 已被 selector 内部 clamp 消解)

- **现象**: `can_use_skill_at_coord` **从未定义** (grep 0)。`hex_battle_procedure._start_actor_action` (`:273-279`) 把 `decision.get("target_coord", null)` 原样塞进 ABILITY_ACTIVATE, 无 coord-aware 资格检查。
- **风险大幅消解 (2026-05-31 grill 复查)**: grid_cone selector 自带 `防远投` clamp (`grid_cone.gd:64-67`, origin 超 CONE_RANGE → fallback caster_pos) 且扇形从 caster_pos 发出, 即便跳过 proc gate **也不会超距**。angle_cone 同样从 caster apex 量。所以现有 3 个 cone 技能没有实际超距漏洞。
- **残留 (low)**: 缺的是一个**通用** `can_use_skill_at_coord` 入口 —— 未来若新增 coord 技能而作者忘了自带 clamp, 就没有框架层兜底。这是"未来 authoring 防护"而非现存 bug。触发面仅 `RandomLoadoutStrategy` (demo_random_frontend, 且先 `can_use_skill_on` 选 actor 再复制其坐标) + 假想的玩家/外部脚本直传 coord。
- **改法 (low, 可选)**: 实现 `can_use_skill_at_coord(actor, skill, coord)` 作为 coord 路径的统一 gate, 把"自带 clamp"从每技能自觉变成框架保证。

### ❌ P2-11 · grid_cone RANGE 语义"不一致" — 误判, 撤回 (2026-05-31 grill 逐行复查)

> **撤回**: 原 finding 称"grid_cone footprint 从 origin 展开, 命中可达声明 RANGE 两倍"。**逐行核实为读错代码**:
> - `grid_cone.gd:69` `_collect_cone_cells(caster_pos, direction)` —— 扇形顶点是 **caster_pos**, 不是 origin。
> - `:93` `_collect_cone_cells(apex, direction)` + `:101` `for ring in range(1, CONE_RANGE+1)` + `:104` `_step(apex, direction, ring)` —— 格子从 **caster** 出发 1/2/3 步, 最远 = CONE_RANGE。
> - `:114` `meta(RANGE, CONE_RANGE=3)` —— 声明 RANGE **正好 == 实际最远 reach**。
> - `target_coord` 只用于 `_resolve_primary_direction` 选方向; `:64-67` 另有 `防远投` guard 把 origin clamp 到 CONE_RANGE 内。
> 结论: grid_cone 与 angle_cone (`get_range(caster_pos, CONE_RANGE)`) **RANGE 语义一致, 都从 caster 发出、都被 CONE_RANGE 限**。无不一致, 无 D2 决策。

### 🟢 P1-2 残留 · 无共享 condition+cost bundle helper (medium, DRY)

> 注: Strike 缺 Silence 这条经共识确认为**有意豁免** (basic attack 不受沉默, 测试文档明写), 非 bug。本条只剩 DRY。

- **现象**: 标准门控四件套 `NoTagCondition(TAG_CANT_ACT)` + `NoTagCondition(TAG_CANT_USE_SKILL)` + `CooldownCondition.new()` + `TimedCooldownCost.new(COOLDOWN_MS)` 在 ~28 个 active 逐字节手抄 (grep `TimedCooldownCost.new` ≈ 29 文件)。`cooldown_system.gd:54-60` 有工厂别名却全被绕过。
- **风险**: 手抄是唯一的"正确性保证" —— 正是它让 Strike Silence 漂移在结构上无法被区分。AI 生成的新技能漏一行无兜底。
- **改法**: `HexBattleCooldownSystem.standard_active_conditions(builder, cooldown_ms)` 应用 `[ActionLock, Silence, Cooldown] + cost`; 显式 `basic_attack_gating(cooldown_ms)` (silence-exempt) 给 Strike, 把豁免从"沉默的省略"变成"具名 opt-out"。

### 🟢 P2-12 残留 · 缺三处共享抽象 (medium, DRY)

1. **damage value resolver**: `skill_helpers.gd` 只有 trigger filter + position/coord resolver, 无 damage/heal value resolver。7 份 byte-identical `_CASTER_ATK_DAMAGE` 闭包应抽 `caster_atk_damage(mult := 1.0)` / `flat_damage(x)` / `flat_heal(x)`。
   - **关联**: SkillValidator 静态读 flat 伤害值受阻 (验证期无 ExecutionContext, `float_val`/`float_fn` 都是 ctx 闭包无类型区分, 静态 `resolve(null)` 对 atk-scaled 会崩)。若框架给 resolver 加 `is_static: bool` + `static_value` 标记, validator 就能静态读 flat 数值做 balance 检查 (现 Stage5 因此只能查 cooldown 不能查 damage)。
2. **AOE 几何**: grid_cone / angle_cone / piercing_line 三套几何 + "存活敌方占格过滤"尾巴各自实现 (`:194-202` / `:181-190` / `:93-102`)。抽 `HexBattleAreaGeometry` (cone/line/ring → `Array[HexCoord]`) + `HexBattleAreaSelector` (吃 footprint-resolver Callable + origin, 统一过滤)。
3. **projectile damage skill factory**: fireball/precise_shot/chain_lightning 各手装四件套 (`on_tag(LAUNCH, LaunchProjectileAction)` + 独立 `*_HIT` timeline + `component_config(ActivateInstanceConfig).trigger(PROJECTILE_HIT_EVENT)` + 该组件的 `on_timeline_start([DamageAction])`)。弹体本身 0 HP 伤害, 全部伤害只来自第④步; 漏掉组件 = 飞出去不掉血且无结构报错。抽 `make_projectile_damage_skill(...)` 把四件套绑死。

### 🟢 P2-* nit 汇总 (low)

- **stance 缺 RANGE meta** (`stance.gd:99`): 其余 self 技能声明 `RANGE 0`, stance 漏; consumer 默认缺失为 1 (`hex_world_gameplay_instance.gd:217`)。self-cast 今天无害, 加 `.meta(RANGE, 0)` 对齐。
- **duration 默认 2000 多源**: stun/silence/break 各自 `X_DURATION_MS` + raw-string meta key + buff `DEFAULT_DURATION_MS` 三处。让 buff 做单一来源。
- **fireball/precise_shot CFG_DAMAGE 与 hit float_val 双字面量**: CFG_DAMAGE 对 HP dead (只进 projectileHit payload 当表演/replay metadata), 改一个不改另一个会让回放/VFX 伤害脱节。抄 chain_lightning 用具名 const 双处引用。
- **swift_strike 三连击三抄 `float_val(10.0)`** (`:39-53`) + `{"hits":3}` 另抄 (`:37`): 抽 `const PER_HIT_DAMAGE`/`HIT_COUNT` 循环建。
- **swap 描述自相矛盾** (`:8` vs `:119` vs `:47-48` 代码拒 self): 删描述里"自己"。
- **spawn_fire_tile / totem 描述硬抄数值** (`:35`): consts 是真值, 描述漂成字面量, 用 `%d` 插值。
- **HealAction / DamageAction execute 路径裸 `print()`** (`heal_action.gd:81,111-113` / `damage_action.gd:192`): 确定性 hot path 无条件 stdout, 走 Log/level-gated。
- **chain_lightning copy-paste `_projectile_hit_filter`** (`:47-66`): 共享 `projectile_hit_filter` 无 extra-predicate hook, 加 `projectile_hit_filter_with(extra: Callable)`。
- **timeline 同 ms tag 排序非全序** (`ability_execution_instance.gd` tick() sort_custom 仅按 tagTime): 今天 0 碰撞 (每 timeline tag ms 唯一), 未来/AI 技能声明两个同 ms tag 即 native-vs-WASM 不稳。加次级 key (tag name / 插入序) 成全序。

---

## 待拍板的设计决策 (grill-me 讨论项)

| ID | 决策 | 状态 |
|---|---|---|
| **D1** | damage scaling 原则 (P2-6) | **已定 (2026-05-31 grill)**: 撤销统一; scaling vs flat 由技能设计自定。只做 low 可读性 (具名 helper + 巧合注释)。 |
| **D2** | grid_cone RANGE 语义 (P2-11) | **作废 (2026-05-31 grill)**: 前提是误判 (读错代码), cone RANGE 语义本就一致。无决策。 |

> 两个待拍板决策经 grill 后均无需拍板 (D1 = 设计选择撤销统一, D2 = 误判撤回)。其余 P1/P2 是确定性改法, 按 severity 顺序实现。

---

## 实现优先级 (拍板后)

P1: P1-3 (seeded base RNG) → P1-2 (condition bundle helper) → P1-5a (BuffTags const)
P2: P2-7 (expose cap) → P2-8 (totem feasibility) → P2-10 (can_use_skill_at_coord) → P2-11 (按 D2) → P2-6 (按 D1) → P2-12 (三抽象)
P2-nit: 批量收尾 (stance RANGE / 双字面量 / print→Log / 描述插值 / 全序排序)

---

## 已推翻的误报 (避免下轮重提)

- **poison "double-apply"**: 假; `poison_tick_action.gd:57` 只 apply 一次 (PURE 不吃 atk 是 `:11` 明文契约)。
- **PreciseShot "零伤 bug"**: 假; `precise_shot.gd:75-88` 正确装 hit-timeline DamageAction。
- **crushing_blow / swift_strike "抄了 caster.atk"**: 假; 二者纯 flat `float_val`。
- **knockback_punch "dead 局部变量 duration2"**: 捏造; 实为干净 return。`COLLISION_ACTION_LOCK_BONUS_MS := 0.0` 是具名预留 tuning 非 dead code。
- **cone 常量 (DAMAGE:=35 / COOLDOWN 5000 / cue cone_swing)**: 捏造; 实际无 DAMAGE const (用 atk resolver) / COOLDOWN 8000 / cue `angle_cone_cast`。
- **P2-9 piercing_line "anchor 死亡 → 整条线 fizzle"**: 推翻 (Codex refute 正确); 死者留 registry + hex_position 保留, 方向照常算, 不 fizzle。降为 low 语义瑕疵, **已在 B 批加注释说明**。
- **P2-11 grid_cone "RANGE 语义不一致 / footprint 超距"**: 推翻 (grill 逐行复查); 扇形从 caster_pos 发出 (`grid_cone.gd:69` 传 caster_pos 为 apex), 最远 == CONE_RANGE == 声明 RANGE, 与 angle_cone 一致。原 finding 把 `_collect_cone_cells(caster_pos,...)` 读成"从 origin 展开"。connected: P2-10 风险也因此 clamp 大幅消解。

## 方法论补记 (2026-05-31 grill)

本轮 review 的 workflow-generated findings 即便过了对抗式验证, 仍有**"读错代码 → 病理化成设计债"**的系统性误报 (D1 damage scaling 把设计选择当漂移; P2-11/D2 把 caster-apex cone 读成 origin-extended)。教训: **finding 引用具体行为前必须逐行读那段代码**, 尤其涉及"哪个变量当起点/参数传给谁"时 —— 对抗式验证只查"claim 是否自洽", 不一定能抓出"原始读图就错了"。与 [[feedback_verify_field_names_before_use]] 同源 (假设代替核实)。

## 方法论 (本轮固化)

- **死者语义不变量** (见 [[2026-04-26]]): 任何"目标在 cast→结算间死亡 → 技能 fizzle/返回 []"的 finding 默认是误判 —— 死者还在、hex_position 还在。判这类 bug 前先套这三条不变量。
- **引用类成员前先读真实定义**: 本轮 SkillValidator 修复中假设了多个不存在的字段名 (`_damage` / `Resolver.FloatValueResolver` / `_heal_resolver` / `trigger_event_type` / `has_active_use` / `get_metadata`), 全因没先读真实类。改完必跑 `.tscn` smoke, 编译错误即字段假设错。
