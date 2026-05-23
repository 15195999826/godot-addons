# 5 · Summon Totem #16（spike + TDD 门，非直接 impl）

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 上一阶段：[phase-04-demon-form.md](phase-04-demon-form.md)


**设计卡**：召唤图腾 actor，低 HP、不移动、每 3s 攻击最近敌人、TTL 15s 或被打死。

## 5.1 为什么是 spike 门

3 个框架级未知，未查清不能写 impl 方案：

1. **战斗中途 add_actor 能否被 ATB/AI 驱动**：procedure 只 iter `get_alive_characters()`（CharacterActor）+ `ai_strategy.decide()`。图腾若非 CharacterActor 不会自动行动。
2. **中途新 actor 的 recording 完整性**：`setup_recording` 在 actor 何时挂？战斗中途加入的 actor 录像是否完整、事件顺序和关键 payload 是否稳定。
3. **TTL → remove_actor 通路**：`TimeDurationConfig` 只让 ability expire，不 remove actor 本体。spike 先验证 ability lifecycle 自删是否可行；正式实现已收敛为 hex actor-level lifetime 到期后走 world `remove_actor()`，不抽 `RemoveActorAction`。

本技能必须用 TDD 推进。它不是普通数值技能，而是中途 actor 生命周期能力：spawn、grid occupancy、AI/ATB 驱动、TTL remove、replay/recording 都可能在不同层失败。实现前先写失败测试，测试明确红了再补最小框架能力；禁止先写 `SummonTotemAction` 再靠手测补漏。

## 5.2 TDD / Spike 计划（先红后绿，断言框架原语而非图腾行为）

**spike scene**：`tests/battle/smoke_summon_spike.tscn`（优先写成可保留的回归；若实现路线改变，再拆成正式 scenario / core tests）

| TDD 阶段 | 先写的失败断言 | 绿灯后允许做什么 |
|---|---|
| 1. spawn 原语 | 战斗第 N tick spawn actor 后不崩；grid 占位生效；无法占位时失败结果可观测 | 抽 `SpawnActorAction` 或保留技能私有 spawn routine 的依据 |
| 2. actor 驱动 | 中途加入 CharacterActor 后进入 alive actors；能被 ATB/AI/ability tick 驱动并产生一次行动或 periodic 攻击 | 决定路线 A 是否成立 |
| 3. replay/recording | 新 actor 的 spawn/grant/damage/remove 事件进入 replay；同 seed 两次事件可观察顺序与关键 payload 一致 | 允许把中途 add/remove 纳入正式技能 |
| 4. remove/TTL | TTL 到期后 remove actor；grid 释放；alive actors 不再包含；无悬挂引用导致后续 tick 报错 | 决定 actor-level lifetime / remove cleanup 通路 |
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
- Actor-level lifetime（正式 Totem 采用；spike 的 `TimeDurationConfig + NoInstance.on_remove` 仅保留为 proof）
- `HexBattleSpawnActorAction`（hex 应用层 Primitive Action；Totem / Fire Tile 共用，不上提 LGF core）
- `ActorSummonedEvent` 暂不引入；demo/replay 先使用 `actorSpawned` + `abilityGranted`
- `RemoveActorAction` 暂不引入；remove 由 death / actor-level lifetime / world API 负责
- 图腾 auto-attack ability（优先复用 Strike / DamageAction；若需要特殊 AI 行为，放极薄触发层，不新增完整 AI strategy 框架）

## 5.4 表演层（spike 后定）

新 unit visualizer（图腾形态）可能需进 `default_registry`；召唤视觉先消费 `actorSpawned`。
spike 不接表演层（纯框架探针）。

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
| 1 spawn | 中途 `GameplayInstance.add_actor` + `UGridMap.model.place_occupant` 后 actor 进 `get_alive_actor_ids` + grid 占位 | ✅ | 框架原语完全支持 mid-battle 加新 actor；不需要 LGF core SpawnActor primitive，但正式 Totem / Fire Tile 会抽 hex 层 `HexBattleSpawnActorAction`。 |
| 2 actor 驱动 | 中途加 CharacterActor 后, 由调用方手动驱动 `ability_set.tick + tick_executions`, periodic loop timeline (Demon Form 3s) 在 7s 内 tick 2 次 | ✅ | CharacterActor 一旦加进 instance, ATB/AI/ability tick 链路天然可走;关键是 caller 必须显式 tick (与 procedure / harness 一致)。 |
| 3 replay/recording | 中途 grant 的 ability 产生的 `abilityGranted` + `abilityStacksChanged` event 进入 `BattleRecorder.timeline` | ✅ | 关键是 grant 后立即 `recorder.record_frame(-1, event_collector.flush())`, 然后每 tick `record_frame(i, flush())` — event-order consistent (per phase 文档放松到 "可观察顺序稳定"); 不要求 byte-level identical。 |
| 4a manual remove | 模拟 TTL 到期后显式 `HexWorldGameplayInstance.remove_actor(id)`, actor / grid 都干净 | ✅ | hex world override 已集中清 grid occupancy / reservation；不需要调用方先手动 `grid.remove_occupant`。 |
| 4b TTL lifecycle | `TimeDurationConfig` expire 后触发 `NoInstanceConfig.on_remove_actions` 内嵌 SkillLocalAction, 自清 actor / grid | ✅ | ability lifecycle 自删可行；但正式 Totem 改用 actor-level lifetime, 不把 actor TTL 建模为 Ability。 |
| 5 图腾行为 | placeholder, 留正式 impl | ⏭️ | spike 不实现 auto-attack / 低 HP / 不移动 / 死亡消失，且 placeholder 不计入 PASS。 |

