# SkillPreviewBattle 拆分: 删 Web preview + 迁 headless harness 进 LGF

**状态**: Implemented
**日期**: 2026-04-29
**范围**:
- `scripts/SkillPreviewBattle.gd` (拆 + 删)
- `scripts/SimulationManager.gd` (删 Web preview hook)
- `addons/logic-game-framework/example/hex-atb-battle/` (新增 harness)
- `addons/logic-game-framework/tests/example/hex-atb-battle/skill_scenarios/` (迁入 scenario tests)
- `addons/logic-game-framework/tests/example/hex-atb-battle/smoke_skill_scenarios.*` (迁入 runner)
- `addons/logic-game-framework/tests/example/skill-preview/smoke_skill_preview*.gd` (迁入 SkillPreview smoke)
- `addons/logic-game-framework/tests/example/hex-atb-battle-frontend/smoke_*.gd` (迁入 frontend/presentation smoke)
**前置**: 无. **本 plan 是 TargetPolicy v3 第 5 步的前置 / 替代** — 完成本 plan 后, TargetPolicy 第 5 步直接在新 harness 上扩 `environment_N` 支持, 不再动 `scripts/`.

---

## 背景

`scripts/SkillPreviewBattle.gd` 当前是一个混合体:

1. **Web preview 桥接** — `run_preview(skill_source, scene_config)` + `_compile_skill()` (运行时编译 GDScript 字符串) + `_build_grid_config()` + `_resolve_target()`. 入口: `SimulationManager._on_preview_skill_call` → `window.godot_preview_skill`.
2. **Headless scenario harness** — `run_with_config()` / `run_with_actions()` + `_PreviewInstance extends HexWorldGameplayInstance` + 一堆 `_resolve_*_ref` / `_actor_src_to_preview_cfg` / `_fire_action`. 调用方: addon 内 `tests/example/hex-atb-battle/skill_scenarios/`, addon 内 `tests/example/hex-atb-battle/smoke_skill_scenarios.gd`, addon 内 `tests/example/skill-preview/smoke_skill_preview_timeline.gd`, `tests/example/skill-preview/smoke_skill_preview_procedure_timed.gd`, addon 内 `tests/example/hex-atb-battle-frontend/smoke_surge_unit_view.gd`.

两者共享 `_PreviewInstance` 但语义已经分叉:
- Web 路径接受**字符串源码**, 走运行时 GDScript 编译, 是"AI 生成技能预览"的产物
- Headless 路径接受**已注册的 ability config / scenario action**, 是 smoke 测试的固定 helper

类名 `SkillPreviewBattle` 也产生混乱:
- addon `example/skill-preview/skill_preview*.gd` (常驻 world 编辑器版) **已不依赖**它
- 但名字里仍带 "Preview" 让人以为它就是 skill_preview UI 的引擎

## 决策

**双步动作, 一步删 + 一步迁**:

### 1. 删 Web preview 路径 (整片删)

- `SimulationManager.gd`:
  - 删 `_js_callback_preview_skill` 字段
  - 删 `_on_preview_skill_call` 回调
  - 删 `_setup_js_bridge` 里 `window.godot_preview_skill` 注册块 (含 print)
  - 删 `run_preview_skill(input_json)` 包装函数
  - **保留** `godot_run_battle` / `godot_validate_skill` / `godot_greet` 三个 (与本轮无关)
- `SkillPreviewBattle.gd` 待迁前先删 Web 专属符号:
  - `run_preview()`
  - `_compile_skill()`
  - `_build_grid_config()` (Web 端 JSON dict → GridMapConfig 的桥; headless 路径用的是另一条 `_build_preview_config` + `map_config` 直接进 `_PreviewInstance.start`)
  - `_resolve_target()` (Web 路径专用, 旧的 845 行附近; headless 用的是 `_resolve_target_ref`)
  - `_make_result()` (`run_preview` 唯一调用方)
- 不再产出 `window.godot_preview_skill` 注册日志, 不再有运行时 GDScript 字符串编译.

### 2. 迁 headless harness 进 LGF

新位置: **`addons/logic-game-framework/example/hex-atb-battle/scenario/skill_scenario_harness.gd`**

