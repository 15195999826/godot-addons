# 阶段 5 落地：拆 HexBattle thin 门面，引入 HexDemoWorldGameplayInstance

**日期**：2026-04-26
**范围**：`example/hex-atb-battle/hex_battle.gd`（删）、`example/hex-atb-battle/hex_demo_world_gameplay_instance.gd`（新）、`example/hex-atb-battle-core/hex_world_gameplay_instance.gd`、`example/hex-atb-battle/ai/*.gd` × 4、`example/hex-atb-battle/demo_headless.{gd,tscn}` + `example/hex-atb-battle-frontend/demo_frontend.{gd,tscn}`（含改名 `main.*` → `demo_*`）、主仓 `scripts/SimulationManager.gd` / `scripts/SkillPreviewBattle.gd` / `tests/smoke_world_view.gd`
**类型**：架构落地 + 范式对齐
**前置**：[2026-04-19-world-as-single-instance.md](2026-04-19-world-as-single-instance.md) 阶段 5（最后一个待启动阶段）

---

## 范围 / 前置

阶段 1–3 + 死亡留 world 落地后，剩下的就是把"`HexBattle` 这个 thin 兼容门面"从代码里彻底拆掉。原计划描述：

> 阶段 5 — 正式游戏场景：`main.tscn` / `Simulation.tscn` / Web 桥接 / scenario runner 切 WorldGI 承载；去掉 `HexBattle` 兼容门面；actor id 前缀替换。

实际实施时，启动盘点发现一个错位：**`HexBattle` 不只是 thin 门面**。

## 背景：原计划的"thin 门面" 描述与代码实际不符

阶段 1 把 core 拆成 `WorldGameplayInstance` / `BattleProcedure` 后，`HexBattle` 被收缩为 `extends HexWorldGameplayInstance` 的兼容子类。design note 里把它叫"thin 兼容门面"，意思是它转发给真正干活的 procedure，自己不干活。

但 2026-04-26 启动阶段 5 时通读 `hex_battle.gd` 268 行实际内容：除了 procedure 转发以外，还封装了**一整套 6v6 demo 战斗启动行为**：

- 默认 9x9 grid 配置（`_build_default_grid_config`）
- 6 职业硬编码（priest / warrior / archer / mage / berserker / assassin，左右各 3）
- 队伍随机放置（`_place_team_randomly` + `_calculate_placement_ranges`）
- inspire buff 全员加成（`_apply_inspire_buff_to_all`）
- 战报打印（`_print_battle_info`）
- 录像保存（`_save_replay` 写 `user://Replays/battle_*.json`）

这套行为被三个 demo entry 共用：
- `addons/.../hex-atb-battle/demo_headless.gd`（addon headless demo，本轮从 `main.gd` 改名）
- `addons/.../hex-atb-battle-frontend/demo_frontend.gd`（addon frontend demo，本轮从 `main.gd` 改名）
- `scripts/SimulationManager.gd`（web 桥接 `godot_run_battle`，本质也是给前端跑一场 demo battle）

"删 `HexBattle`" 等价于"把这套 demo 行为搬到某处"。这是个本轮才暴露的**架构决策**。

## 候选方案

讨论了 4 个：

| 方案 | 描述 | 否决/选定原因 |
|---|---|---|
| A | demo 行为整套搬到 `HexWorldGameplayInstance` | ❌ 框架类污染。`HexWorldGameplayInstance` 是通用 hex world base，写死 priest/warrior 等 demo 内容破坏分层 |
| B | 下沉到 3 个 main 各自 inline | ❌ 同套 ~150 行 demo 行为出现 3 份，未来加角色 / 调整默认地图要同步 3 处 |
| C | 改名 `HexBattle` → `HexBattleDemoInstance`，保留物理类 | ⚠️ 失去"物理删 HexBattle"的字面目标，但实际架构清晰度提升 |
| D | 抽 `HexBattleDemoBuilder` static helper，调用方 `helper.setup(world, cfg)` | ⚠️ 多一层概念，调用方写两行 |

**最终选定**：方案 C 的范式版本 —— 与已有的 `SkillPreviewWorldGI` 范式对齐：**每个独立场景拥有自己的 `HexWorldGameplayInstance` 子类**，新建 `HexDemoWorldGameplayInstance`，把 `HexBattle` 内容原样搬入。

## 选定方案的合理性

`SkillPreviewWorldGI` 已经在 `example/skill-preview/skill_preview_world.gd` 里跑了一段时间，模式经过验证：

```gdscript
class_name SkillPreviewWorldGI
extends HexWorldGameplayInstance
# 含 reset() / queue_preview / 编辑态 add_actor 流程
```

