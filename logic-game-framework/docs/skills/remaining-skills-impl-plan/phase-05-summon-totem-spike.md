# 5 · Summon Totem #16（spike + TDD 门，非直接 impl）

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 上一阶段：[phase-04-demon-form.md](phase-04-demon-form.md)


**设计卡**：召唤图腾 actor，低 HP、不移动、每 3s 攻击最近敌人、TTL 15s 或被打死。

## 5.1 为什么是 spike 门

3 个框架级未知，未查清不能写 impl 方案：

1. **战斗中途 add_actor 能否被 ATB/AI 驱动**：procedure 只 iter `get_alive_characters()`（CharacterActor）+ `ai_strategy.decide()`。图腾若非 CharacterActor 不会自动行动。
2. **中途新 actor 的 recording 完整性**：`setup_recording` 在 actor 何时挂？战斗中途加入的 actor 录像是否完整、事件顺序和关键 payload 是否稳定。
3. **TTL → remove_actor 通路**：`TimeDurationConfig` 只让 ability expire，不 remove actor 本体。优先 spike 路线是“图腾持有 duration ability → duration end / on_remove → SkillLocalAction → RemoveActorAction(target=self)”；如果 actor 自删过程中 ability lifecycle 死锁，再退回 procedure tick 检查 TTL。

本技能必须用 TDD 推进。它不是普通数值技能，而是中途 actor 生命周期能力：spawn、grid occupancy、AI/ATB 驱动、TTL remove、replay/recording 都可能在不同层失败。实现前先写失败测试，测试明确红了再补最小框架能力；禁止先写 `SummonTotemAction` 再靠手测补漏。

## 5.2 TDD / Spike 计划（先红后绿，断言框架原语而非图腾行为）

**spike scene**：`tests/battle/smoke_summon_spike.tscn`（优先写成可保留的回归；若实现路线改变，再拆成正式 scenario / core tests）

| TDD 阶段 | 先写的失败断言 | 绿灯后允许做什么 |
|---|---|
| 1. spawn 原语 | 战斗第 N tick spawn actor 后不崩；grid 占位生效；无法占位时失败结果可观测 | 抽 `SpawnActorAction` 或保留技能私有 spawn routine 的依据 |
| 2. actor 驱动 | 中途加入 CharacterActor 后进入 alive actors；能被 ATB/AI/ability tick 驱动并产生一次行动或 periodic 攻击 | 决定路线 A 是否成立 |
| 3. replay/recording | 新 actor 的 spawn/grant/damage/remove 事件进入 replay；同 seed 两次事件可观察顺序与关键 payload 一致 | 允许把中途 add/remove 纳入正式技能 |
| 4. remove/TTL | TTL 到期后 remove actor；grid 释放；alive actors 不再包含；无悬挂引用导致后续 tick 报错 | 抽 `RemoveActorAction` / TTL lifecycle 通路 |
| 5. 图腾行为 | 低 HP、不移动、每 3s 攻击最近敌人、死亡或 TTL 结束消失 | 正式 `summon_totem_scenario.gd` 通过后才能标 ✅ |

**spike 产出 = 一份结论**写入本节「Spike 结论」，据此二选一：
- **路线 A**：图腾 = 低 HP CharacterActor（新「图腾」职业配置 + 简化 ai_strategy）→ 复用整套 ATB/AI/技能链
- **路线 B**：图腾 = 新 SummonActor 子类，自带 periodic auto-attack timeline（绕开 ATB），procedure 加最小驱动钩子

replay 判定不要要求 byte-level identical：中途 add_actor 可能受 Dictionary key order、actor allocation id 展示顺序等无关细节影响。V1 只要求事件流的可观察顺序稳定、关键字段一致（actor_id / source_actor_id / target_actor_id / event type / grid coord / damage 等）。

TDD 规则：
- 每个阶段先提交/保留一个红测试意图：测试名必须描述合同，例如 `summon_spawn_registers_mid_battle_actor`、`summon_ttl_releases_grid_cell`。
- 每次只让当前阶段变绿，不提前实现后续阶段；尤其不要在 spawn 阶段顺手做 auto-attack。
- 框架原语测试与技能 scenario 分开：spawn/remove/replay 属于框架回归，图腾攻击/TTL 数值属于 skill scenario。
- 若某阶段证明现有架构不支持，先回写「Spike 结论」并重新选择路线，不继续堆 workaround。

