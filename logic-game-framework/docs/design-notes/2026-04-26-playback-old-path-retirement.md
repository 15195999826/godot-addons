# 2026-04-26 — A 层"录像播放"老路径下线（Playback Old Path Retirement）

## 范围 / 前置

涉及文件：

- `addons/logic-game-framework/example/hex-atb-battle/frontend/`
  - `main.gd` / `main.tscn`：唯一生产视觉入口，要切到响应式 wire
  - `scene/battle_replay_scene.gd`：要删
  - `ui/replay_controls.gd`：rename → `ui/playback_controls.gd`（见 D4）
- `addons/logic-game-framework/tests/frontend/`
  - `test_replay_flow.gd` / `test_3d_visualization.gd` / `test_compilation.gd`：3 个孤儿测试，要删
- 主仓 `tests/smoke_frontend_main.gd`：节点路径要同步改

依赖前轮决策：

- 阶段 2 [2026-04-20-world-view.md](2026-04-20-world-view.md) — `WorldView + BattleAnimator` 已落地
- 阶段 3 [2026-04-20-skill-preview-reactive.md](2026-04-20-skill-preview-reactive.md) — `skill_preview` 已切响应式
- D5 收尾 [2026-04-26-death-keeps-actor-in-world.md](2026-04-26-death-keeps-actor-in-world.md) — 命名约定钉死（Playback = A 层 / Replay = B 层）

## 背景

`FrontendBattleReplayScene.load_replay(record)` 是 destructive 重建路径 —— 从录像 dict 直接 spawn 视觉 view、setup grid renderer、wire camera/lighting，不读取任何运行时 world 状态。阶段 2/3 引入响应式 `WorldView + BattleAnimator` 后，这条老路径只剩**一个生产调用方**（`main.gd`）和**一个 smoke 测试**（`smoke_frontend_main`）间接依赖。

本轮目标：把这两个调用方切到响应式 wire，删掉 destructive 路径整个。

## 现状盘点

### `FrontendBattleReplayScene` 的所有引用

| 类型 | 文件 | 现状 | 处理 |
|---|---|---|---|
| 生产入口 | `example/hex-atb-battle/frontend/main.gd` | 唯一调用 `load_replay` 的视觉入口 | 改写为响应式 wire |
| 自身定义 | `example/hex-atb-battle/frontend/scene/battle_replay_scene.gd` | A 层 destructive 入口 | 删 |
| 测试（在跑） | `tests/smoke_frontend_main.gd`（主仓） | 通过 main.tscn 间接拿 BattleReplayScene 节点 | 配套改节点路径 + 断言保持 |
| 测试（孤儿） | `tests/frontend/test_replay_flow.gd` | 不在 `run_tests.gd::TEST_PATHS`，无 .tscn 入口 | 删 |
| 测试（孤儿） | `tests/frontend/test_3d_visualization.gd` | 同上 | 删 |
| 测试（孤儿） | `tests/frontend/test_compilation.gd` | 同上 | 删 |
| 文档 | `example/hex-atb-battle/frontend/README.md` | 流程图 + sample code 用到 | 同步更新 |
| 文档 | 各 design-note + skill `example-app-presentation.md` / `example-app-overview.md` | 历史描述 | design-note 留作历史；skill 文档同步类名 |

`SimulationManager.gd` 的两个 Web 桥接（`godot_run_battle` / `godot_preview_skill`）**只产出录像 JSON 字符串给 JS 端消费，Godot 内部不渲染**，不在老路径下线范围内。

### `FrontendReplayControls` 的所有引用

| 文件 | 处理 |
|---|---|
| `example/hex-atb-battle/frontend/ui/replay_controls.gd` | rename → `ui/playback_controls.gd`，`class_name FrontendReplayControls` → `FrontendPlaybackControls` |
| `example/hex-atb-battle/frontend/main.gd` | 引用同步更新 |
| `tests/frontend/test_compilation.gd` | 孤儿测试，整个删（见上一表） |

UI 控件（暂停/播放/重置/速度）逻辑是表演层通用的，跟 destructive 路径无关，但既然本轮在动这一带，顺手改名对齐 Playback 命名约定（见 D4）。

## 架构决策

