# 线 3 启动提案：已知债务清偿 + hex-atb-battle 架构优化

> 任务来源：主仓 `docs/future/task-queue.md` 线 3。约束：**尽量少改 core** · **首要目标 = 优化 hex-atb-battle 架构** · 改动前出提案过目 · 守 enforcing-lgf。
> 本文 = 启动轮产出（现状核实 + 逐项方案 + 执行切分），**未动任何代码**。侦察方式：5 路并行代码级普查（core→stdlib 反依赖 / 强类型事件消费路径 / Replay 命名影响面 / 门控迁移清单 / hex 全景）+ 主会话对 core 中枢文件逐一直读 + 架构 KB 4 条原则比对（P027/P084/P034/P019）。
> 2026-07-03，fable。

---

## 0. 拍板清单（TL;DR）

| # | 项 | 推荐方案 | 规模 | 行为风险 |
|---|---|---|---|---|
| D1 | core→stdlib 反依赖（recorder） | **recorder 家族物理迁入 `core/playback/`**（git mv ×5，零代码改动）+ 组件刷新钩子去字符串匹配 | 小 | 零 / 极低 |
| D2 | ProjectileActor / projectile_events 在 core | **整体迁 `stdlib/projectile/`**（git mv，零代码改动；「反向依赖 ProjectileSystem」经查证不存在，债务描述需修正） | 小 | 零 |
| D3 | 强类型事件落回 Dictionary | **转正 dict 总线形态 + 收敛端点纪律**：core 只动 `game_event.gd`（AbilityActivate 补字段、删死类 AbilityActivated）；6 处手写 literal 改 create；4 个手写 visualizer 改 from_dict；kind 字面量常量化。**不**切管线签名，**不**删 class | 中 | 低 |
| D4 | Replay/Playback 命名混用 | 守既定最小集：`ReplayData→PlaybackData` + `load_replay→load_playback`，18 文件 73 引用点（含主仓 4 文件）。web 桥 JSON key 零波及（已核实） | 中（机械） | 低 |
| D5 | 28 技能门控手抄 | 28 个 byte-identical → `apply_standard_active_gating`；strike → `apply_basic_attack_gating`；move 不碰；**顺修 SkillValidator 豁免名单字符串错位**（`"skill_move"` ≠ 实际 `"action_move"`，潜伏 bug） | 中（机械） | 低（68 scenario 契约兜底） |
| D6 | WorldGI 把 hex 概念塞进 core | **维持不修**（触发条款未满足：3 分支中仅 dota2 不用 grid），仅更新债务条目描述 | 文档 | 零 |
| H1 | hex 自己的 core/ 双向依赖 logic/ | `hex_battle_procedure.gd` + `hex_world_gameplay_instance.gd` **上移 logic/**，core/ 只剩 `events/battle_events.gd`（真·纯数据层）；否决 core/README 里的「Actor 下沉」旧路线 | 小 | 零 |
| H2 | skill_preview.gd 6607 行 god file | 拆子控制器（给最小档 / 完整档两案，见 §3.2），**规模最大，单独排期** | 大 | 中 |
| H3 | 一致性小清理包 | 亡灵注释 ×2、"Character"/"Environment" 魔法字符串常量化、procedure 双日志路径、doc drift ×3、`_on_any_item_change_2` 命名 | 小 | 低 |

执行顺序建议：**轮 A（D1+D2+H1 纯位移 + 全部文档修正）→ 轮 B（D1 钩子 + D3a + validator 修正）→ 轮 C（D4 rename）→ 轮 D（D5 门控）→ 轮 E（D3b + H3）→ 轮 F（H2，独立大轮）**。详见 §5。

---

## 1. 现状核实：文档描述 vs 代码实况的漂移

启动侦察发现 `docs/README.md` 债务清单写于早前，多处已与代码脱节。**这些修正本身就是轮 A 的一部分**：

1. **D2 的「反向依赖」不实**：债务条目称 `projectile_actor.gd`「反向引用 stdlib 的 ProjectileSystem」——实测 core 全目录对 `ProjectileSystem` 唯一命中是 `projectile_actor.gd:110` 的注释块；`projectile_events.gd` 对 stdlib 引用 0 处。真实问题只剩「玩法常量（`PROJECTILE_TYPE_BULLET/HITSCAN/MOBA` + `CFG_*` + `STATE_*`）住在 core」一个维度。
2. **D1 的范围比文档多一条**：真实 core→stdlib 代码级反依赖共 5 处 / 3 文件 / 3 类——除已记录的 `BattleRecorder`（`battle_procedure.gd:21/45/94`）外，还有 `Actor.gd:164` 的 `RecordingContext` 参数类型、以及**文档未记录的** `ability.gd:361` 字符串鸭子匹配 `component.type == "TimeDurationComponent"`（REFRESH 叠层策略点名 stdlib 具体组件）。
3. **`HexBattle` 兼容类已删除**，但 `hex_world_gameplay_instance.gd:6-7` 与 `hex_battle_procedure.gd:6` 头注释仍称其「保留为 thin 兼容子类」——亡灵注释。
4. **门控 helper 零调用**：`apply_standard_active_gating` / `apply_basic_attack_gating` 已定义（`cooldown_system.gd:73-88`），全仓无一个技能调用。实测 active/ 30 文件 = 28 个 byte-identical 手抄 + strike（有意豁免 silence 的三件套）+ move（零门控），与文档「~28」吻合。
5. **B 层「命名占位」实为文档占位**：`BattleReplayPlayer` / `BattleReplaySession` 全仓代码零存在，仅活在 `docs/README.md` 一句话里。
6. **新发现潜伏 bug**：`scripts/SkillValidator.gd:12/16` 豁免名单写 `"skill_move"`，而 `move.gd:10` 实际 `CONFIG_ID = "action_move"`——字符串不匹配。当前无症状（move 无 `active_use_components`，豁免布尔从未被读到 warning 分支），但 move 未来加 active_use 或新技能占用该 id 时会爆。
7. **强类型事件的唯一构造破口**：`abilityActivate` 这个 kind 被手写 dict 6 处（`hex_battle_procedure.gd:292` 与 `dota2_auto_battle_procedure.gd:216` 两处生产代码 + skill-preview + 3 tests），根因是 `GameEvent.AbilityActivate` class **schema 落后**（缺 `logicTime` / `target_actor_id` / `target_coord`），写码者被迫绕开。另有**死类** `GameEvent.AbilityActivated`（与前者只差一个字母）create/from_dict/is_match 全 0。
8. **hex core/ 的双向依赖是已认账取舍**：`core/README.md:25` 明确承认 procedure/WorldGI 引用 logic 层类型「概念上倒挂……阶段 5 若把 Actor 下沉可消除，短期不动」。
9. **doc drift ≥3 处**：`frontend/README.md` 阶段三仍写 `update_state` 内 `if !is_alive -> _play_death_animation()`（与 `unit_view.gd:209` 现行「State 路径不推断死亡 transition」相反）；stale 的 `FrontendBattleReplayScene` 使用段；signal 签名标 `Dictionary` 实为强类型。

---

## 2. 逐债务方案

### D1 — core→stdlib 反依赖（recorder）→ recorder 家族迁入 core

**裁决依据**：录像不是 core 的「可选附件」，而是一等公民——`BattleProcedure.finish()` 的返回值就是 recorder 的输出（timeline dict）；`WorldGameplayInstance.battle_finished` signal 载荷即该 timeline；`EventCollector` 头注释自述「收集的事件仅供录像/表演层消费」；「录像顺序 = 调用栈真实顺序」是设计铁律。概念归属既然在 core，物理位置随之。

**动作**（轮 A，git mv ×5 + `--import`，零代码零行为改动——class_name 全局注册对文件移动免疫，已核实无任何 `.tscn`/preload/autoload 路径引用这些文件）：

```
stdlib/replay/battle_recorder.gd      → core/playback/battle_recorder.gd
stdlib/replay/recording_context.gd    → core/playback/recording_context.gd
stdlib/replay/recording_utils.gd      → core/playback/recording_utils.gd
stdlib/replay/replay_data.gd          → core/playback/replay_data.gd   （文件名轮 C 随类名一起改）
stdlib/replay/replay_log_printer.gd   → core/playback/replay_log_printer.gd（同上）
```

目录名取 `core/playback/`：与「A 层 = Playback（现役）」的既定立场同词根，覆盖「录制 → 数据 → 播放」整条数据基建；也顺手消灭了 `stdlib/replay/` 这个与 A/B 层命名立场相抵的目录名。迁移后 recorder 家族的全部依赖（GameEvent/GameWorld/Actor/IAbilitySetOwner/IdGenerator）都是 core 自己人，无新增反向边；stdlib→example 本就零引用。

**附带（轮 B，行为等价小改）**：`ability.gd:359-362` 的 `component.type == "TimeDurationComponent"` 字符串匹配 → `AbilityComponent` 基类加 `func on_ability_stack_refreshed() -> void: pass` 虚钩子，REFRESH 策略广播给所有 component，`TimeDurationComponent` override 调自己的 `refresh()`。core 不再点名 stdlib 具体组件（P027「机制不内置策略」的正统修法）。

**否决项**：
- 候选 A（core 定 IRecorder 抽象 + 注入）：改 core 接口、波及 hex / skill-preview / inkmon 三个 procedure 子类，「可替换 NoopRecorder/NetworkRecorder」是无实需的假设（YAGNI）。
- 候选 B（BattleProcedure 下放 stdlib）：被 `WorldGameplayInstance._active_battle` 字段 + `_create_battle_procedure` 工厂钉死，不可行。
- `Actor.gd:109-180` 的「BattleRecorder 兼容属性」段（`id/display_name/team/position` getter）**不动**：recorder 迁入 core 后这段注释语义反而成立；删兼容属性需全仓排查 `actor.id` 简写用量，收益低风险高。`position: Vector3` 本身合规（P027 案例明确：框架统一 Vector3 + configs 声明坐标系解释规则，正是现状设计）。

### D2 — 投射物家族 → 整体迁 `stdlib/projectile/`

**裁决依据**：① 全仓引用普查证实「白带」论点——`ProjectileActor` 仅 hex 一个 example 使用，dota2 / inkmon / 主仓零引用；② P027：bullet/hitscan/moba 是具体玩法策略，不是框架机制；③ P019 允许工厂类住子系统（该原则要求集中在 core 注册表的是**事件类型定义**——`GameEvent.ProjectileHit` class 留在 `game_event.gd` 不动，迁走的 `ProjectileEvents` 只是 dict 工厂 + kind 常量）。

**动作**（轮 A，git mv，零代码改动）：

```
core/entity/projectile_actor.gd       → stdlib/projectile/projectile_actor.gd
core/events/projectile_events.gd      → stdlib/projectile/projectile_events.gd
stdlib/systems/projectile_system.gd   → stdlib/projectile/projectile_system.gd
stdlib/systems/*_collision_detector.gd（×4）→ stdlib/projectile/（detector 家族只服务投射物）
```

hex 侧 28 处静态字段访问（chain_lightning/fireball/precise_shot）、skill_preview、harness、根级 tests fixture 全部零改动（class_name 不变）。`action_architecture_validator.gd` 的路径常量只列 actions 目录，不受影响。

**概念结论**：投射物从「core 一等公民」降为「stdlib 可选件」——正是债务原意（「不做投射物的 example 白带此类型」）的了断。

### D3 — 强类型事件 → 「转正 dict 总线 + 收敛端点纪律」

**普查结论**（这条债务的真实形状与文档描述差别最大）：
- 28 个强类型 class 三体系（core GameEvent 14 / hex BattleEvents 11 / hex HexBattlePreEvents 3），dota2 另用第四模式（`make_*() -> Dictionary` 工厂，零 class）。
- 调用统计：`create` 64 处 / `from_dict` 23 处 / **`is_match` 0 处**（四件套成员之一全员弃用，事实标准 = kind 常量比较）。
- **构造端纪律其实很好**：hex `logic/actions/`+`logic/abilities/` 手写事件 literal = 0。唯一破口是 `abilityActivate`（6 处手写，见 §1.7）。
- 消费端半分裂：7/12 visualizer 用 from_dict；4 个手写 `.get()`（`actor_facing_changed_visualizer` 有现成 from_dict 不用；`projectile_visualizer.gd:16-18` 硬编码 `"projectileLaunched"` 等 3 个字面量不用常量；`battle_animator.gd:215` 硬编码 `"actorSpawned"`）。
- 管线 16 处 Dictionary/MutableEvent 签名、0 强类型；Pre 消费走 `MutableEvent.get_current_value`（修改语义决定了强类型重建不适合 pre 管线）。

**裁决**（KB：P084 用户既有意志 = 消费端字段直访；P034 = 底层 dict 可接受、边界须类型安全；约束 = 少改 core）：

- **D3a（core 仅动 `game_event.gd` 一个文件，轮 B）**：`AbilityActivate` 补全字段（`logic_time` / `target_actor_id` / `target_coord`，可选字段）；6 处手写 literal 改走 `create()`；死类 `AbilityActivated` 删除（改前再 grep 复核一次零引用）。
- **D3b（example 层，轮 E）**：4 个手写 visualizer 改 from_dict（`buff_visualizer` 的 `consumption_records` 数组遍历等复杂结构按实际判断保留）；全部 `can_handle` 统一 kind **常量**比较，消灭字符串字面量。
- **D3c（文档，轮 A）**：README 债务条目改写为裁决记录——**dict = 总线/序列化形态**（EventCollector 与录像边界的合法形态），**强类型 = 两端形态**（构造走 create、消费走 from_dict / 字段直访）；`is_match` 从「四件套必备」降级为可选（实测采用率 0%，kind 常量比较已是事实标准）。
- **双否决**：候选 A（管线签名全切强类型）——改 EventProcessor/MutableEvent/Ability/component 全家签名，波及全部 example + inkmon 主游戏，违「少改 core」；候选 B（删 class 留 kind 常量）——直接违背 P084 证据链里用户四次原话表达的强类型意志，且被该原则「常见错误」点名。
- **不做**：统一 dota2 的 `make_*` 工厂模式——1c（dota2 从头重做）在队列在途，事件模式留给 1c 一并裁决。

### D4 — Replay/Playback rename → 守既定最小集

**动作**（轮 C，纯机械）：`ReplayData → PlaybackData`（嵌套类 BattleRecord/BattleMeta/FrameData/ActorInitData 名字不含 replay，不动）+ `load_replay → load_playback`（`battle_director.gd:192` + 4 调用点）+ 文件名 `replay_data.gd → playback_data.gd`、`replay_log_printer.gd → playback_log_printer.gd`。

**影响面**（已精确普查）：18 文件 73 引用点 = addon 内 14 文件 61 处 + **主仓 4 文件 12 处**（`ink_mon_battle_2d_animator/view`、`ink_mon_world_gi` 等）——需 submodule commit + 主仓 bump 同一批联动。

**已核实的安全边界**：录像 JSON 顶层 key（`version/meta/configs/mapConfig/initialActors/timeline`）与嵌套 key 全部不含 replay 字样，`SimulationManager.run_battle()` 原样 stringify 返回——**web/JS 桥协议零波及**；`PROTOCOL_VERSION` 不动。

**明确不动**（防止范围膨胀）：69 个 scenario 的 `assert_replay` 覆写族（测试 DSL 内部名，改它 = 影响面从 18 文件涨到 87 文件）；`BattleRecorder` 家族（Recorder = 写入器语义，与 A/B 层之争无关）；`playback_*` signal（已是正确词根）；`FrontendBattleDirector` / `FrontendPlaybackControls`；inkmon 侧自治命名（`load_record` / `play_replay` / `play_battle_replay` / `_replay_active`——是否顺势统一属主仓决策，本轮只列出不动手）；`"user://Replays/"` 存档路径。可选扩展项（默认不做，可拍板加入）：`get_replay_data() → get_playback_data()`（hex 2 个 GI + SimulationManager + inkmon world_gi/host 波及）。

### D5 — 门控迁移 → 29 文件机械替换 + validator 修正

**动作**（轮 D）：
1. 28 个 byte-identical 文件：4 行手抄 → `HexBattleCooldownSystem.apply_standard_active_gating(builder, COOLDOWN_MS)`（冷却传参 100% 一致用 `const COOLDOWN_MS`，无参数歧义；helper 返回 builder 可续链）。
2. `strike.gd:122-124`：3 行 → `apply_basic_attack_gating(builder, COOLDOWN_MS)`（其手抄内容与该 helper 输出逐项相同，silence 豁免已被 validator 具名固化）。
3. `move.gd` 不碰（零门控，走 ActivateInstanceConfig 事件路由，`ADVISORY_CANT_ACT_EXEMPT` 语义正确）。
4. **`SkillValidator.gd:12/16` 豁免字符串修正**：`"skill_move"` → `"action_move"`（§1.6 潜伏 bug）。
5. `cooldown_system.gd:65-68` 注释更新（「28 个手抄」的说法随迁移过时）。

Stage5 advisory 逻辑无需改（它检查 build 产物的 conditions 数组，helper 版产物相同）。buffs/passives/skill-preview/AI fixture 均无手抄门控，无同步面。

### D6 — WorldGI hex 概念 → 维持不修，更新描述

**核实**：grid 类族（HexCoord/GridMapConfig/GridMapModel）来自姊妹 addon `ultra-grid-map`（addon→addon 依赖，非 core→example）；WorldGI 现有 3 个直接分支——hex（用 grid）、inkmon 主游戏（用 grid，且 adr/0002 明确把 `grid`/`actor_position_changed` 钉为 GI 基类机器）、dota2（**不用** grid，也不走 `tick()` 的 blocking 战斗循环，由前端时钟外部 drive）。触发条款「子类 3+ 且**超过一个**不用 grid」——不用 grid 的仅 dota2 一个，**未触发**。

**动作**（轮 A，纯文档）：债务条目补记「dota2 分支已落地且不用 grid（白带字段无实害）」的现状，触发线改写为「再出现一个不用 grid 的 WorldGI 分支，或 LGF core 需独立发布」。

---

## 3. hex-atb-battle 架构优化（首要目标）

全景扫描总评：**分层纪律整体良好**——logic→frontend 零引用；frontend 不改逻辑态（`apply_*` 只作用于 `FrontendRenderWorld` 渲染态）；「事件 vs 状态边界」实现干净（`unit_view.gd:209` 显式不在 State 路径推断死亡）；TODO/FIXME/HACK 标记全仓为零。真正的架构问题集中在三处：

### H1 — hex core/ 归位（轮 A）

hex 的 `core/` 宣称「共享数据层」，实际 3 个文件里 2 个（`hex_battle_procedure.gd` 334 行、`hex_world_gameplay_instance.gd` 222 行）大量引用 logic 层类型（CharacterActor/HexBattleActor/BattleAbilitySet/HexBattleLogger/HexBattleSkillMetaKeys）——README 宣称的「frontend → logic → core 单向」在 core→logic 方向被违反，且 README 架构表本来就把 `HexBattleProcedure` 归在 logic 层。

**推荐**：两文件 git mv 上移 `logic/`，core/ 只剩 `events/battle_events.gd`（647 行纯数据定义，唯一名副其实的共享层）。frontend 依赖 logic 本就合法（单向链内），零引用改动。
**否决**：`core/README.md:25` 旧路线「阶段 5 把 Actor 下沉 core」——CharacterActor 连着职业 config / 技能 / 装备容器整条链，下沉会把 core 吹成大杂烩，成本高两个数量级。
**顺带**：清 2 处 `HexBattle` 亡灵注释（§1.3）。

### H2 — skill_preview.gd 拆分（独立轮 F，规模最大）

**现状**：6607 行 / 344 函数，约 12 种职责块挤在一个场景控制器里（场景初始化 / 库存 UI+model 桥 ~750 行 / timeline 编辑器 ~1000 行 / 角色面板+Details ~850 行 / keyframe 数据模型 / World Reset / 3D 拾取+右键菜单 / START 模拟 / 战斗结果回放 / console 格式化 / preset 存取 / clay 主题 99 行）。全项目最大文件，是第二名（775）的 8.5 倍。另有实锤复制：**库存 orchestration 与 `item-preview/item_preview.gd`（604 行）平行两份**——`handle_drop` 同签名近同实现、`_refresh_*`/`_snapshot_*` 一一对应（widget 层 BagCell/EquipmentSlot 已复用，orchestration 没有）。

**拆分手法**：沿用 inkmon 主游戏已验证的「子场景控制器下放」先例（root 972→776 行那轮）。skill_preview 的 UI 均为代码构建，子控制器持 root 引用 + 自己的 UI 子树，宿主只留 wire。

| 档位 | 内容 | 预期 |
|---|---|---|
| **最小档** | 只拆两大块：`skill_preview_timeline_panel.gd`（SPT tab 全家：track 绘制/keyframe 按钮/拖拽/ruler/warning）+ `skill_preview_inventory_panel.gd`（库存 tab，**与 item_preview 共享同一个 orchestration 控制器**，一并消灭复制） | 6607 → ~4500 行 |
| **完整档** | 最小档 + 角色面板 / 3D 拾取输入 / preset 序列化 / console formatter 四块 | 6607 → ~2000 行 |

**风险与兜底**：skill-preview 有 9 个 smoke + DevAgent ops（`skill_preview_dev_agent_ops.gd` 依赖宿主方法名，拆分时保留 facade 方法或同步改 ops）。建议先做最小档验证手法，再决定是否推进完整档。

### H3 — 一致性小清理包（轮 E 或散入各轮）

1. **"Character"/"Environment" 魔法字符串常量化**：散落 12/8 个文件跨三层，无 actor-kind 常量（对比：门控 tag 已提常量且字面量近绝迹）。加 `HexBattleActorKinds.CHARACTER/ENVIRONMENT` 常量类，逐处替换。
2. **hex procedure 双日志路径**：`hex_battle_procedure.gd` 内 6+ 处 raw `print()` 战斗解说与结构化 `HexBattleLogger` 并存——收敛进 logger（受 `console_log` 开关控制）。
3. **doc drift 修正**（可提前进轮 A 文档批）：frontend/README 死亡逻辑段、stale `FrontendBattleReplayScene` 段、signal 签名 Dictionary→强类型。
4. 小项：`_on_any_item_change_2` 编号命名；`demo_random_frontend.gd:8` 硬编码 preload（class_name 已有，删 preload 用类名）。

---

## 4. 建设性意见（观察在案、本轮不动）

1. **技能 timeline 骨架样板**：~33 个 active 技能重复 `CONFIG_ID/TIMELINE_ID/COOLDOWN_MS + static var *_TIMELINE + static var ABILITY := builder()...` 结构。README 已认「无共享骨架 helper」为真债，但骨架 helper 的抽象容易过度设计——建议 D5（门控）落地后观察剩余样板的真实重复度再议。
2. **BaseAction(43) vs PrimitiveAction(6) 划分不统一**：`damage_action` 与 `spawn_actor_action` 同为原语却分属两基类。这是 action-architecture 契约里 allowlist cleanup（「历史类暂时走 allowlist，后续分批迁移」）的既有挂账，宜作为独立机械轮（迁基类 + allowlist 削减），不混入本批。
3. **测试空白**：logic/ai 5 个策略类、`battle_logger.gd`（389 行）、`HexDemoWorldGameplayInstance` demo 行为均无独立测试（仅端到端间接覆盖）。AI 策略是逻辑分支密集区，值得补 headless 单测；随未来改动顺手补，不专门开轮。
4. **dota2 事件模式**（`make_*` 工厂 vs hex 强类型 class）与 core 战斗调度不适配实时模型（dota2 绕开 `WorldGI.tick` blocking 循环）——两项都留给队列 1c（dota2 重做）裁决，本轮只记录。
5. **既有挂账重申**（不新增动作）：录像文件大小优化 3 方案（`battle_recorder.gd` 头注释）；录像格式 v3（split world_snapshot + event_timeline，hex procedure 仍走旧 v2 initial_actors 路径）。

---

## 5. 执行切分与验收

| 轮 | 内容 | 改动性质 | 验收 |
|---|---|---|---|
| **A** | D1 迁移（5 文件→core/playback/）+ D2 迁移（7 文件→stdlib/projectile/）+ H1 归位（2 文件→logic/）+ 亡灵注释 + 全部文档修正（README 债务节重写：D2 描述修正/D3c 裁决/D6 更新；hex README 架构表；frontend/README drift；CHANGELOG） | 纯 git mv + 注释/文档，**零行为** | `--import` 后全量：`run_tests.ps1 -Required hex/all dota2autobattle/smoke` + `inkmon/all`（D1 动 core 目录波及主仓） |
| **B** | D1 组件刷新钩子（ability.gd 去字符串匹配）+ D3a（AbilityActivate 补字段、6 处 literal 改 create、删死类）+ D5.4 validator 豁免修正 | 行为等价小改，core 2 文件 | 同上全量 + LGF 单元 73 tests |
| **C** | D4 rename（addon 14 文件 + 主仓 4 文件联动 bump） | 机械 rename | 全量 + web 桥 smoke（SimulationManager 路径） |
| **D** | D5 门控迁移（29 技能文件 + 注释更新） | 机械等价替换 | `hex/all`（68 scenario 契约为主保障，含 silence/stun gate 场景） |
| **E** | D3b（4 visualizer + kind 字面量常量化）+ H3（魔法字符串常量类、双日志、小项） | example 层小改 | `hex/frontend` + 对账 oracle + `hex/all` |
| **F** | H2 skill_preview 拆分（先最小档） | 结构重构 | skill-preview 9 smoke + DevAgent ops 回归 + 编辑器 F6 人工过一遍 |

- 每轮 = 独立 submodule commit + 主仓 bump（阶段性即提）；轮间无强依赖，但 A 先行能让后续轮的文件路径一次到位。
- 迁移类改动（A）的既知坑：mv 后必须 `godot --headless --import` 再跑 smoke（class_name 缓存重建），`.uid` 文件随 .gd 同步移动。

## 6. 不做清单（本提案的负空间）

- D3 候选 A（管线签名全切强类型）/ 候选 B（删 class 留常量）——双否决，理由见 §2 D3。
- D6 抽 `ISpatialBackend` 抽象——触发条款未满足，维持既有裁决。
- `Actor.gd` 录像兼容属性段清理——收益低风险高。
- `assert_replay` 族（69 文件）与 `BattleRecorder` 家族 rename——范围膨胀，且 Recorder 语义无争议。
- inkmon 侧 replay 相关自治命名统一——主仓决策，不属线 3。
- dota2 事件模式统一 / timeline 骨架 helper / BaseAction→PrimitiveAction 批量迁移——观察在案，另立轮次。