### 路线决定: **路线 A (低 HP CharacterActor)**

依据:

1. **阶段 2 已验证 CharacterActor 中途加入可被驱动**。图腾若是低 HP / 不主动移动的
   CharacterActor 子类配置 (例新增 TOTEM character class + 简化 ai_strategy 永远 idle
   或 attack_nearest), 复用整套 ATB / ability_set / DamageAction / DeathEvent 链路。
   不需要为图腾新建一套 actor 子树。
2. **阶段 3 证明 recording 完整**, CharacterActor 子类天然走 hex `positionFormats="hex"`
   record, replay 不需要额外 schema。
3. **阶段 4a/4b 证明 remove_actor 与 lifecycle cleanup 安全**: 显式 remove 走
   `HexWorldGameplayInstance.remove_actor` 即可清 actor + grid；ability lifecycle 自删已被
   spike 证明可行, 但正式图腾把 15s 存活时间放到 hex actor-level lifetime。死亡走现有
   `check_death` 流程；正式图腾仍需补死亡消失 scenario。
4. **路线 B (SummonActor 子类 + periodic auto-attack timeline) 的额外成本不划算**:
   - SummonActor 子类要重新挂 `ability_set` / `attribute_set` / collision_profile
   - periodic auto-attack timeline 绕 ATB, 与现有"ATB 是攻击节拍统一入口"违和
   - replay 子类 actor record 字段需要额外 schema migration
   - 拒绝路线 B 也避免引入 framework 级 SpawnActorAction / RemoveActorAction primitive；
     正式 Totem 只引入 hex 应用层 `HexBattleSpawnActorAction`

### 正式 impl 待办 (留给后续 /goal)

执行顺序：Summon Totem 正式实现必须先于 Fire Tile / 地形伤害格。原因是 Fire Tile 也会复用
"战斗中途生成 actor + actor lifetime + replay/lifecycle" 这组 board-object 原语；先把占格召唤物打通,
再讨论 passable overlay hazard。

#### HexBattleSpawnActorAction

正式实现 Totem 时同步抽 hex 应用层 public primitive：`HexBattleSpawnActorAction`。
它不是 LGF core primitive；它依赖 `HexBattleActor` / `HexCoord` / hex grid / team / placement,
因此归属 `example/hex-atb-battle/logic/actions/`。

职责边界：

- 只负责“创建一个 `HexBattleActor` 并接入 hex battle runtime”。
- 不知道 Totem / Fire Tile 的业务语义。
- 不执行 damage / hazard tick / AI 决策。
- 不移除 actor；remove 仍由 death、actor-level lifetime、world API 负责。
- 不新增 `ActorSummonedEvent`；先复用 `actorSpawned` / `abilityGranted` replay 事件。

建议配置形态：

```gdscript
HexBattleSpawnActorAction.new(
	coord_resolver,
	actor_factory,
	placement_mode,
	team_policy,
	lifetime_resolver,
	granted_ability_factories
)
```

参数语义：

- `actor_factory`：执行时创建 actor。Totem 创建 `CharacterActor(TOTEM)`；Fire Tile 创建
  `EnvironmentActor("fire_tile")`。
- `placement_mode`：
  - `OCCUPANT`：占格，要求目标格存在且未被占用；Totem 用。
  - `OVERLAY`：不写 `grid.occupant`，只设置 `actor.hex_position` 并注册到 world；Fire Tile 用。
    `OVERLAY` V1 不做同格唯一性检查，同一 coord 可以存在多个 environment actor；Fire Tile 因此是并存叠加，不 refresh、不 replace、不 merge。
  - 该参数执行后必须写入 `actor.placement_mode`，因为 remove 时 Action config 已不可依赖。
