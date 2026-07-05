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
- **AttributeSet generator per-example 自动发现 + example-local 属性边界**：`AttributeSetGeneratorScript` 的两对硬编码 (config, output) 常量改为约定式发现——固定项目级 `logic-game-framework-config/attributes/` + 共享 demo 区 `example/attributes/` + 扫描 `example/<name>/logic/attributes/attributes_config.gd`，产物统一生成到 config 同目录 `generated/`（**加新 example 不动 generator**）；生成前跨 config set 名冲突预检（set 名决定生成 class_name 全局符号，重名整体拒绝、不写文件）。生成/校验逻辑全部 static 化，新增 headless 入口 `scripts/generate_attribute_sets.tscn`（退出码 0/1，agent/CI 可自跑；编辑器菜单 `Tools > LGFramework > 生成属性集` 不变）。hex（`HexBattle*` ×3）与 dota2（`Dota2*` ×2）set 迁入各自 `logic/attributes/`，共享 config 只剩 `Example*` demo set；产物 git mv 保 uid，重生成逐字节一致（hex character/environment 两文件带出历史 drift 修正：属性字母序 + 尾空行，语义零变化）。新增 `tests/core/attributes/attribute_set_generator_test.gd`（discovery / 冲突预检 / 生成主链路）。why：多 example 共挤一份 config 的耦合与产物冲突（dota2 route-3 临时债）清偿，「每个 example 自持 AttributeSet 边界」成为默认约定。
- **录像格式 v3 —— world_snapshot 归位 + 单路径录像**：录像文件形状改为 `{meta, world_snapshot{actors, mapConfig, positionFormats}, timeline}`。`BattleRecorder.start_recording(world_snapshot, actors)` 成为唯一录像路径——**快照必传**（战斗 blocking 跑完后世界已是终态，回放要从开战初态播，快照是回放必需品，"复用现有 world"对战后回放不成立）且**由世界侧产出**：`WorldGameplayInstance.capture_world_snapshot()`（配 `should_record_actor()` 录像范围钩子——常驻世界排除 overworld 实体，与 `_get_position_formats()` 坐标格式钩子），recorder 不再伸手进世界抄状态；actor 变化订阅保留（`attributeChanged` 等事件的唯一产生管道，inkmon render2d 回放消费）。`BattleProcedure._start_recorder()` 基类默认即标准路径，hex / skill-preview / inkmon 三处 override 删除；`_recording_enabled` 开关与中途 spawn 补录连接一并上提基类（含 `finish()` 时 disconnect 防跨战斗监听器泄漏——原 hex 版遗漏；基类版不再带 participants 去重 guard，`register_actor` 的订阅表前置检查已覆盖去重语义）。why：世界 owns 战斗架构的录像侧收尾——"录像 = 战斗过程、世界状态 = 世界产出"职责归位，消灭 events-only 双路径半吊子（基类默认路径从未有生产使用者）。拍板与执行清单见 `docs/proposals/2026-07-03-playback-v3-format.md`。
- **skill_preview.gd 拆分最小档（线 3 轮 F / H2）**：6607 行场景控制器拆出两个 RefCounted 子控制器——`SkillPreviewInventoryPanel`（390 行：inventory session/UI/拖放/快照）与 `SkillPreviewTimelinePanel`（1212 行：SPT 轨道/keyframe 按钮/拖拽/ruler/warning/mode buttons），宿主降至 5083 行（净减 1524）。纯平移契约：73 函数逐行不变（仅 `_host.` 前缀 + 18 处类型标注补齐——`_host: Node` 上取值需显式类型）；共享 selection（`_selected_spt_*`）、`_actors`、keyframe mutation 层留宿主（三方共用）。附带：`BagCell`/`EquipmentSlot` 的 owner 参数 `Node`→`Object` 放宽（panel 是 RefCounted；item_preview 零改动向后兼容）；与 item_preview 的 orchestration 合并**未做**（两侧 DevAgent 输出 rect schema 冲突 `{w,h}` vs `{width,height}`，强行统一是行为变化——留给完整档评估，差异清单见拆分依赖分析）。DevAgent 输出 schema 零变化。
- **visualizer 消费端收敛 + hex 一致性清理（线 3 轮 E）**：`BattleEvents` 新增 kind 常量区（11 个，class 内 kind 赋值与 is_match 同源化），11 个 visualizer + `battle_animator` 的 `can_handle`/`match` 事件 kind 字面量全部换常量（含 `ProjectileEvents.PROJECTILE_*_EVENT`、`GameEvent.ACTOR_SPAWNED_EVENT`）；`actor_facing_changed_visualizer` 改用现成 `from_dict`。`HexBattleActor` 新增 `KIND_CHARACTER`/`KIND_ENVIRONMENT` 常量，production 代码 14 文件的 `"Character"`/`"Environment"` 字面量常量化归零（tests 有意保留字面量做协议黑盒）。hex procedure 6 处 raw `print()` 战斗解说收敛进 `HexBattleLogger`（双日志路径合一；**默认可见性变化**：这些解说原来无条件打印控制台，现在受 `console_log` 开关门控且现有调用点默认 false——调试需看战斗过程文本时显式传 `console_log: true`）；`item_preview` 编号命名 handler 改语义命名；`demo_random_frontend` 删硬编码 preload 改用 class_name。
- **hex 技能门控统一走 bundle helper（线 3 轮 D）**：28 个标准 active 技能的手抄门控四件套（cant_act + silence + CooldownCondition + TimedCooldownCost）机械替换为 `HexBattleCooldownSystem.apply_standard_active_gating(builder, COOLDOWN_MS)` 链头包装；`strike` 的三件套（有意豁免 silence）替换为 `apply_basic_attack_gating`；`move` 零门控不变。条件从链尾前移到链头（纯查询条件 + 单 cost，求值顺序无副作用，语义等价）。门控声明自此单点化，漂移可结构区分。
- **A 层命名收敛（线 3 轮 C）**：`ReplayData → PlaybackData`（文件名同步 `core/playback/playback_data.gd` / `playback_log_printer.gd`）、`FrontendBattleDirector.load_replay → load_playback`——「现役 = A 层 = Playback」立场落到代码；.gd 17 文件 69 处 + 主仓 inkmon 4 文件联动 + 现行文档同步。录像 JSON key 与 web 桥协议零波及（key 本就不含 replay 字样），`PROTOCOL_VERSION` 不动；`assert_replay` scenario DSL / `BattleRecorder` 家族 / `initialize_from_replay` 等词根方法不在最小集，维持原名。
- **`AbilityActivate` 补齐 schema（线 3 轮 B）**：新增 `logic_time` / `target_actor_id` / `target_coord: Dictionary` 三个可选字段（to_dict key 沿用既有事实拼写 `logicTime` / `target_actor_id` / `target_coord`，空 target 不写 key）——消灭全仓仅存的 6 处手写 `abilityActivate` dict literal（hex / dota2 procedure、skill-preview、harness、2 个 smoke 全部改走 `create()`）。`target_coord` 是坐标 dict 而非 HexCoord 类型，core 不依赖坐标实现。
- **REFRESH 叠层刷新改组件钩子（线 3 轮 B）**：`AbilityComponent` 新增 `on_ability_stack_refreshed()` 虚钩子，`Ability` 的 OVERFLOW_REFRESH 改为向全部 component 广播（原 `component.type == "TimeDurationComponent"` 字符串鸭子匹配删除——core 不再点名 stdlib 具体组件）；`TimeDurationComponent` override 钩子调自身 `refresh()`，行为等价。
- **目录归位（零行为，线 3 轮 A）**：recorder 家族（`BattleRecorder` / `RecordingContext` / `RecordingUtils` / `ReplayData` / `ReplayLogPrinter`）`stdlib/replay/` → `core/playback/`——录像是 core 事件系统一等公民（`BattleProcedure.finish()` 返回值即 recorder 输出）；投射物家族（`ProjectileActor` / `ProjectileEvents` / `ProjectileSystem` / collision detector ×4）`core/` + `stdlib/systems/` → `stdlib/projectile/`——仅 hex 使用的可选玩法件，不再让全部 example 白带；hex 的 `HexWorldGameplayInstance` / `HexBattleProcedure` `core/` → `logic/`——两类签名依赖 logic 类型，按单向依赖归位，hex `core/` 只剩共享事件定义。**全部类名不变，引用方零改动。** 裁决与执行切分见 `docs/proposals/2026-07-03-known-debt-and-hex-architecture-proposal.md`。

### Removed
- **录像 v3 一揽子删除**：`PROTOCOL_VERSION` 与录像 `version` 字段（单一架构、录像是短命数据无多版本共存；防呆改必需字段检查——`BattleRecord.from_dict` 对缺 `world_snapshot`/`timeline` 直接 crash，坏文件炸得响不静默播空场）；顶层 `configs`/`mapConfig`/`initialActors` key（迁入 `world_snapshot`，`configs` 唯一实际内容 positionFormats 随迁；inkmon animator 对 `configs.animation` 的死读——recorder 侧从未写过该 key——改 `create_default()`）；`ActorInitData.abilities`/`tags` 字段（A 层铁律"Playback 不重建逻辑层"下全仓零消费，B 层 deterministic 重算若做需要的是配置+种子而非实例快照；Actor 的 `get_ability_snapshot()/get_tag_snapshot()` 方法保留——hex GI 观察快照与 skill_preview tags 面板仍消费）；`start_recording_events_only()`（并入唯一路径）。
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