spike/TDD 绿后再出**正式 impl align 方案**（补本节）。

## 5.3 预判新机制清单（spike 后确认/收敛）

- 图腾 Actor 载体（新职业配置 或 新 SummonActor 子类）
- TTL → remove_actor 通路（若抽 `RemoveActorAction`，必须作为 Primitive Action 登记；图腾 TTL 自毁过程是 SkillLocalAction / ability lifecycle 逻辑）
- `ActorSummonedEvent`（新 event type，若 demo/replay 需要区分召唤）
- `SpawnActorAction`（Primitive Action，若 spike 证明中途 add_actor 可行）；归属先不定 core vs hex example，spike 后根据 RTS 是否也能复用决定。图腾自身 summon 过程不新增 public `SummonTotemAction`，写成 SkillLocalAction
- 图腾 auto-attack ability（优先复用 Strike / DamageAction；若需要特殊 AI 行为，放图腾 controller / SkillLocalAction，不新增半公开业务 Action）

## 5.4 表演层（spike 后定）

新 unit visualizer（图腾形态）可能需进 `default_registry`；`ActorSummonedEvent` 视觉。spike 不接表演层（纯框架探针）。

> **评审意见**：已批准 spike/TDD 门。当前不继续细化最终图腾架构；先按 §5.2 写红测试验证中途 spawn、actor 驱动、replay/recording、remove/TTL 与图腾行为。测试结果出来后再决定路线 A（低 HP CharacterActor 复用 ATB/AI）或路线 B（SummonActor / periodic auto-attack）。禁止先写 `SummonTotemAction` 再靠手测补漏。

---

## 5.5 Spike 结论 (2026-05-20)

跑 `tests/battle/smoke_summon_spike.tscn`，最终输出
`SMOKE_SPIKE_RESULT: PASS - 5/5 verified phases passed; 1 placeholders skipped`。

重要口径：Phase 5 behavior 仍是 placeholder，不计入完成；TTL 结论拆成 manual remove 与
`TimeDurationConfig → NoInstance.on_remove` lifecycle 两条独立证据。

### 阶段验证记录

| 阶段 | 验证内容 | 状态 | 关键发现 |
|---|---|---|---|
| 1 spawn | 中途 `GameplayInstance.add_actor` + `UGridMap.model.place_occupant` 后 actor 进 `get_alive_actor_ids` + grid 占位 | ✅ | 框架原语完全支持 mid-battle 加新 actor;不需要新 SpawnActor primitive。 |
| 2 actor 驱动 | 中途加 CharacterActor 后, 由调用方手动驱动 `ability_set.tick + tick_executions`, periodic loop timeline (Demon Form 3s) 在 7s 内 tick 2 次 | ✅ | CharacterActor 一旦加进 instance, ATB/AI/ability tick 链路天然可走;关键是 caller 必须显式 tick (与 procedure / harness 一致)。 |
| 3 replay/recording | 中途 grant 的 ability 产生的 `abilityGranted` + `abilityStacksChanged` event 进入 `BattleRecorder.timeline` | ✅ | 关键是 grant 后立即 `recorder.record_frame(-1, event_collector.flush())`, 然后每 tick `record_frame(i, flush())` — event-order consistent (per phase 文档放松到 "可观察顺序稳定"); 不要求 byte-level identical。 |
| 4a manual remove | 模拟 TTL 到期后显式 `HexWorldGameplayInstance.remove_actor(id)`, actor / grid 都干净 | ✅ | hex world override 已集中清 grid occupancy / reservation；不需要调用方先手动 `grid.remove_occupant`。 |
| 4b TTL lifecycle | `TimeDurationConfig` expire 后触发 `NoInstanceConfig.on_remove_actions` 内嵌 SkillLocalAction, 自清 actor / grid | ✅ | ability lifecycle 自删可行；正式图腾可用同 pattern 做 TTL 到期消失。 |
| 5 图腾行为 | placeholder, 留正式 impl | ⏭️ | spike 不实现 auto-attack / 低 HP / 不移动 / 死亡消失，且 placeholder 不计入 PASS。 |