- `team_policy`：
  - `INHERIT_SOURCE`：继承施法者 team；Totem 用。
  - `NONE` / `NEUTRAL`：无阵营或中立；Fire Tile 可能用。
- `lifetime_resolver`：设置 actor-level lifetime；不是 Ability duration。
- `granted_ability_factories`：actor `add_actor()` 后才 grant，因为此时 owner id 已分配；
  grant 时传入 `source_actor_id`，保证伤害归因和 replay 可追溯。

Fire Tile 的归因例外：Fire Tile 自己是造成 pulse damage 的 actor。Fire Tile ability 的 owner 是
Fire Tile actor，因此 pulse damage 的 `DamageEvent.source_actor_id` 应为 `fire_tile_actor.id`。
原 caster / source skill 只作为 Fire Tile actor 的 `creator_actor_id` / `source_skill_id` metadata
保存，供 replay / debug / tooltip 追溯；combat attribution 不回填到 creator。

Runtime 接入不要散落在 Action 内部硬改各处数组。应补一个 hex runtime API / hook，
例如：

```gdscript
HexBattleProcedure.register_spawned_actor(actor, options)
```

或由 `HexWorldGameplayInstance.spawn_actor_from_action(actor, options)` 统一转发。这个入口负责：

- 注册到 world：`add_actor(actor)`。
- 按 `placement_mode` 处理 grid occupant / overlay，并把 mode 写到 `HexBattleActor.placement_mode`。
- CharacterActor 按 team 加入正式 procedure actor source / team list，否则不会被 ATB / AI tick。
- recording 开启时调用 recorder 注册 actor，保证 `actorSpawned` 与后续 ability / tag / attribute
  变化进入 replay。
- logger / in_combat tag / participant ids 的同步。
- 失败时 rollback：如果 placement 或 runtime registration 失败，不能留下半注册 actor。

#### placement_mode 与 remove cleanup

`placement_mode` 归属 `HexBattleActor`，不是 `SpawnActorAction` 的临时状态。它表达 actor 当前如何接入 hex grid：

```gdscript
enum PlacementMode {
	UNPLACED,
	OCCUPANT,
	OVERLAY,
}
```

建议 `HexBattleActor` 默认 `placement_mode = UNPLACED`。所有新放置路径都必须走 world placement API：

```gdscript
place_actor(actor, coord, PlacementMode.OCCUPANT)
place_actor(actor, coord, PlacementMode.OVERLAY)
```

`HexWorldGameplayInstance.remove_actor()` 按 `actor.placement_mode` switch 清理：

- `OCCUPANT`：如果 `grid.get_occupant(actor.hex_position) == actor`，再 `grid.remove_occupant(actor.hex_position)`；同时清理由该 actor 持有的 grid reservation。
- `OVERLAY`：只清 overlay registration，不碰 `grid.occupant`。
- `UNPLACED` / 旧路径缺 metadata：不按 coord 强删 occupant；最多走 identity-guard fallback。

Fire Tile 带来的额外约束：如果 `OVERLAY` actor 与 character 共格，overlay 到期 remove 绝不能调用
`grid.remove_occupant(coord)`，否则会误删站在同格的 character occupant。

同格多个 `OVERLAY` actor 也必须安全：移除一个 environment actor 只能移除自己的 world registration /
overlay registration，不能影响同 coord 的其它 environment actor。

#### EnvironmentActor runtime tick

Fire Tile 如果实现为 `EnvironmentActor` 上的 ability / timeline，正式 battle procedure 必须 tick 所有
`HexBattleActor` 的 ability runtime，而不是只 tick `CharacterActor`。推荐拆分：

- 所有 `HexBattleActor`：`ability_set.tick()` + `ability_set.tick_executions()`。
- alive `CharacterActor`：ATB 累积、AI 决策、主动行动启动。

这样 Fire Tile / future aura / trap 可以作为 EnvironmentActor 自己推进 timeline，同时不会让 environment
进入 team victory、ATB 或 AI 行动语义。

#### Fire Tile damage pipeline

Fire Tile 不走“环境伤害跳过反应”的特殊规则。它是高 HP 的普通 `EnvironmentActor`：

- pulse damage 正常走 pre-damage、shield、damage event、death event、post-damage。
- 目标有 Thorn / post-damage 反应时，反伤 source 是 Fire Tile actor，Fire Tile 正常扣 HP。
- Fire Tile HP 归零时按普通 death 处理；死亡 cleanup 仍按 `placement_mode = OVERLAY`，不能清同格 occupant。
- 正常情况下 Fire Tile 大概率不会被打死，主要由 actor-level lifetime 到期移除。

