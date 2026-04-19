# Changelog

本文件记录 Logic Game Framework 的重要变更。格式参考 [Keep a Changelog](https://keepachangelog.com/)。

- **Added** — 新增能力
- **Changed** — 行为或 API 变化
- **Fixed** — Bug 修复
- **Removed** — 移除
- **Deprecated** — 即将废弃

对于有架构推理的重大变更，在 `docs/design-notes/` 下会有对应长文，行末以链接引用。

---

## [Unreleased] — 2026-04-20 阶段 1：WorldGameplayInstance + BattleProcedure 核心拆分

"世界 owns 战斗"架构第一步。把 HexBattle 身上的 instance(actor registry / grid / systems)与 procedure(ATB loop / teams / recorder)两条职责拆开,为后续 frontend 响应式 view + skill_preview 无缝展开战斗 + replay 格式 v3 奠基。阶段 1 只改 core / hex-atb-battle-core 层,调用端(`SkillPreviewBattle` / `main.tscn` / `scenes/Simulation.tscn` / scenario runner)通过 `HexBattle` 兼容门面不动一行。  
→ [design-notes/2026-04-19-world-as-single-instance.md](docs/design-notes/2026-04-19-world-as-single-instance.md)

### Added
- `WorldGameplayInstance extends GameplayInstance`(`core/entity/world_gameplay_instance.gd`):显式 mutation API `add_actor` / `remove_actor` / `configure_grid`,每个 emit 对应 signal(`actor_added` / `actor_removed` / `actor_position_changed` / `grid_configured` / `grid_cell_changed` / `battle_finished`);`start_battle(participants: Array[Actor])` 入口配合工厂钩子 `_create_battle_procedure`,`tick(dt)` 战斗优先,分帧吞吐由常数 `BATTLE_TICKS_PER_WORLD_FRAME`(默认 INT_MAX,一帧跑完)控制。Signal 只由显式 mutation 触发,战斗期间 actor 属性/tag 直接改内存,不发 signal(view 由 BattleAnimator 消费 event_timeline 回放)。
- `BattleProcedure extends RefCounted`(`core/entity/battle_procedure.gd`):抽象骨架。Public API `start` / `tick_once` / `should_end` / `finish`(被 WorldGI.tick 调用,不加下划线)。生命周期管理 in_combat tag(`_mark_in_combat` 虚钩子,基类 no-op,子类按 tag 容器实现)+ recorder(`_start_recorder` 虚钩子,默认走 events-only,子类可 override 回退旧版 `start_recording(actors,...)`)。
- `BattleRecorder.start_recording_events_only()`(`stdlib/replay/battle_recorder.gd`):仅记录 event timeline,不带 initial_actors / map_config。为新架构下"world 已常驻持有状态,录像只记过程事件"服务;旧版 `start_recording()` 保留未动,向后兼容。
- `HexBattleProcedure extends BattleProcedure`(`example/hex-atb-battle-core/hex_battle_procedure.gd`):hex 特化。承接原 `HexBattle.tick` 里的 ATB 累积、AI 决策、技能施放、投射物事件广播、MAX_TICKS 安全上限、胜负判定(某方全灭 → `mark_finished` + `_result` 设置为 `left_win / right_win / timeout`)。`_start_recorder` override 走旧版 `start_recording(actors, configs, map_config)` 路径,保留 initial_actors snapshot,阶段 1 不破坏 FrontendBattleReplayScene。
- `HexWorldGameplayInstance extends WorldGameplayInstance`(`example/hex-atb-battle-core/hex_world_gameplay_instance.gd`):actor registry + grid(UGridMap autoload 后端)+ system 管理。`configure_grid` 转发到 `UGridMap.configure`,保持 `grid` 字段指向 `UGridMap.model`。`remove_actor` 覆盖清理格子 occupant / reservation。`get_actor` 类型收窄 CharacterActor。提供 `get_alive_actor_ids` / `get_ability_set_for_actor` / `can_use_skill_on`。

### Changed
- `HexBattle extends HexWorldGameplayInstance`(`example/hex-atb-battle/hex_battle.gd`)从具体 instance 转为 thin 兼容门面。`start(config)` 走新架构:`configure_grid()` + 6 个 `add_actor()` + 队伍装备 + buff + timeline 注册 + `start_battle(...)` 创建 HexBattleProcedure。`tick(dt)` 委托父类 `WorldGI.tick`,由其驱动 procedure;每 tick 从 procedure 镜像 `tick_count`。战斗结束通过 `battle_finished` signal 回 `_on_battle_finished`,保留字段 `left_team / right_team / recorder / logger / _ended / _final_replay_data / MAX_TICKS`(= 10000)兼容旧调用。  
  原 HexBattle 上的 ATB loop / projectile 广播 / AI 决策 / `_check_battle_end` / `_start_actor_action` / `_create_action_use_event` 等全部迁至 HexBattleProcedure,不再在 HexBattle 里保留。

### 外部调用点兼容性
- `HexBattle.new().start(config)` / `battle.tick(dt)` / `battle.tick_count` / `battle.left_team` / `battle.right_team` / `battle.recorder` / `battle.logger` / `battle.get_replay_data()` / `battle.get_log_dir()` / `HexBattle.MAX_TICKS` / `battle.can_use_skill_on(...)` 全部保留;`main.tscn` / `SimulationManager` / `SkillPreviewBattle` / scenario runner / Web 桥接均未调整。
- 录像格式暂未变化(仍走旧版 `start_recording(actors, ...)` 保留 initial_actors),FrontendBattleReplayScene 不受影响。格式 v3(split `world_snapshot` + `event_timeline`)在阶段 4 再落地。

### 待处理(下一阶段)
- 阶段 2:`WorldView` 订阅 WorldGI signal 维护 unit view,`BattleAnimator` 消费 event_timeline 叠加飘字/特效。
- 阶段 3:`skill_preview` 切换到常驻 `SkillPreviewWorldGI` + `world.start_battle`,验证无缝展开战斗。
- 阶段 4:`BattleRecord` v3 格式落地 + `ReplayPlayer`(临时 WorldGI + WorldView)。
- 阶段 5:正式游戏场景(`main.tscn` / `Simulation.tscn` / Web 桥)切换到 WorldGI 承载。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS(Logic battle completed in 139 ticks) |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ (CrushingBlow / DeathrattleAoe / Fireball / HolyHeal / Poison / PreciseShot / Strike / SwiftStrike / Thorn) |

---

## [Unreleased] — 2026-04-19 后续：Ability 叠层一级化 + grant 事件化

围绕 Poison（DOT）技能实装,对外暴露两个 framework 缺口并一次性补齐:
(1) 叠层数据之前挂在 `StackComponent` 里,action 必须遍历 components 找它;
(2) `grant_ability` 只跑 local callback,buff 无法"挂上就自动 tick"。

### Added
- `Ability.stacks / max_stacks / overflow_policy` 提升为一级属性,配套 API `get_stacks() / is_stacks_full() / add_stacks(count) / remove_stacks(count) / set_stacks(count)`。溢出策略常量 `Ability.OVERFLOW_CAP / OVERFLOW_REFRESH / OVERFLOW_REJECT`。REFRESH 策略在叠层同时调用本 ability 上 `TimeDurationComponent.refresh()`(之前的 TODO 随一级化变成 3 行实现)。归 0 不自动 expire —— 清理由调用方决定(stacks 做纯计数器,与项目约定一致)。
- `AbilityConfig` 加 `initial_stacks / max_stacks / overflow_policy` 配置字段,`AbilityConfigBuilder.stacks(initial, max_val, policy)` 一级 API。不调默认 1/1/CAP(不可叠加 ability 调 add_stacks 一直 CAP 在 1,语义安全)。
- `AbilitySet.grant_ability(ability, game_state_provider = null)` 新增第二参数。传入后,grant 内部构造 `ABILITY_GRANTED_EVENT` 并同步调 `receive_event(event_dict, provider)` 广播给本 actor 的所有 ability。限本人 ability_set 广播,不走 event_processor 全局 post —— 跨 actor 监听由业务层自行决定。未传 provider(默认)则仅跑 local callback,保持与旧调用点兼容。
- `TriggerConfig.GRANTED_SELF` 静态 factory:匹配 `ABILITY_GRANTED_EVENT` 且 `event.actor_id == owner_id` 且 `event.ability.id == ctx.ability.id`(严格 instance id,同 actor 上多个同 config 实例不互激活)。典型用途:buff 挂 `ActivateInstanceConfig + GRANTED_SELF + loop timeline` 实现"挂上就自动 tick"(DOT/HOT/持续光环)。

### Removed
- `stdlib/components/stack_component.gd` 删除(对应 `stacks / max_stacks / overflow_policy` 已上移到 Ability 一级)。StackComponent 原本"组件化"但实际没有 hook/callback 也没有组件间交互接口,只是"一堆方法 + 状态"伪装成 component。外部 action 必须遍历 components 按 type 字符串找它才能读写层数,违反 component 封装。上移后:
  - Poison DOT 的 tick action 直接 `ctx.ability_ref.get_ability().get_stacks()`,零胶水
  - `Ability` 成为 stacks 的 facade(类比 `attribute_set.atk` / `actor.faction`),AbilityConfig 一级 API `.stacks(...)` 声明可叠加 ability

### Changed
- `Ability.serialize()` 增加 `stacks / maxStacks / overflowPolicy` 字段(replay/snapshot 携带层数信息)。

### 外部调用点同步
本次 addon 改动对现有业务代码**零调用点变更**:grant_ability 新参数默认 null;stacks 字段在所有未调 `.stacks(...)` 的 config 下默认 1/1/CAP,add/remove 对它们是 no-op。

### Added(上轮累积,保留)
- `Actor.is_pre_event_responsive() -> bool`（默认 true）虚函数。项目层子类覆盖以表达"此刻不响应 PreEvent 分发"的状态（如死亡、沉默、眩晕）。框架在 `PreEventComponent` handler 触发时查询，返回 false 则 handler 自动降级为 `pass_intent()`。  
  → [design-notes/2026-04-19-ability-lifecycle-decoupling.md](docs/design-notes/2026-04-19-ability-lifecycle-decoupling.md)
- `GameplayInstance.end()` 末尾自动调 `EventProcessor.remove_handlers_by_owner_id(actor.get_id())` 清理所有 actor 的 PreEvent handler 注册，避免跨战斗累积孤儿。不 revoke ability，保留 `_abilities` 数组以支持复活等语义。

### Changed
- `Ability` 删除 `_lifecycle_context` 字段。`apply_effects(ctx)` 不再缓存 context，`remove_effects()` 内部通过新方法 `_build_remove_context()` 从 `owner_actor_id` + `GameWorld.get_actor` 按需重建精简 context（仅 `ability`/`attribute_set`/`ability_set` 三字段，`event_processor`/`owner_actor_id` 在 on_remove 路径上无消费者）。幂等性改由 `_effects_active: bool` 哨兵维护。  
  → [design-notes/2026-04-19-ability-lifecycle-decoupling.md](docs/design-notes/2026-04-19-ability-lifecycle-decoupling.md)
- `PreEventComponent` 删除 `_lifecycle_context` 字段。注册到 `EventProcessor._pre_handlers` 的 handler/filter lambda **只捕获 String ID 和用户 Callable**，不捕获 `self`（PreEventComponent 实例）；触发时通过静态方法 `_rebuild_context` 按需构造。重建包含三层 null 短路：
  1. `GameWorld.get_actor` 找不到 actor → `pass_intent()`
  2. `actor.is_pre_event_responsive()` 返回 false → `pass_intent()`
  3. `ability_set.find_ability_by_id` 找不到 ability → `pass_intent()`  
  这同时修复了潜在的"死者/已 revoke ability 的幽灵 handler 响应"问题。
- `DynamicStatModifierComponent` 删除 `_context: AbilityLifecycleContext` 缓存字段。`on_remove` 从参数收 context（签名本来就如此）。
- `tests/core/events/pre_event_component_test.gd` 重写测试 setup，通过 `GameWorld.create_instance` + `instance.add_actor` 注册真实 MockActor（继承 `Actor`），匹配生产代码"handler 重建需要 actor 在 GameWorld 里"的契约。

## [Unreleased] — 2026-04-19 后续轮：结构性循环根治

上一轮识别但未修的循环 C、调研发现的循环 D/E 本轮一次性处理。统一原则：**子对象回指所属 container 禁止强引用，一律用 WeakRef 或 String id**（此约定之前只由 `Actor._instance_id: String` 体现）。

### Changed
- `AbilityComponent._ability: Ability` → `_ability_ref: WeakRef`（循环 C）。`initialize()` 调 `weakref(ability)`；`get_ability() -> Ability` 新增，返回 `_ability_ref.get_ref() as Ability`（可能 null，调用方需短路）。子类不再允许直接访问 `_ability` 字段。  
  → 修复：`Ability._components[]` ↔ `AbilityComponent._ability` 互持强引用，GDScript RefCounted 无循环 GC，Ability 对象图永不释放。
- `TimeDurationComponent._trigger_expiration()` 使用 `var ability := get_ability(); if ability != null: ability.expire(...)` 替代直接字段访问。唯一的 stdlib 外部消费点。
- `AbilityExecutionInstance` 删除 `_game_state_provider: Variant` 字段（循环 D）。`tick(dt, provider)` / `fire_sync_actions(actions, tag, provider)` / `_build_execution_context(tag, provider)` / `_execute_actions_for_tag(tag, actions, provider)` 全部添加 `provider: Variant` 参数。`Ability.tick_executions(dt, provider)` / `AbilitySet.tick_executions(dt, provider)` 同步加参。`Ability.activate_new_execution_instance` 保留 `p_game_state_provider` 参数**仅用于 activate 瞬间 `fire_sync_actions(__timeline_start__)`**，不再传入 `AbilityExecutionInstance.new`。  
  → 修复：execution instance 缓存 provider（= battle）形成 `battle → actor → ability_set → ability → _execution_instances → _game_state_provider = battle` 循环。遵循既有"provider 是调用时参数流"约定（对齐 `HandlerContext.game_state` / `ExecutionContext.game_state_provider` / `Component.on_event`）。
- `System._instance: GameplayInstance` → `_instance_ref: WeakRef`（循环 E）。`on_register(instance)` / `on_unregister()` / 新增 `get_instance() -> GameplayInstance` 短路返回。`get_logic_time()` 走 getter。`ProjectileSystem._process_pending_removal` 唯一外部消费点改为局部 `var instance := get_instance()`。  
  → 修复：`GameplayInstance._systems[]` ↔ `System._instance` 互持强引用。虽然 `GameplayInstance.end()` 会调 `system.on_unregister()` 主动解链，但这是纪律防御（依赖 end 被正确调用）；WeakRef 把它变成结构性防御。

### 外部调用点同步
- `hex_battle.gd:343`、`scripts/SkillPreviewBattle.gd:98`、`tests/smoke_strike.gd:71`：`actor.ability_set.tick_executions(dt)` → `.tick_executions(dt, self/battle)`。
- `addons/logic-game-framework/tests/core/abilities/ability_execution_instance_test.gd` / `ability_test.gd` / `timeline_loop_test.gd`：补齐新签名。

### 验证（基线 → 本轮后）
| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (59/59) | 25 leaked | **14** |
| `smoke_strike.tscn` | 41 leaked | **38** |
| `smoke_frontend_main.tscn` | 57 leaked | **46** |

### 待处理
- **smoke_strike 剩余 38 泄漏的根源**：shutdown 时 battle 在 `_end_all_instances` + `_instances.clear()` 后仍有 1 个真实外部强引用。不是循环 C/D/E。可能的候选：Action 里某个 Callable / event 字典持对象引用 / `UGridMap.place_occupant` 缓存的 occupant 路径。独立问题，需要新一轮 probe 定位。
- 本轮本该带来的数字下降受到此残余循环压制，因此循环 D 的实际收益被低估了（frontend 降 11 是循环 D 的真实体现，smoke_strike 未能暴露）。

## [Unreleased] — 2026-04-19 第三轮：pre_change 闭包循环根治（config 驱动跨属性 clamp）

承接上一轮「smoke_strike 剩余 38 泄漏」待处理项。PREDELETE probe 定位到：
```
CharacterActor.attribute_set → HexBattleCharacterAttributeSet
HexBattleCharacterAttributeSet._pre_change_callback → Callable
Callable → (闭包捕获 self) → CharacterActor   ← 循环
```
即 `CharacterActor._setup_attribute_constraints` 注册的 lambda 在访问 `attribute_set.max_hp` 时隐式捕获 `self`，形成 actor ↔ attribute_set ↔ Callable 三角强引用。属于循环 C/D/E 同族（子对象存的 Callable 捕获 owner），但表层是「闭包捕获」而非「字段缓存」。

### 架构决策：pre_change callback → 声明式 config 驱动的 cross-attr clamp
`_pre_change_callback` 的实际能力只能改 `inout_value["value"]`（clamp），无法触发副作用 —— **唯一用例**是跨属性 clamp（hp ≤ max_hp）。收敛为声明式 API 后 Callable 彻底消失。

### Added
- `RawAttributeSet.register_cross_attr_clamp(target, bound, source)` + `clear_cross_attr_clamps()`。`bound` 取 `"max"` / `"min"`，`source` 属性的 current value 作为 target 的动态边界。构建期 assert target/source 必须在同 set 里定义。
- `BaseGeneratedAttributeSet.register_cross_attr_clamp` 转发。
- Attribute config schema 新增 `maxRef` / `minRef` 字段，值为同 set 内的属性名。生成器在 `_init()` 末尾自动产出 `_raw.register_cross_attr_clamp(...)` 调用，并在生成期 validate source 存在；缺失时 `push_error`。
- `example/attributes/attributes_config.gd` 的 `HexBattleCharacter.hp` 加 `"maxRef": "max_hp"`，生成文件同步重建。

### Removed
- `RawAttributeSet._pre_change_callback` 字段 + `set_pre_change(callback)` + `clear_pre_change()`。
- `BaseGeneratedAttributeSet.set_pre_change(callback)` 转发。
- `CharacterActor._setup_attribute_constraints()` 函数 + `_init()` 里的调用（约束语义已完全下沉到 config）。

### Changed
- `RawAttributeSet.get_breakdown()` 计算流程「步骤 2」从「调 `_pre_change_callback`」改为「遍历 `_cross_attr_clamps` 并走 `get_breakdown(source)`」。读 source 时复用已有 `_computing_set` 循环检测机制，语义一对一。
- `tests/core/attributes/attribute_set_test.gd` 两个 pre_change 测试改名为 `cross_attr_clamp_*`，API 切换为 `register_cross_attr_clamp("hp", "max", "max_hp")`，断言不变。

### 主仓库同步
- `character_actor.gd` 删 `_setup_attribute_constraints` 调用。项目级 `logic-game-framework-config/attributes/attributes_config.gd`（`Hero`/`Tower`）因不含 hp 属性，无需改动。

### 验证（基线 → 本轮后）
| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (59/59) | 33 leaked / 14 resources | **24 leaked / 11 resources** |
| `smoke_strike.tscn` | 112 leaked / 38 resources | **0 / 0** 🎯 |
| `smoke_frontend_main.tscn` | 46 resources | **0 / 0** 🎯 |

→ [design-notes/2026-04-19-attribute-cross-clamp-config-driven.md](docs/design-notes/2026-04-19-attribute-cross-clamp-config-driven.md)

### 待处理
- LGF 单元测试 24 leaked / 11 resources 是**测试框架层面**的泄漏（testframework 保留每个 `*_test.gd` 的 GDScript 引用），与生产代码无关，独立问题。
- `_listeners: Array[Callable]` 仍是潜在风险点：若业务代码向 `attribute_set.add_change_listener` 传入捕获 actor 的 lambda，会形成 actor ↔ attribute_set ↔ listener 循环。生成器产出的 wrapper 只捕获 `actor_id` String 和用户 Callable，自身安全；但用户侧 Callable 的闭包捕获需要审计（后续同类风险扫描）。