现在的 GameplayInstance 子类结构：

```
HexWorldGameplayInstance（框架基类，通用 hex world）
├── SkillPreviewWorldGI（skill-preview 编辑器场景，已存在）
└── HexDemoWorldGameplayInstance（6v6 demo 场景，新建）  ← 替代 HexBattle
```

每个独立场景有独立子类，框架基类保持通用。actor id 前缀按场景自然区分：
- `skill_preview_*`（preview 场景）
- `demo_*`（demo 场景，原 `battle_*` 替换）
- `preview_*`（主仓 SkillPreviewBattle 的 web 路径，新增）

将来真游戏战斗加一个 `HexGameplayInstance`（或别的命名），保持范式一致。

## 实现

PR-1 字段归位（先做）：
- `HexBattle.MAX_TICKS` 删（`HexBattleProcedure.MAX_TICKS` 是唯一来源，原本 HexBattle 上是注释里写明「保持一致」的镜像副本）
- `HexBattle.recorder` 字段删（`get_replay_data` 改读 `_hex_procedure.get_recorder()`）
- `HexWorldGameplayInstance.get_alive_actors()` 上抬
- AI strategy 4 个文件 7 处 `battle: HexBattle` → `battle: HexWorldGameplayInstance`
- `_PreviewInstance` 自管 `recorder` 字段

PR-2 物理拆解（本 design note 主体）：
- 新建 `HexDemoWorldGameplayInstance`，把 `HexBattle` 全部内容搬入；id 前缀 `demo`，type `hex_demo`，replay 文件名前缀 `demo_*`
- `_PreviewInstance` 改 `extends HexWorldGameplayInstance`，自管 `left_team` / `right_team` 字段（沿用 staging 风格），自带 `get_all_actors()`，id 前缀 `preview`
- 物理删 `hex_battle.gd`
- 调用方批量切：`SimulationManager` / `smoke_world_view` / addon `main.gd` × 2 → `HexDemoWorldGameplayInstance`
- 注释字面量更新：`handler_context.gd` example、`hex_battle_game_state_utils.gd` 注释、`hex_battle_procedure.gd` 注释、`CLAUDE.md` mermaid 图

## 验证

| 测试 | 结果 |
|---|---|
| LGF unit `tests/run_tests.tscn` | 59/59 ✅（PR-1 + PR-2 各跑一轮） |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_world_view.tscn` | PASS（views 6→5） |
| `tests/smoke_skill_preview_reactive.tscn` | PASS（3 场连续 + reset 归 0） |
| `tests/smoke_skill_scenarios.tscn` | 12/12 PASS |

## 方法论总结

**"thin 门面"这个词容易误导**。下次遇到「某类被标注为 thin 兼容层准备拆掉」时，先通读它的实际行数和方法清单，再判断"拆"的语义。本次 268 行的 `HexBattle` 被叫成 thin 门面，只因为它的**架构定位**是兼容层 —— 但**实际承担的代码体量**远超字面"thin"。两者都正确，但混用会让计划估错工作量。

**架构定位 ≠ 代码体量**。同一个类可以是「逻辑上的 thin 适配器」+「物理上的 ~200 行 demo 容器」。计划阶段把这两个维度拆开看，避免"删 X" 这种字面动作的语义滑动。

**范式优于 helper**。当某个 base class 已有一个具体子类（如 `SkillPreviewWorldGI`），新加场景时优先复用「子类化」范式而不是引入新的 builder/helper 层 —— 概念数量越少越好。

## 遗留

- `HexBattle` 字面量在 `addons/logic-game-framework/CHANGELOG.md` / `docs/design-notes/2026-04-19-*` / `docs/design-notes/2026-04-20-*` / `docs/README.md` / `docs/reference/action-system.md` 中仍存在 —— 这些是历史 snapshot 或 API 示例文档：
  - CHANGELOG / design-notes 是历史记录，按"只讲现状不讲历史"的反向规则**不更新**（它们正确反映了那一时点的代码状态）
  - `docs/README.md` / `docs/reference/action-system.md` 是当前版 API 文档，**应跟新**示例代码里的 `HexBattle` 类型标注 → `HexWorldGameplayInstance`，但不在阶段 5 PR-2 范围（属于跟随性文档清理，单独一轮）

- 主仓 `scripts/SkillPreviewBattle.gd::_PreviewInstance` 与 addon `SkillPreviewWorldGI` 是孪生但代码不共享 —— web 桥接 `godot_preview_skill` 的轻量复刻。如未来 web 端复用 addon 的 reactive preview，这两条路径可合并，本阶段不动。