### D1. 一次性下线，不走渐进 alias

候选：
- **A. 一次性下线**：改 main.gd + 删 ReplayScene + 改 smoke ✅ 选
- B. 渐进：重命名 `Replay→Playback` + `@deprecated`，下一轮再删 ReplayScene

选 A 因为：
1. 唯一调用方就 1 个（main.gd）+ 1 个 smoke 间接依赖，改动面**实测可控**
2. 渐进会留中间态（`Playback*` + 老 destructive `load_replay` 共存），文档/skill 维护成本↑
3. LGF tests/frontend 3 个孤儿删了之后干净，没历史遗物

### D2. 数据 schema 类（`ReplayData` 等）不重命名

`ReplayData` / `ReplayData.BattleRecord` / `ActorInitData` / `EventInitData` 是录像数据格式本身，A 层（播放）和 B 层（若做，重跑）都消费它。命名约定钉的是"消费路径"，不是数据 schema。

### D3. `FrontendBattleAnimator` / `FrontendBattleDirector` 保留原名

两者都不带 Replay / Playback 字眼，语义中性（"动画播放器" / "指挥层"），不需要重命名。

### D4. `FrontendReplayControls` → `FrontendPlaybackControls`（顺手改）

UI 控件不属于核心播放路径，独立改名收益≈0，但本轮在动这一带（`scene/` 删除、`main.gd` 重写），顺手把 `ui/replay_controls.gd` rename 到 `ui/playback_controls.gd`、`class_name` 同步对齐 Playback 命名约定，不留命名残债。

### D5. 录像格式 v2 不变

handoff 已确认 v3 split（`world_snapshot` + `event_timeline`）不做。`PROTOCOL_VERSION` 不升，外部录像消费方（JS / cloud）不受影响。

### D6. AI 目录类型标注收束本轮不做

正交问题，单独一笔 commit。

## 落地步骤

### Step 1 — 删孤儿（LGF submodule，无风险先做）

- `rm addons/logic-game-framework/tests/frontend/test_replay_flow.gd`
- `rm addons/logic-game-framework/tests/frontend/test_3d_visualization.gd`
- `rm addons/logic-game-framework/tests/frontend/test_compilation.gd`
- 如果 `tests/frontend/` 空了，顺手删目录

### Step 2 — 重写 `main.gd` 响应式 wire

**参考样板**：`addons/logic-game-framework/example/hex-atb-battle/skill-preview/skill_preview.gd::_init_world_stack` —— 该文件是当前已落地的"常驻 World + WorldView + Animator 三件套"响应式样板，本轮 main.gd 直接借同一模式。关键链：

```gdscript
# 摘自 skill_preview.gd:142-159
_world = <WorldGameplayInstance 子类>.new()
GameWorld.create_instance(func() -> GameplayInstance: return _world)
_world.start()
_world.battle_finished.connect(_on_battle_finished)

_setup_camera_and_env()                    # 自己承担 camera / lighting / env

_world_view = FrontendWorldView.new()
_world_view.name = "WorldView"
add_child(_world_view)
_world_view.bind_world(_world)             # 响应式 spawn unit views

_animator = FrontendBattleAnimator.new()
_animator.name = "BattleAnimator"
add_child(_animator)
_animator.playback_ended.connect(_on_playback_ended)
```

战斗触发 / timeline 喂给 animator：

```gdscript
# 摘自 skill_preview.gd:889-901
func _on_battle_finished(timeline: Dictionary) -> void:
    _animator.play(timeline, _world_view.get_unit_views())
```

main.gd 适配点：

1. World 用 `HexBattle`（继承 `WorldGameplayInstance`），不是 `SkillPreviewWorldGI`
2. 用户按 Start Battle 时按 map_config 重置 World（参考 skill_preview 的 `_reset_world_to_model_unguarded`），然后 tick 到 `battle_finished`
3. 自己 setup camera rig / lighting / hex grid renderer（从被删的 ReplayScene 搬出来，参数沿袭以保持视觉一致 —— skill_preview 注释 `_setup_camera_and_env` 已踩过同样的坑）
4. UI 控件 `FrontendPlaybackControls`（D4 改名后）继续用，`play / pause / reset / set_speed` 信号转发到 animator