- 新 class_name: `HexBattleSkillScenarioHarness`
- 路径放 `example/hex-atb-battle/scenario/` 是因为 `_PreviewInstance extends HexWorldGameplayInstance` 强依赖 hex-atb-battle 层 (HexBattleActor / 投射物 / grid). 不放 `addons/logic-game-framework/tests/` 根目录 — 那是 LGF core 单元测试地盘, 不该塞游戏专属 harness.
- 同目录已有 `environment/` 子模式作为先例, `scenario/` 与之并列.

**保留搬迁的符号** (从 `SkillPreviewBattle` 里直接搬, 不重写):
- `MAX_TICKS` / `TICK_INTERVAL` / `POST_EXECUTION_TICKS`
- `run_with_config()` / `run_with_actions()`
- `_fire_action()` / `_sync_all_actor_tag_logic_time()` / `_empty_result()`
- `_target_cfg_to_ref()` / `_resolve_actor_ref()` / `_resolve_target_ref()`
- `_build_preview_config()` / `_actor_src_to_preview_cfg()`
- `_PreviewInstance` 内嵌 class

**不搬的**: 上面"删 Web preview"列出的 5 个符号一并删掉, 不进新文件.

### 3. 更新所有调用方并迁移 scenario tests

- `tests/skill_scenarios/` → `addons/logic-game-framework/tests/example/hex-atb-battle/skill_scenarios/`
- 旧主项目 `smoke_skill_scenarios.gd/.tscn` → `addons/logic-game-framework/tests/example/hex-atb-battle/smoke_skill_scenarios.gd/.tscn`
- addon 内 `skill_scenario.gd` 注释 (line 21 / 50): `SkillPreviewBattle` → `HexBattleSkillScenarioHarness`
- addon 内 `smoke_skill_scenarios.gd` line 88: `SkillPreviewBattle.run_with_actions` → `HexBattleSkillScenarioHarness.run_with_actions`
- `addons/logic-game-framework/tests/example/skill-preview/smoke_skill_preview_timeline.gd` line 33 + 文件头注释
- `addons/logic-game-framework/tests/example/skill-preview/smoke_skill_preview_procedure_timed.gd` 注释 (line 4)
- `addons/logic-game-framework/tests/example/hex-atb-battle-frontend/smoke_surge_unit_view.gd` line 6 + 任何调用
- 删完后 grep 确认: `grep -rn "SkillPreviewBattle\|run_preview\|godot_preview_skill" scripts/ addons/` 应只剩 CHANGELOG / design-notes 历史记录.

### 4. 删空文件

最后 `scripts/SkillPreviewBattle.gd` 应该是空的 (所有符号要么删要么迁), **直接删文件**, 不留空 stub.

## 不做的事

- ❌ **不动** `addons/.../example/skill-preview/skill_preview*.gd` (常驻 world 编辑器, 走 `SkillPreviewProcedure`, 与本轮无关)
- ❌ **不动** `godot_run_battle` Web 桥接 (它走 `HexDemoWorldGameplayInstance`, 不是 SkillPreviewBattle)
- ❌ **不动** `godot_validate_skill` Web 桥接 (它走 `SkillValidator`, 与 preview 解耦)
- ❌ **不引入** harness 内部的进一步重构 (保持 1:1 搬迁, 等下次有具体需求再优化)
- ❌ **不重命名** `_PreviewInstance` (内嵌 class, 改名扩散面无收益)

## 落地顺序 (5 步)

| 步 | 动作 | 验证 |
|---|---|---|
| 1 | 在 LGF 新建 `example/hex-atb-battle/scenario/skill_scenario_harness.gd`, 1:1 搬保留符号, class_name = `HexBattleSkillScenarioHarness` | 新文件能 parse (Godot 编辑器打开无红线) |
| 2 | 迁移 scenario / SkillPreview / frontend smoke 到 addon, 改所有 test 调用方的引用 (见上) | 跑 LGF `run_tests.tscn` + addon `tests/example/hex-atb-battle/smoke_skill_scenarios.tscn` + addon `tests/example/skill-preview/smoke_skill_preview_timeline.tscn` + addon `tests/example/hex-atb-battle-frontend/smoke_surge_unit_view.tscn` 全 PASS |
| 3 | 在 `SimulationManager.gd` 删 `godot_preview_skill` 注册 + `_on_preview_skill_call` + `_js_callback_preview_skill` + `run_preview_skill` | `main.tscn` 能跑, `godot_run_battle` 仍工作 (本地 / Web 端不影响) |
| 4 | 删 `scripts/SkillPreviewBattle.gd` 整个文件 | grep 确认无残留引用; 跑全套 smoke + LGF unit tests |
| 5 | submodule commit (新 harness + LGF 内更新) → 主仓库 commit (删 SkillPreviewBattle.gd + SimulationManager.gd 改动) → bump submodule pointer | 两层 commit 顺序: submodule 先, 主仓后 |

