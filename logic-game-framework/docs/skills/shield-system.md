# Shield System — 护盾系统

## 状态

🔵 **V1 已落地** — 2026-04-25 实现完成，scenarios 全绿（3/3 shield + 9/9 既有 + 59/59 LGF 单元 + frontend main 通过）。

---

## 🎯 核心定位

**护盾 = LGF 的 `Ability`，本体状态托管在 `ShieldComponent` 上。**

| ❌ 不是 | ✅ 是 |
|---|---|
| 角色属性（不挂 `attribute_set`） | 一组带 `ShieldComponent` 的 ability |
| 独立 Actor | 挂在受保护者 `AbilitySet` 上 |
| 普通受伤前监听器（`PreEventConfig`） | 项目层独立的"护盾结算"步骤 |
| 单个总盾值 | 多个独立护盾实例，统一结算 |

每个角色身上可以同时有多个护盾实例（亚巴顿盾 + 护盾符 + 物理盾...），各自独立存活、统一结算。

---

## 📐 数据结构

```
Ability (例如 ward_buff)
  ├── ShieldComponent              ← 项目层新增 (状态 + 行为)
  │     数据：current / capacity / damage_types / priority
  │           on_break / on_expire / stacking_policy(字段占位)
  │     行为：consume(amount, damage_type) → (absorbed, broken)
  └── TimeDurationComponent        ← LGF 标准，管 duration
```

`ShieldComponent` 有可变状态（`current`），与 LGF "组件随能力实例创建、可有状态" 的范式一致；这与 `Action` 的无状态规则不冲突。

---

## 🔄 在伤害流程中的位置

护盾结算是项目层 `apply_damage` 流程中**夹在「修正后伤害确定」和「扣血」之间**的一步：

> pre_event 修正（易伤 / 减伤）→ 命中特殊修正（暴击）→ **护盾结算（吸收 + 记录消耗）** → 扣血（按穿透后的 `actual_life_damage`）→ 破裂回调 `on_break` → 死亡检测 / `remove_actor` → post_event（反伤 / 吸血在这里读 `actual_life_damage` 触发）

两条**对护盾系统不可妥协**的顺序约束：

1. **护盾结算必须在扣血之前** — 否则没有"吸收"语义可言。
2. **`on_break` 回调必须在 `remove_actor` 之前** — 否则像 Aphotic 这类"破裂时 AoE 爆炸"的护盾，回调时 owner actor 已被移除，拿不到位置 / 状态 / ability 上下文。

完整 9 步流程图、damage event schema 各字段「该读哪个」对照表、未来扩展点 → 见 [damage-pipeline.md](damage-pipeline.md)。

