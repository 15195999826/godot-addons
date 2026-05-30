# Hex-ATB-Battle 技能层设计债清单 (Claude × Codex 双审共识)

> 状态: **未实现, 仅落盘**。本文记录 2026-05-31 一轮"hex 技能设计评审"中识别、经两个独立模型 (Claude 多 agent workflow + Codex 静态复核) 逐条对抗式核验后达成共识的设计债。
> 已在本轮**实现**的部分不在此文 (见 CHANGELOG `[Unreleased] — 2026-05-31`): A 批 SkillValidator 三连环修复 + Stage5 advisory (主仓 `scripts/SkillValidator.gd`), B 批安全子集 (`lifesteal.gd` schema guard / `piercing_line.gd` anchor 语义注释)。
> 本文 = 剩余的 P1-3 / P1-5a / P2-* 设计债, 待后续轮次按优先级实现。

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

### 🟠 P1-3 · 默认 demo 用未播种 `shuffle()` 落子 (high)

- **现象**: `hex_demo_world_gameplay_instance.gd:240` `available_coords.shuffle()` 用 Godot 全局未播种 RNG。此 base class 是生产入口 —— web `godot_run_battle` (`SimulationManager.gd:68` → 实例化它)、`demo_frontend`、`demo_headless` 全走它。
- **影响**: 起始 hex 位置喂给所有 nearest/distance/RANGE 决策, 整场战斗从 tick 0 起不确定; `_save_replay` 存了事件但产生它们的 setup 无法从 seed 重放 —— 与项目"bit-identical replay"卖点冲突。
- **对照**: 子类 `HexRandomDemoWorldGameplayInstance` 已做对 —— `_rng.seed = _resolved_seed` (`:34-35`) + 自写 `_shuffle_hex_coords` (`:65`)。base 没拿到这个待遇。
- **改法**: 给 base 一个 seeded `RandomNumberGenerator` (`start()`/`_setup_teams` 接 `random_seed`, 默认固定值), 把 `:240` 的 `shuffle()` 换成子类已验证的 `_shuffle_hex_coords` 模式。把 `_resolved_seed` 嵌进 `_save_replay` 的 replay meta。
- **风险**: 改 base 的 setup RNG 会改变默认 demo 的初始布局 (现有依赖固定布局的 frontend/headless smoke 可能数值漂移)。需跑 `hex/regression` + `hex/frontend` 确认。**这是改 base 契约, 不是机械修复, 故落本文不在 B 批做。**

### 🟡 P1-5a · cleanse 负面分类全靠未命名空间裸字符串 (medium)

- **现象**: `cleanse.gd:69-71` (`has_ability_tag("buff")` / `"negative"`) + `:101-103` (`"control"` / `"passive_break"`) 用裸字符串匹配 debuff 分类。每个 debuff producer (break/expose/poison/silence/stun buff) 各自硬抄这些 tag 字符串。
- **关键**: `"control"` 已有具名 const `action_lock_status.gd:15 TAG_CONTROL`, 但 cleanse + 各 buff 仍有 ~6 处字符串副本 —— live dual-source。新加 debuff 漏写/typo `"negative"` → 对 cleanse 静默不可见, 无报错。
- **改法**: 集中成 `HexBattleBuffTags` const 类 (`TAG_BUFF` / `TAG_NEGATIVE` / `TAG_CONTROL` (复用现有) / `TAG_PASSIVE_BREAK`), cleanse + 6 个 buff 全改引用。
- **影响面**: 跨 7 文件 (cleanse + 6 buff), 改 tag 声明会动 `ability_tags([...])` 列表 —— 需跑 `cleanse_priority_scenario` / `cleanse_self_scenario` + 各 buff scenario 确认 tag 匹配不变。

> **P1-5b (lifesteal schema guard) 已在 B 批实现** (`lifesteal.gd:55-61` 加 `Log.assert_crash`)。此处仅留 P1-5a 文档化。

### 🟡 P2-6 · damage scaling 模型混用, 无统一原则 (medium, **需拍板**)

- **现象**: 30 个 active 里只有部分随 caster.atk 缩放。逐文件核实 (Codex 仲裁后权威结论):
  - **atk-scaled** (`Resolvers.float_fn` 读 `attribute_set.atk`, byte-identical 7 份): strike / angle_cone / grid_cone / knockback_punch / lifesteal / piercing_line / wall_breaker; shadow_step 是同闭包 ×1.5; execute fallback 再抄一份。
  - **flat** (`Resolvers.float_val`): crushing_blow `90.0` (`:37`), fireball `80.0` (`:82`/`:84`), precise_shot `45.0`, holy_heal `40.0`; chain_lightning flat-but-data-carried (customData 60/48/38.4)。
- **漂移证据**: 同为 melee class-default 普攻核, strike (Warrior) atk-scaled 而 crushing_blow (Berserker) flat 90; `strike.gd:19` 明确点名 CrushingBlow 应复用 atk 模板 —— **documented-but-unfulfilled contract**。fireball flat 80 == Mage atk 80 是巧合, 掩盖了"不缩放"事实 (buff 抬 atk 时 strike 缩放 / fireball 不缩放, 巧合无声破裂)。
- **待拍板 (政策选择, 见末尾决策表 D1)**: class-default 普攻是否一律随 atk? spell/projectile nuke 是否保留 flat-by-design? CrushingBlow/SwiftStrike 是否对齐?

### 🟡 P2-7 · expose 100%+ uptime + 乘法叠加 (medium)