- 新增 `HexBattleClassConfig.CharacterClass.TOTEM`。Totem 仍走 `CharacterActor` +
  `HexBattleCharacterAttributeSet`, 但配置应表达召唤物语义：低 hp、不移动、可被攻击。
  - `speed` 不能是 0：路线 A 复用 ATB / AI 驱动, 0 speed 会导致永远不行动。
  - `atk` 可以为 0, 如果 `HexBattleTotemAttack` 使用固定伤害 resolver；也可以给低 atk 并复用 atk resolver。
- 新增 hex actor-level lifetime, 不把 15s 存活时间建模为 `HexBattleTotemLifetime` Ability。
  - 建议放在 `HexBattleActor` 基类: `set_lifetime(duration_ms, reason)`,
    `has_lifetime()`, `tick_lifetime(dt) -> expired`。
  - 由 hex battle procedure / world runtime 每 tick 统一处理到期并调用 `remove_actor()`。
  - `TimeDurationConfig + NoInstance.on_remove` spike 结论只证明 ability lifecycle 自删可行；
    正式 Totem 不采用该路径, 避免把 actor 生命周期伪装成 buff / ability 生命周期。
- 新增 `summon_totem.gd` (active skill): CAST 阶段计算 spawn coord (默认 caster 前一格),
  HIT 阶段使用 `HexBattleSpawnActorAction`：
  - `actor_factory = CharacterActor(TOTEM)`
  - `placement_mode = OCCUPANT`
  - `team_policy = INHERIT_SOURCE`
  - `lifetime = 15000ms`
  - `granted_ability_factories = [HexBattleTotemAttack]`
  - 不调用普通 `CharacterActor.equip_abilities()`；避免默认注入 `move` / class passive / class skill。
- `HexBattleTotemAttack` 是普通 active ability：
  - cadence 用 cooldown / ATB 表达 3000ms, 不用 `GRANTED_SELF + periodic timeline` 绕过 ATB。
  - "最近敌人"优先放进 ability 的 target selection / resolver, 不写死在 AI strategy。
  - timeline HIT 阶段走 `HexBattleDamageAction`。
- Totem 自动行为 V1 只保留很薄的触发层：
  - 如果复用 `CharacterActor.ai_strategy`, 新增 `TotemAIStrategy` 也只负责在 attack ready 时触发
    `HexBattleTotemAttack`; 目标选择交给 ability / target selector。
  - 不在本阶段建立完整 AI strategy 框架。
- 中途加入的 Totem 必须进入正式 procedure 的 actor source。
  - 当前 `HexBattleProcedure` 遍历 `left_team / right_team`；spawn 后若不进入对应队列,
    它不会被 ATB / AI 驱动。
  - 可选修法：spawn 时加入对应 team list, 或把 procedure actor source 改为 world 查询。
- 新增 totem 视觉 (unit visualizer 注册 TOTEM class)。
- 正式 scenario: 召唤 + 攻击最近敌人 + 3s cadence + 15s lifetime 到期消失 + 死亡消失。

### 框架原语清单 (本 spike 不动)

| 原语 | 状态 | 备注 |
|---|---|---|
| `instance.add_actor / remove_actor` | ✅ 现成 | 已用,无需新增 |
| `grid.place_occupant / remove_occupant` | ✅ 现成 | spawn 用 place; remove 由 `HexWorldGameplayInstance.remove_actor` 集中清 grid |
| `recorder.record_frame(frame, events)` | ✅ 现成 | 调用方手动驱动 |
| `event_collector.flush()` | ✅ 现成 | flush after grant / tick |
| `TimeDurationConfig + NoInstance.on_remove` | ✅ 现成 | spike 已验证 ability lifecycle 自清 actor/grid；正式 Totem 改用 actor-level lifetime |
| `HexBattleSpawnActorAction` primitive | ✅ 正式 Totem impl 引入 | hex 应用层 public primitive；Totem 用 `OCCUPANT`，Fire Tile 后续用 `OVERLAY` |
| `RemoveActorAction` primitive | ❌ 不引入 | remove 由 death / actor-level lifetime / world API 负责；不为对称性硬抽 |
| `ActorSummonedEvent` | ❌ 不引入 | abilityGranted + actorSpawned 已足够 demo/replay 区分召唤 |

### 待删除 / 后续清理

- `smoke_summon_spike.tscn` 是一次性 spike, 保留作回归 (验证 mid-battle 原语); 正式
  totem impl 完成后, 它仍有意义作 framework smoke。
- BuffVisualizer / StageCueVisualizer 接入图腾相关的 cue (per phase 文档 §5.4) 留给
  正式 impl PR。