## 验证

| 场景 | 预期 |
|---|---|
| LGF `run_tests.tscn` | PASS (无 SkillPreviewBattle 依赖) |
| addon `tests/example/hex-atb-battle/smoke_skill_scenarios.tscn` | PASS (调用方迁到 `HexBattleSkillScenarioHarness`) |
| `smoke_skill_preview_timeline.tscn` | PASS |
| `smoke_skill_preview_procedure_timed.tscn` | PASS |
| `smoke_surge_unit_view.tscn` | PASS |
| `smoke_frontend_main.tscn` | PASS (与 SkillPreviewBattle 无依赖, 应不动) |
| addon `example/skill-preview/skill_preview.tscn` | 能打开能跑 (走 `SkillPreviewProcedure`, 与本轮无关) |
| 主场景 `scenes/Simulation.tscn` (Web 模式 / 本地) | `godot_run_battle` / `godot_validate_skill` 仍可用; `godot_preview_skill` 不再注册 (Web 端 JS 调用会得到 `undefined`) |

## 与 TargetPolicy plan 的关系

本 plan 完成后:
- TargetPolicy v3 第 5 步的"`scripts/SkillPreviewBattle.gd` 加 `environment_N` 支持"改为"`addons/.../scenario/skill_scenario_harness.gd` 加 `environment_N` 支持".
- 推荐顺序: **先做本迁移 → 再做 TargetPolicy**. 理由: TargetPolicy 第 5 步要扩三个 helper (`run_with_actions` / `_target_cfg_to_ref` / `_resolve_target_ref`), 在迁好的新文件上动比在待删的老文件上动更克制, 且不会产生"先在 scripts/ 改一遍, 迁完再改一遍"的双修改.
- 若想并行省一轮 commit: 在本 plan 第 1 步搬迁时**顺手**加 `environment_N` 支持, TargetPolicy 第 5 步降级为只接入 wall_breaker smoke, 不再动 harness 内部. 但这会把两个独立决策耦合在一个 commit, 出问题难回滚 — **不推荐**, 默认两 plan 串行.

## 风险

- **Web 端调用方**: 若有 JS 端代码在调 `window.godot_preview_skill`, 删了之后会 silent fail (返回 undefined). 不在本轮兼容窗口范围 — 用户已显式表态"暂时不想关 Web 端的事情". **删之前需 grep Web 端代码 (本仓 `web/` / `frontend/` 目录或独立仓库) 确认没在用**, 或承认主动断该入口.
- **运行时 GDScript 字符串编译**: `_compile_skill` 是"AI 生成技能"系统的关键基础设施. 若未来要复活 Web preview, 需要从 git history 拉回 (`git log -- scripts/SkillPreviewBattle.gd`). **不预先抽到别处保留** — 那是猜需求.
- **CHANGELOG / design-notes 大量提到 SkillPreviewBattle**: 不动历史文档 (它们记录的是当时的状态), 但 CHANGELOG 加新条目说明本轮删除 + 迁移.

## 遗留 / 未来

- **若未来恢复 Web preview**: 走全新路径, 走 `SkillPreviewProcedure` + 常驻 world (与编辑器版同引擎), 不复活 `_PreviewInstance` 双轨. 入口可改名 `godot_preview_skill_v2`.
- **harness 内部 tick loop 与 `SkillPreviewProcedure` 内联了同构逻辑** (见 design-note `2026-04-20-skill-preview-reactive.md` 末段). 本轮**不合并**, 等需求驱动.