**到期不在伤害流程里** — `on_expire`（duration 到期）由 `TimeDurationComponent` / ability 生命周期驱动，**不出现在 `consumption_records` 里**。详见下面 [🕐 护盾到期路径](#-护盾到期路径)。

---

## 🕐 护盾到期路径

**到期不属于伤害流程**，由 ability 生命周期驱动：

```
TimeDurationComponent 到期
  ↓
ability 触发 expire / on_remove
  ↓
ShieldComponent 读取自身 on_expire 回调
  ↓
on_expire(remaining_capacity) → push 新事件（如果有定义）
  ↓
ability 从 AbilitySet 移除
```

**职责划分**：
- `consumption_records[]` 只记录**因伤害而消耗的护盾** — 字段只有 `broken`，没有 `expired`
- `on_expire` 触发完全在 ability lifecycle 路径上，与 `apply_damage` 解耦
- 实现位置：`ShieldComponent` 实现 LGF 的组件 `on_remove` 钩子（或监听 ability 的 expire 信号），在那里调用 `on_expire`

---

## 🔢 消耗顺序（确定性 / Deterministic）

```
ShieldResolver.resolve(actor, damage, damage_type):
  1. 取出 actor 所有带 ShieldComponent 的 ability
  2. 过滤：damage_type 必须 in shield.damage_types     ← 硬过滤
  3. 排序（稳定）：
       priority         降序        ← 设计师显式控制
       grant_index      降序        ← LIFO，后获得先扣
       ability.id       升序        ← 字典序兜底（determinism）
  4. 逐个 consume，直到 damage 归零或全部用完
  5. 返回 (life_damage, consumption_records)
```

`grant_index` = ability 在 `AbilitySet.get_abilities()` 数组中的下标。授予时追加，所以下标 = 获得顺序。

---

## 🔒 4 条硬约束

1. **`ShieldResolver` 无副作用事件** — 它会**提交 `ShieldComponent.current` 变更**（这是它的职责），但不 push 事件、不扣 `actor.hp`、不触发 `on_break`/`on_expire` 回调。这些副作用由调用方（`apply_damage`）按流程顺序触发
2. **破裂行为只能 push 新事件** — 不能回写本次伤害事件（避免亚巴顿爆炸反向影响打破它的那次伤害）
3. **完全吸收仍发 damage 事件** — 但 `actual_life_damage = 0`，回放/表演层需要看到吸收
4. **on-damage-taken 反应（反伤/吸血）默认看 `actual_life_damage > 0`** — 默认不响应纯吸收

---

## 📦 叠加策略

`stacking_policy` 字段在 `ShieldComponent` 上**先占位、不全部实现**：

| 策略 | 描述 | V1 |
|---|---|---|
| `independent` | 每次施放产生新护盾 ability 实例，参与排序消耗 | ✅ V1 唯一实现 |
| `refresh` | 旧盾还在就刷新 duration（Shield Rune 风格） | V2 |
| `add` | 容量累加到旧盾上 | V2 |
| `replace` | 旧盾立即作废，换新盾 | V2 |
| `burst_then_replace` | 旧盾立即触发 `on_break`，再换新盾（Aphotic 风格） | V2 |

**职责划分**：叠加策略由 `ApplyShieldAction` 在授予前查询已有同类护盾时处理，**不归 `ShieldResolver` 管**（resolver 只管"已有护盾怎么消耗"）。

---

## 📁 文件边界

### 🆕 新增（项目层 hex-atb-battle）

```
addons/logic-game-framework/example/hex-atb-battle/
  components/
    shield_component.gd
    shield_component_config.gd
  shields/
    shield_resolver.gd                ← 项目层纯函数
  skills/
    ward.gd                           ← V1 首个使用者
  actions/
    apply_shield_action.gd
```

### ✏️ 修改

| 文件 | 改动 |
|---|---|
| `addons/.../hex-atb-battle/utils/hex_battle_damage_utils.gd` | `apply_damage` 插入 `ShieldResolver` 调用 |
| `addons/.../hex-atb-battle-core/events/battle_events.gd` | damage event schema 加 `shield_absorbed` / `actual_life_damage` / `consumption_records[]`；定义 `shield_broken` 事件（伤害打破时）。`shield_expired` 事件由到期路径决定是否需要，可复用 LGF 既有 `ability_expired` 类标准事件 |
| `addons/.../hex-atb-battle/skills/thorn.gd` | 过滤条件加 `actual_life_damage > 0`（否则全吸收时仍触发反伤，语义错误） |

### 🧪 测试

```
tests/skill_scenarios/
  shield_basic_absorb_scenario.gd        ← 吸收 + 反伤对偶（部分吸收触发反伤 / 全吸收不反伤）
  shield_on_grant_passive_scenario.gd    ← "获得护盾时" 被动（监听 LGF 现有 ability granted 事件 + 过滤 ShieldComponent；具体事件名以 LGF 接口为准）
  shield_priority_order_scenario.gd      ← 类型过滤 + priority + LIFO + 字典序
```

### ❌ 不碰

- `addons/.../core/`（LGF 框架层）
- `addons/.../hex-atb-battle-frontend/`（表演层）
- `attribute system`、`tag system`

---

## ✅ 实现顺序（已完成）

```
1. ✅ components/shield_component.gd + shield_component_config.gd
2. ✅ utils/hex_battle_shield_resolver.gd（纯函数 + 排序规则）
3. ✅ hex-atb-battle-core/events/battle_events.gd 扩 damage event schema + 定义 shield_broken
4. ✅ utils/hex_battle_damage_utils.gd::apply_damage 插入 resolver 调用 + on_break 在 remove_actor 前触发
5. ✅ skills/thorn.gd 加 actual_life_damage > 0 过滤
6. ✅ actions/apply_shield_action.gd
7. ✅ buffs/ward_buff.gd + skills/ward.gd（V1 independent 策略）+ skills/all_skills.gd 注册 WARD_TIMELINE
8. ✅ tests/skill_scenarios/shield_{basic_absorb, full_absorb_no_thorns, priority_order}_scenario.gd
9. ✅ Codex 审查后修复（P1/P2/P3）：
   - frontend: visualizers/damage_visualizer.gd 飘字/血条/闪白按 actual_life_damage 走，额外飘 "护盾 -N"
   - scenario_assert_context.gd: total_damage_to 语义改为「实际生命伤害」(actual_life_damage)，
     新增 total_modified_damage_to / total_shield_absorbed_for
   - apply_damage: on_break 回调返回 Array[Dictionary] 时并入 ActionResult.all_events
```

### 落地踩坑（供未来类似工作参考）

- **新 .gd 文件 Godot 不会自动索引**：跑测试前必须 `godot --headless --path . --import`，否则 `class_name` 不进 `.godot/global_script_class_cache.cfg`，运行时报 "Identifier XXX not declared"。新增 .gd 都要走一次 reimport。
- **类型注解的循环依赖**：`ShieldComponent._init(config: ShieldComponentConfig)` 与 `ShieldComponentConfig.create_component()` 内部 `ShieldComponent.new(self)` 互相引用 —— GDScript 在 reimport 后能解决，但 LSP 启动期会暂时报错，等编辑器索引完即消失。同 LGF 的 `PreEventComponent` / `PreEventConfig` 一致，无需额外处理。

### V1 没做的测试

`shield_on_grant_passive_scenario.gd`（监听 ability granted 触发被动）暂未写 —— 需要为测试单独造一个 listener ability 才能验，且 V1 没有真实用例，留到 V2 第一个用到 "获得护盾时" 语义的被动技能落地时一并写。

---

## 🛣️ V2+ 路线图

按优先级排序：

### 🟠 P1 — 短期内可能想做

- [ ] **Aphotic Ward**（破裂时 AoE 伤害）— 验证 `on_break` 回调机制
- [ ] **Shield Rune**（按 max HP 计算 + `refresh` 叠加策略）
- [ ] **物理盾 / 魔法盾**（具体技能配置 + `damage_types` 过滤）

### 🟡 P2 — 机制扩展

- [ ] **`stacking_policy` 全套实现**（`refresh / add / replace / burst_then_replace`）
- [ ] **次数盾**（按命中次数而非数值吸收）→ 走子类化 `HitCountShieldComponent extends ShieldComponent`，override `consume()`
- [ ] **"护盾被打也想响应"的反伤扩展** — 给 `thorn` 类 ability 一个开关：`react_to_shield_absorb: bool`

### 🔵 P3 — 长期演化

- [ ] **把"结算位置 + 消耗记录"上提到 LGF 框架层** — 触发条件：当格挡/招架/转伤/分摊都重复同一个"`apply_damage` 中间一步 + 消耗记录"模式时，证明这是通用能力，再上提。届时考虑给 `MutableEvent` 加 `metadata: Dictionary` 通道

---

## 🧠 设计决策记录

### Q: 为什么护盾不走 `PreEventConfig` 减伤？

**A:** 三个限制使其无法承载完整护盾系统：

1. **顺序不可控** — `MutableEvent` 强制 `SET → ADD → MULTIPLY`。护盾若用 `Modification.add(damage, -absorbed)`，会被后续 MULTIPLY 重新放大，语义变成"先挡再易伤"。
2. **没有消耗记录通道** — `MutableEvent` 只有 `original / _modifications / cancelled`，没有通用 metadata。`PreHandler` 之间也没有 priority。
3. **无法表达破裂触发** — 多个 PreHandler 并行注册，无法做"统一结算后逐个触发 on_break"。

### Q: 为什么不造 `ShieldContainer`？

**A:** `AbilitySet` 已经是容器。护盾 = ability，所以 `actor.ability_set.get_abilities()` 过滤带 `ShieldComponent` 的就是护盾集合。造独立容器会让护盾脱离 LGF 一等公民地位 —— 失去 `ability_added` 事件、`TimeDurationComponent` 复用、ability 生命周期钩子等。

### Q: 为什么 `ShieldComponent` 是具体类而非虚类？

**A:** 与 LGF 现有 `AbilityComponent` 体系对齐 —— `PreEventComponent` / `TimeDurationComponent` / `StatModifierComponent` 都是具体类 + 配置驱动。90% 的护盾变体（Aphotic / Rune / 物理盾 / 魔法盾）通过 **配置 + 回调** 即可表达。只有真正吸收逻辑不一样的（次数盾）才继承。**先具体后子类化**，不预先造抽象层。

### Q: 为什么不改 LGF 框架层？

**A:** 护盾是 hex-atb-battle 这个示例的规则，不是所有用 LGF 的游戏都需要的根能力。先在项目层证明它，等格挡/招架/转伤都重复同一个"结算位置 + 消耗记录"模式时，再有证据上提到框架层（V3 路线）。这比"先建框架抽象、再找用例"更稳。

### Q: 为什么破裂行为不能回写本次伤害？

**A:** 因果链应是"本次伤害 → 护盾破 → 新事件（爆炸/治疗/反伤）"，不是"护盾破回过头改本次伤害"。否则会出现亚巴顿盾爆炸反向放大打破它的那次攻击的诡异语义。新事件走 `EventProcessor.push` 标准通道，由它自己再走完整流程。

### Q: 为什么完全吸收仍发 damage 事件？

**A:** 回放和表演层需要看到"护盾吸收"这件事（VFX、伤害飘字"ABSORBED"等）。但反伤/吸血等 on-damage-taken 反应默认不应响应纯吸收，所以引入 `actual_life_damage > 0` 过滤。

---

## ⚠️ 已知限制 / 待拍板

| 项 | 描述 | 触发拍板时机 |
|---|---|---|
| **actor 死亡导致 ability 移除时，护盾 `on_expire` 是否触发** | actor 死亡 → ability 整体清理 → 残余护盾的 `on_expire` 要不要走？这是 ability lifecycle 的通用问题，不是护盾特有 | V1 基础 Ward 没有 `on_expire`，不影响。做 Aphotic 或新增带 `on_expire` 的护盾时拍 |
| **damage event `damage` 字段语义已变更** | 现在是「修正后但未扣护盾」的总伤害。**所有读 damage event 的消费者**（反伤/吸血/受击 buff filter、frontend visualizer、统计 helper、外部 replay 工具）都要意识到：HP 实际损失 = `actual_life_damage`。`thorn.gd` / `damage_visualizer.gd` / `ScenarioAssertContext.total_damage_to` 已就位，新增同类消费者要同步对齐 | 新增任何读 damage event 的代码时 |
| **`stacking_policy` 仅占位** | V1 重复施放只能产生独立护盾实例（`independent`）。Refresher / Aphotic 风格的"刷新或替换"语义 V1 不支持 | 实现 Shield Rune / Aphotic 时 |
| **`damage_types` 取值集合** | 当前未明确 `damage_type` 的标准取值（"physical" / "magical" / "pure" / "true"...）。需要在 `battle_events.gd` 里定义统一枚举 | 实现物理盾/魔法盾时 |

---

## 📚 相关参考

- LGF 架构总览：[`addons/logic-game-framework/CLAUDE.md`](../../addons/logic-game-framework/CLAUDE.md)
- 事件系统：[`addons/logic-game-framework/core/events/`](../../addons/logic-game-framework/core/events/)
- 现有 buff ability 范式：[`addons/.../hex-atb-battle/skills/poison.gd`](../../addons/logic-game-framework/example/hex-atb-battle/skills/poison.gd)
- 反伤 ability：[`addons/.../hex-atb-battle/skills/thorn.gd`](../../addons/logic-game-framework/example/hex-atb-battle/skills/thorn.gd)
- 伤害集中点：[`addons/.../hex-atb-battle/utils/hex_battle_damage_utils.gd`](../../addons/logic-game-framework/example/hex-atb-battle/utils/hex_battle_damage_utils.gd)
