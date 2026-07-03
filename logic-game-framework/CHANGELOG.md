# Changelog

本文件记录 Logic Game Framework 的重要变更。格式参考 [Keep a Changelog](https://keepachangelog.com/)。

- **Added** — 新增能力
- **Changed** — 行为或 API 变化
- **Fixed** — Bug 修复
- **Removed** — 移除
- **Deprecated** — 即将废弃

新变更追加到 `[Unreleased]` 段下，按上述分类组织；每条写清 **API 变化** 与 **why**。架构级取舍写进 `docs/README.md`（设计铁律 / 架构节）或 `docs/reference/`，不另开逐阶段长文。

---

## [Unreleased]

### Changed
- **`AbilityActivate` 补齐 schema（线 3 轮 B）**：新增 `logic_time` / `target_actor_id` / `target_coord: Dictionary` 三个可选字段（to_dict key 沿用既有事实拼写 `logicTime` / `target_actor_id` / `target_coord`，空 target 不写 key）——消灭全仓仅存的 6 处手写 `abilityActivate` dict literal（hex / dota2 procedure、skill-preview、harness、2 个 smoke 全部改走 `create()`）。`target_coord` 是坐标 dict 而非 HexCoord 类型，core 不依赖坐标实现。
- **REFRESH 叠层刷新改组件钩子（线 3 轮 B）**：`AbilityComponent` 新增 `on_ability_stack_refreshed()` 虚钩子，`Ability` 的 OVERFLOW_REFRESH 改为向全部 component 广播（原 `component.type == "TimeDurationComponent"` 字符串鸭子匹配删除——core 不再点名 stdlib 具体组件）；`TimeDurationComponent` override 钩子调自身 `refresh()`，行为等价。
- **目录归位（零行为，线 3 轮 A）**：recorder 家族（`BattleRecorder` / `RecordingContext` / `RecordingUtils` / `ReplayData` / `ReplayLogPrinter`）`stdlib/replay/` → `core/playback/`——录像是 core 事件系统一等公民（`BattleProcedure.finish()` 返回值即 recorder 输出）；投射物家族（`ProjectileActor` / `ProjectileEvents` / `ProjectileSystem` / collision detector ×4）`core/` + `stdlib/systems/` → `stdlib/projectile/`——仅 hex 使用的可选玩法件，不再让全部 example 白带；hex 的 `HexWorldGameplayInstance` / `HexBattleProcedure` `core/` → `logic/`——两类签名依赖 logic 类型，按单向依赖归位，hex `core/` 只剩共享事件定义。**全部类名不变，引用方零改动。** 裁决与执行切分见 `docs/proposals/2026-07-03-known-debt-and-hex-architecture-proposal.md`。

### Removed
- **死类 `GameEvent.AbilityActivated` 及其 `ABILITY_ACTIVATED_EVENT` 常量（线 3 轮 B）**：与 `AbilityActivate` 仅差一字母、全仓 create/from_dict/is_match 调用为 0 的占位类，从未有生产路径 emit 该 kind——直接删除消除命名混淆源（enforcing-lgf skill 文档清单同步）。

### Fixed
- **`ProjectileHit` 的 kind 常量归 core 注册表**：`GameEvent` 新增 `PROJECTILE_HIT_EVENT` 常量，`ProjectileHit` 改用之；stdlib `ProjectileEvents.PROJECTILE_HIT_EVENT` 转引 core 常量（值不变 `"projectileHit"`，行为逐位等价）——消除投射物工厂迁 stdlib 后 `game_event.gd` 对其残留的 core→stdlib 反向引用（codex review P2）。
- 文档漂移：`docs/README.md` 已知债务节按线 3 提案裁决重写（原 D2 条目「反向引用 ProjectileSystem」描述经查证不实）；hex `core/README.md` 重写为共享数据层职责（作废「阶段 5 Actor 下沉」旧路线）；`frontend/README.md` 修正死亡动画路径描述（走 `actor_died` Event 路径而非 `update_state` 推断）、删除已下线的 `FrontendBattleReplayScene` 使用段、Director/RenderWorld 的 signal 与方法签名对齐现行强类型；清理 `HexBattle` 已删除类的亡灵注释（2 处）。

---

## [Baseline] — 2026-05-31

文档 baseline 重置。此前逐阶段变更记录（Phase A–G、多轮 `[Unreleased]` 子段、各 design-note 长文）已归档为快照——完整轨迹见 git 历史。以下为当前框架与示例的能力快照，作为后续变更的基线。

### 框架核心 (`core/`)

- **Entity**：`Actor` / `System` + `GameWorld`（autoload 单例，`get_actor()` 统一查询入口，ID 格式 `{instance_id}:{local_id}`）。
- **World owns Battle**：`WorldGameplayInstance` 持有 actor registry / grid / systems，战斗降级为短命 `BattleProcedure`；前端响应式观察 world（见 `docs/README.md` 的 "World owns Battle + 响应式前端" 节）。
- **Ability**：`Ability` / `AbilitySet` + Timeline keyframe 驱动；Action 四层分层（Util / Primitive / Flow / SkillLocal，契约见 `docs/reference/action-architecture.md`），由轻量 validator 守边界。
- **Attribute**：`RawAttributeSet` + 4 层公式计算 + config 驱动跨属性 clamp（`maxRef` / `minRef` → `register_cross_attr_clamp`）。
- **Event**：`EventProcessor` pre/post + Intent（PASS / MODIFY / CANCEL）+ 强类型事件类；`EventCollector` 单 buffer，录像顺序 = 调用栈真实顺序。
- **Tag**：loose / auto-duration / component 三来源（语义见 action-architecture.md）。
- 结构性循环已根治：子对象回指 container 一律 `WeakRef` 或调用链参数流，无字段缓存 owner。

### 标准库 (`stdlib/`)

- Components：`StatModifierComponent` / `DurationComponent` 等。
- Systems：`ProjectileSystem`。
- Replay：`BattleRecorder`（A 层 "录像播放" Playback 现役；B 层确定性 Replay 仅命名占位）。录像格式 `PROTOCOL_VERSION` = v2。

### 示例 (`example/`)

- **hex-atb-battle**：回合制 + hex grid 战斗示例；~30 个 active ability + buff/passive 体系、skill-preview 沙盒、前端 `FrontendWorldView` / `FrontendBattleAnimator` 响应式表演层。专属文档见 `example/hex-atb-battle/README.md`。
- **dota2-auto-battle**：自动战斗示例（controller-intent + tick model）。专属文档见 `example/dota2-auto-battle/README.md`。
- **assets/tiny_swords**：共享美术资产包 + `TinySwordsCatalog` / `TinySwordsAnimationCatalog` 加载器。

> 已知债务与未来规划见 `docs/README.md` 的 "未来规划 / 已知债务" 节。