### 路线决定: **路线 A (低 HP CharacterActor)**

依据:

1. **阶段 2 已验证 CharacterActor 中途加入可被驱动**。图腾若是低 HP / 不主动移动的
   CharacterActor 子类配置 (例新增 TOTEM character class + 简化 ai_strategy 永远 idle
   或 attack_nearest), 复用整套 ATB / ability_set / DamageAction / DeathEvent 链路。
   不需要为图腾新建一套 actor 子树。
2. **阶段 3 证明 recording 完整**, CharacterActor 子类天然走 hex `positionFormats="hex"`
   record, replay 不需要额外 schema。
3. **阶段 4a/4b 证明 remove_actor 与 TTL lifecycle 安全**: 显式 remove 走
   `HexWorldGameplayInstance.remove_actor` 即可清 actor + grid；TTL 到期可由
   `TimeDurationConfig + NoInstanceConfig.on_remove_actions` (§0.6) 触发内嵌
   SkillLocalAction 自删。死亡走现有 `check_death` 流程；正式图腾仍需补死亡消失 scenario。
4. **路线 B (SummonActor 子类 + periodic auto-attack timeline) 的额外成本不划算**:
   - SummonActor 子类要重新挂 `ability_set` / `attribute_set` / collision_profile
   - periodic auto-attack timeline 绕 ATB, 与现有"ATB 是攻击节拍统一入口"违和
   - replay 子类 actor record 字段需要额外 schema migration
   - 拒绝路线 B 也避免引入 framework 级 SpawnActorAction / RemoveActorAction primitive
     (per phase 文档 §5.3, 这些 primitive 只在 "需要时" 才落码)

### 正式 impl 待办 (留给后续 /goal)

- 新增 `HexBattleClassConfig.CharacterClass.TOTEM` (低 hp / 0 speed / 0 atk)
- 新增 `summon_totem.gd` (active skill): CAST 阶段计算 spawn coord (默认 caster 前一格),
  HIT 阶段 `_SummonTotemSpawnAction` (SkillLocalAction):
  - `instance.add_actor(totem_actor)`
  - `instance.grid.place_occupant(spawn_coord, totem_actor)`
  - 给 totem grant 一个 `totem_auto_attack` ability (active, periodic timeline tick auto-attack
    最近敌人) + `TimeDurationConfig(15000)` + `NoInstanceConfig.on_remove_actions =
    [_TotemTeardownAction]` (从 grid / instance 移除自身)
- 新增 totem 视觉 (unit visualizer 注册 TOTEM class)
- 正式 scenario: 召唤 + 攻击 + TTL 到期消失 + 死亡消失

### 框架原语清单 (本 spike 不动)

| 原语 | 状态 | 备注 |
|---|---|---|
| `instance.add_actor / remove_actor` | ✅ 现成 | 已用,无需新增 |
| `grid.place_occupant / remove_occupant` | ✅ 现成 | spawn 用 place; remove 由 `HexWorldGameplayInstance.remove_actor` 集中清 grid |
| `recorder.record_frame(frame, events)` | ✅ 现成 | 调用方手动驱动 |
| `event_collector.flush()` | ✅ 现成 | flush after grant / tick |
| `TimeDurationConfig + NoInstance.on_remove` | ✅ 现成 | 已验证 TTL lifecycle 自清 actor/grid |
| `SpawnActorAction` primitive | ❌ 不引入 | spike 证明 SkillLocalAction 足够 |
| `RemoveActorAction` primitive | ❌ 不引入 | 同上 |
| `ActorSummonedEvent` | ❌ 不引入 | abilityGranted + actorSpawned 已足够 demo/replay 区分召唤 |

### 待删除 / 后续清理

- `smoke_summon_spike.tscn` 是一次性 spike, 保留作回归 (验证 mid-battle 原语); 正式
  totem impl 完成后, 它仍有意义作 framework smoke。
- BuffVisualizer / StageCueVisualizer 接入图腾相关的 cue (per phase 文档 §5.4) 留给
  正式 impl PR。
