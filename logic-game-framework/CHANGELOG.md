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

_（暂无）_

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