落地阶段去验证 `HexBattle` 是否有 `battle_finished` signal、是否需要 `start()` / `start_battle()` 等入口；如果 API 跟 skill_preview 用的子类有差异，按实际调整（不在 design note 范围内推断）。

### Step 3 — 删 `FrontendBattleReplayScene` + rename `ReplayControls`

- `rm addons/logic-game-framework/example/hex-atb-battle/frontend/scene/battle_replay_scene.gd`
- 如果 `scene/` 空了，顺手删目录
- `mv addons/logic-game-framework/example/hex-atb-battle/frontend/ui/replay_controls.gd → ui/playback_controls.gd`
- 文件内 `class_name FrontendReplayControls` → `FrontendPlaybackControls`
- `main.gd` 引用同步更新（在 Step 2 重写时一并改完）

### Step 4 — 改 `tests/smoke_frontend_main.gd`（主仓）

节点路径换成新结构（`get_node("BattleAnimator")` / `WorldView` 之类）。4 条 invariants 保持：
- `is_ended()`
- `current_frame == total_frames`
- unit view count > 0
- 所有 actor `visual_hp ∈ [0, max_hp]`

### Step 5 — 文档同步

- `example/hex-atb-battle/frontend/README.md`：流程图和 sample code 改成响应式风格
- skill `enforcing-lgf/reference/example-app-presentation.md` / `example-app-overview.md`：同步类名引用
- LGF `CHANGELOG.md` `[Unreleased]` 开新子段（本轮主题）：
  - **Removed**：3 个孤儿测试 + `FrontendBattleReplayScene`
  - **Changed**：`main.gd` 切响应式 / 主仓 `smoke_frontend_main.gd` 节点路径
- 主仓 commit 链 + submodule pointer bump

## 验证

跑这 4 个，期望全绿：

```bash
godot --headless --path "D:/GodotProjects/inkmon/inkmon-godot" addons/logic-game-framework/tests/run_tests.tscn > /tmp/lgf.txt 2>&1
godot --headless --path "D:/GodotProjects/inkmon/inkmon-godot" tests/smoke_skill_preview_reactive.tscn > /tmp/spv.txt 2>&1
godot --headless --path "D:/GodotProjects/inkmon/inkmon-godot" tests/smoke_frontend_main.tscn > /tmp/sfm.txt 2>&1
godot --headless --path "D:/GodotProjects/inkmon/inkmon-godot" tests/smoke_skill_scenarios.tscn > /tmp/sss.txt 2>&1
```

期望：
- run_tests **59/59**
- skill_preview_reactive **PASS**
- frontend_main **PASS**（节点路径变了之后）
- scenarios **12/12**

**编辑器实测（必跑）**：F6 打开 `addons/logic-game-framework/example/hex-atb-battle/frontend/main.tscn`，点 Start Battle，确认 unit / 飘字 / VFX / 死亡动画都能看到。

## 风险与回滚

| 风险 | 缓解 |
|---|---|
| main.gd 改写引入新 bug | smoke_frontend_main 立刻命中 + 编辑器 F6 双验证 |
| WorldView/BattleAnimator 在 example 路径有未发现 edge case | 阶段 2/3 已落地，smoke_world_view + smoke_skill_preview_reactive 已绿 |
| smoke_frontend_main 节点路径换错 | 改完先 headless 跑，拿到 PASS 再走下一步 |

回滚方式：单一 PR / commit 链路，`git revert` 回到本轮前状态。submodule 单独 bump，必要时主仓回退到老 pointer 即可。

## 遗留

- **B 层"回放"（Replay）** 仍未落地。命名占位 `BattleReplayPlayer` / `BattleReplaySession` 保留，视未来需求再做。
- **AI 目录类型收束**（`ai/*.gd` 5 个文件 `battle: HexBattle` 类型偏窄但 IS-A 兼容当前不报错）单独一轮做。
- **`stdlib/replay/` 目录命名** 暂未变。它现在持有 `BattleRecorder` + `ReplayData` + `ReplayLogPrinter`，都是录像数据生产 / 消费侧的，没有"录像播放表演"成分。如果未来 `Recording` 这个名字更合适，留到那时一起做。