- **现象**: `expose.gd:12` COOLDOWN 4000ms < `expose_buff.gd:15` DURATION 5000ms → 单施法者可永久 expose。且 `ExposeBuff` 文档 (`expose_buff.gd:5-7`) 明写多实例并存 = `1.5^N` 乘法放大 (每实例挂独立 PreEventComponent), `ApplyBuffAction` 零幂等 (`apply_buff_action.gd:6-7`, 有意但 comment-only)。
- **对照**: hard-CC (stun/silence/break) 是 ref-counted overlap 安全的 ~33% uptime; 两个 damage-amp/DoT (expose) 却近 100%+ 且指数叠加。
- **改法**: 把 ExposeBuff cap 成单实例 refresh (overflow_policy = REFRESH, 或 ApplyBuffAction 查重)。需跑 `expose_scenario` 确认单层数值不变。

### 🟡 P2-8 · summon_totem 付了 8s cooldown 仍可 whiff (medium)

- **现象**: cost 在 activation 付 (`active_use_component.gd:46`), spawn 在 HIT (t=400ms) resolve (`summon_totem.gd:46`); 6 邻格全占满 → `spawn_actor_action.gd:47-49` 返回 success no-op (`spawn_failed:"no_free_neighbor"`), 不 abort 不退费。AI 只查 RANGE+cooldown, 会在拥挤棋盘把图腾烧成保证 no-op。
- **改法**: `_find_free_neighbor` 加 ring-2 / self fallback, 或把 spawn-feasibility 做成 cast-eligibility predicate (`can_use_skill_*` 阶段查邻格有空)。

### 🟡 P2-10 · coord 技能 (cone/line) 绕过 `can_use_skill_on` (medium)

- **现象 (Codex 仲裁后真实路径)**: `can_use_skill_at_coord` **从未定义** (grep 0)。`hex_battle_procedure._start_actor_action` (`:273-279`) 把 `decision.get("target_coord", null)` 原样塞进 ABILITY_ACTIVATE 事件, **无任何 coord-aware 资格检查**; cone selector 随后把 target_coord 当 origin 读 (`grid_cone.gd:178` / `angle_cone.gd:163`)。
- **触发面**: actor-target 技能走 `can_use_skill_on` (查 alive/kind/faction/RANGE); coord 技能这条并行路径无等价门控 → cone/line 可超距施放。默认对战不触发 (`RandomLoadoutStrategy` 是唯一附 coord 的, 且先 `can_use_skill_on` 选 actor 再复制其坐标, `random_loadout_strategy.gd:120/156`); **风险主要在玩家/UI/外部脚本直接传任意 coord**。
- **改法**: 实现 `can_use_skill_at_coord(actor, skill, coord)` (RANGE = caster→origin 或 caster→最远 footprint cell; faction/kind 适用), 在 `_start_actor_action` 的 coord 分支 + RandomLoadout 发决策前调用。

### 🟡 P2-11 · grid_cone 的 RANGE 语义与其它技能不一致 (medium, **需拍板**)

- **现象**: `can_use_skill_on` (`hex_world_gameplay_instance.gd:217-219`) 把 RANGE 当 caster→target-**actor** 距离门。但 grid_cone 把 `target_coord` 当 **origin**, footprint 从 origin 再向前展开 `CONE_RANGE-1=2` 格 (`grid_cone.gd:76-77`), 命中距离排序也从 origin 量 (`:205`)。→ 一个 origin 距 caster ~3 格的 cone 会打到距 caster ~5 格的 cell (近声明 RANGE 的两倍)。angle_cone 反而从 caster apex 量 (`get_range(caster_pos, CONE_RANGE)`), RANGE == caster reach。
- **本质**: 同一个 RANGE meta 被 gate 和 selector 用两种不同距离定义 (origin-depth vs caster-reach); 且 coord 路径 (P2-10) 整个跳过 gate, grid_cone 的 RANGE 实际未被强制。
- **待拍板 (政策选择, 见末尾决策表 D2)**: RANGE 在每种寻址模式下量的是什么? gate origin 选择 + 文档化"RANGE = cone 深度", 还是把 footprint clamp 到 caster RANGE 内?

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

| ID | 决策 | 候选 A | 候选 B | 影响面 |
|---|---|---|---|---|
| **D1** | damage scaling 原则 (P2-6) | class-default 普攻一律随 atk; spell-nuke 保留 flat 但文件头注释声明"by-design" | 全部统一为 atk-scaled (含 fireball/holy_heal), 删 flat | A: 改 crushing_blow/swift_strike/execute ~3 文件 + 加注释; B: 改所有 flat 技能 + 重新平衡数值 |
| **D2** | grid_cone RANGE 语义 (P2-11) | gate origin 选择 + 文档化"RANGE = 从 origin 的 cone 深度" (保留远投 origin) | footprint cell clamp 到 caster RANGE 内 (RANGE == 实际最大 reach, 与 angle_cone 对齐) | A: 加 origin gate, 玩法不变; B: 改 grid_cone footprint 计算, cone 实际范围缩小 |

> 这两条是**纯政策/平衡选择**, 不是对错问题, 需游戏设计意图定夺。其余 P1/P2 是确定性改法, 拍板后按 severity 顺序实现。

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

## 方法论 (本轮固化)

- **死者语义不变量** (见 [[2026-04-26]]): 任何"目标在 cast→结算间死亡 → 技能 fizzle/返回 []"的 finding 默认是误判 —— 死者还在、hex_position 还在。判这类 bug 前先套这三条不变量。
- **引用类成员前先读真实定义**: 本轮 SkillValidator 修复中假设了多个不存在的字段名 (`_damage` / `Resolver.FloatValueResolver` / `_heal_resolver` / `trigger_event_type` / `has_active_use` / `get_metadata`), 全因没先读真实类。改完必跑 `.tscn` smoke, 编译错误即字段假设错。
