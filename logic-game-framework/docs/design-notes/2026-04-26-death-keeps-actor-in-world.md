# 2026-04-26 — 死亡 ≠ 离开 world：damage_utils 不再 remove_actor

## 范围 / 前置

- **动的文件**：`example/hex-atb-battle/logic/utils/hex_battle_damage_utils.gd`（删 1 行 + 新增 `_clear_grid_footprint` 静态方法）
- **依赖的前轮决策**：
  - 阶段 0（`2026-04-19-world-as-single-instance.md` line 247）原则："死亡处理：战斗里 hp → 0 时，**发 death event 到 event_collector，但不 `world.remove_actor(id)`**。上层（游戏规则层）决定'死了是消失还是留尸体'。"
  - 阶段 3（`2026-04-20-skill-preview-reactive.md` D5）遗留：`damage_utils.apply_damage` 的 remove_actor 让 skill_preview 在战斗期间死者 view 立刻消失，死亡动画来不及播。当时的论证留了两条出路 ——（a）改 `world.remove_actor` 语义（延迟 emit）；（b）做 ReplayPlayer 临时 world 兜底。两条都太重，被推到下一阶段。

## 背景

阶段 3 收尾时用户在编辑器实测发现：skill_preview 战斗里被打死的角色 view **瞬间消失**而不是播下沉缩小的死亡 tween。当时已经知道是 `damage_utils.apply_damage` 在 hp ≤ 0 时调 `battle.remove_actor(target_id)` → emit `actor_removed` → `FrontendWorldView.queue_free` view → director 后续推 `actor_state_changed(is_alive=false)` 时 view 已 free，tween 起不来。

讨论"阶段 4 = ReplayPlayer + 录像格式 v3"时与用户重新对齐，发现：
- 用户**强烈反对**为表演层重建逻辑 actor（hydrate 真 Actor + AbilitySet + AttributeSet）—— 这是巨量复杂度
- 现状的 `FrontendBattleReplayScene.load_replay` 走的是"从录像 dict 直接 spawn 视觉 view，不重建逻辑层"路径，**已经够用**
- 死亡动画问题的根源不是"缺 ReplayPlayer"，是"damage_utils 顺手做了不该做的清理"

回到阶段 0 doc line 247 原则：**死亡是行为禁止，不是 actor 离开 world**。两个概念分开就行了。

## 定位

### 为什么 damage_utils 之前会 remove_actor？

历史包袱。阶段 1（HexBattle 拆分前）的战斗里，"死了"和"离开战斗"是同一个 owner 处理的 —— 因为战斗就是世界的全部。阶段 1/2/3 把 World/Procedure 拆开后，**逻辑还没迁过来**，damage_utils 这一行幸存下来。

### 移除后的正交性检查

把 `battle.remove_actor(target_id)` 删掉之前，确认每条依赖死者状态的路径都走 `actor.is_dead()`（基于 `_is_dead` flag，hp 一次性 ≤ 0 时翻为 true），不依赖 `world.has_actor()`：

| 路径 | 走什么 | 受影响？ |
|---|---|---|
| `HexWorldGameplayInstance.get_alive_actor_ids()` | `actor.is_dead()` | ❌ |
| `HexBattleProcedure._check_battle_end` | `actor.is_dead()`（`hex_battle.gd:143`） | ❌ |
| AI 候选枚举（`ai_strategy.gd` 等） | `enemies` / `allies` 列表 ← 上面的活人接口 | ❌ |
| `EventProcessor.process_post_event(_, alive_ids, _)` | 由调方传入 alive_ids | ❌ |
| `apply_move_action.gd` 的 `grid.move_occupant` | grid occupant，**会被尸体堵死** | ⚠️ 是问题 |

`apply_move_action.gd:51` 的 UNEXPECTED 兜底 `push_error` 会被踩到 —— 死者占着格子，活人 reserve 完去 move 时发现尸体在那儿。

### 为什么不只让"死亡"自动延伸到"清格子"？

阶段 0 doc 247 行的原话留了空：上层决定**死了是消失还是留尸体**。但"留不留 view"是表演层选择，"留不留格子占用"是逻辑层游戏规则的选择 —— 二者其实是不同维度的决策，目前我们的策略是：

- **逻辑层留 actor 实例**（is_dead()=true，behavior 禁用）—— 给"复活 / 救起 / 亡语 / 尸爆"这类机制留路
- **逻辑层清 grid 占用**（活人能走到尸体格上）—— hex 战斗的常规假设
- **表演层留 view**（缩小下沉到 visible=false）—— 死亡动画完整

未来要做"留尸体堵格子"的 gameplay（比如僵尸吃同伴 / 障碍物尸体），改成在 damage_utils 之外加一层"死后 N tick 清格子" / "某些 tag 的死者不清格子"，**不要改回死亡时全清**。

## 架构决策

### D1：不调 world.remove_actor，但显式调 grid.remove_occupant + cancel_reservation

候选三条：

- **A**：保留 remove_actor，给 World 加"延迟 emit signal"机制（战斗期不发 actor_removed，战斗结束统一发） → 改 framework 层 signal 时序，影响面大
- **B**：保留 remove_actor，给 WorldView 加"战斗期冻结" 开关（战斗期间不响应 actor_removed） → frontend 加状态机，且违反"reactive projection"心智
- **C**：直接不调 remove_actor，单独清 grid footprint —— **当前方案**

C 改动量最小（damage_utils 一处），且对得上阶段 0 doc 已写过的原则，无需扩散到 framework / frontend。

### D2：清格子的代码留在 damage_utils，不下沉到 World

候选两条：
- 把 `_clear_grid_footprint` 做成 `HexWorldGameplayInstance.on_actor_died(actor_id)` 公共方法
- 留在 damage_utils 当 static 工具

留 damage_utils 的理由：清格子是**死亡这一具体事件的清理动作**，跟 damage_utils 里的 push death event / process_post_event 是同一个时序段；下沉到 World 会让"死亡处理逻辑散落两处"，反而难追踪。等未来出现别的"清格子"路径（比如 forced eviction 技能）再抽不迟。

## 实现

```gdscript
# Before:
if target_actor.check_death():
    ...
    if alive_actor_ids.size() > 0:
        event_processor.process_post_event(death_dict, alive_actor_ids, battle)
    battle.remove_actor(target_id)   # 这一行是问题

# After:
if target_actor.check_death():
    ...
    if alive_actor_ids.size() > 0:
        event_processor.process_post_event(death_dict, alive_actor_ids, battle)
    _clear_grid_footprint(battle, target_actor)   # 只清格子, actor 留 world

static func _clear_grid_footprint(
    battle: HexWorldGameplayInstance,
    dead_actor: CharacterActor
) -> void:
    if battle == null or battle.grid == null or dead_actor == null:
        return
    var pos := dead_actor.hex_position
    if pos != null and pos.is_valid():
        battle.grid.remove_occupant(pos)
    for coord in battle.grid.get_all_coords():
        if battle.grid.get_reservation(coord) == dead_actor.get_id():
            battle.grid.cancel_reservation(coord)
```

## 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS（3 场连续, view/animator 实例复用） |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

skill_preview F6 编辑器手动验证（死亡 tween 缩小+下沉+visible=false）由用户接手。

## 命名约定（与本次同一轮对齐）

用户和 Claude 反复对齐"录像 / 回放"语义时确认：

| 中文 | 英文 | 含义 |
|---|---|---|
| **录像播放**（A 层，现状） | **Playback** | 表演层视觉播放：从录像 dict 读 actor 配置和事件流，spawn 一组视觉 view，按 frame 推动画 / 飘字 / VFX。**不重建逻辑 actor**。`FrontendBattleReplayScene` / `FrontendBattleAnimator` 现在做的事。 |
| **回放**（B 层，未来可能做） | **Replay** | 逻辑层重新跑一遍战斗：从录像 dict 反序列化真 Actor / AbilitySet / AttributeSet，按 timeline 命令重计算战斗状态，支持时间轴拖动 / 撤销 / 跳到第 N 帧。**当前不做，没规划**。 |

英文层利用 **playback ≠ replay 的语感分层**钉死两个层：
- `Playback` = "把已经录好的东西放给观众看"（DVR / 视频语境，被动、不计算）
- `Replay` = "重新跑一遍"（War3 replay / Dota replay 语境，deterministic 重算）

未来 A 层老路径整合（清掉 `FrontendBattleReplayScene.load_replay`）那一轮工作中，把现有 `BattleRecorder` / `ReplayData` / `FrontendBattleReplayScene` / `FrontendBattleAnimator` 等 A 层类全部改名到 `Playback*`，腾出 `Replay` 给未来 B 层（如 `BattleReplayPlayer` / `BattleReplaySession`）。**本期不动**。

阶段 0 doc 草拟的 "ReplayPlayer hydrate 真 Actor" 路径（字面看像 B 层但实际只是 A 层包装）**作废**。未来 A 层入口直接叫 Playback 系列。

## 当前剩余的 remove_actor 调用点（运行时，去掉文档/测试）

| # | 调用方 | 用途 | 性质 |
|---|---|---|---|
| 1 | `stdlib/systems/projectile_system.gd:131` | 投射物落地后从 world 拿走 | 投射物不是角色，飞完就该走 |
| 2 | `example/hex-atb-battle/skill-preview/skill_preview.gd:315` | 编辑态右键删 actor | 玩家显式编辑 |
| 3 | `example/hex-atb-battle/skill-preview/skill_preview.gd:562` | preset 加载 / class 切换 | 编辑态显式重建 |
| — | `SkillPreviewWorldGI.reset()` 走 `_actors.clear()` + emit | 战前清场 | 等价"全员离场" |

四条都符合"actor 永久离开 world"语义，跟死亡留尸体原则不冲突。

## 方法论沉淀

1. **概念耦合是隐形债**：阶段 1 拆 World / Procedure 时只关注了"谁拥有 tick"和"谁拥有 actor registry"，但"死亡处理"这种**跨层动作**的归属没单独审计 —— 它一直挂在 damage_utils 里没动，等阶段 3 切到响应式 view 才暴露。**重构清单要把"跨层动作"显式列一遍**：每个跨层动作（死亡、出生、移动、解散战斗、save/load）的清理责任各应该在哪一层做，而不是默认"原本在哪儿就留哪儿"。

2. **判断"留尸体"的责任分层**：
   - 是否留 **逻辑 actor 实例**：游戏规则决定（影响复活、亡语、引用持有）
   - 是否留 **grid 占用**：游戏战术决定（影响走位）
   - 是否留 **view**：表演决定（影响死亡动画 / 永久残骸）
   
   这三个维度可以独立配置，不要绑成"清理 = 全清，留 = 全留"。当前默认配置：留逻辑、清格子、留 view 直到自然下沉。

## 遗留

- **AI 走位绕开死者 view**：现在死者 view 留在场上（visible=false 之前会持续 0.5s 死亡 tween），活人这段时间里 move 到该格子视觉上会"穿过死尸"。本期不修，等出现明显视觉违和再说（可能修法：view 死亡 tween 触发时立即 visible 不影响 hp_bar / mesh 但 collision 关闭，或活人 move 路径检测）。
- **A 层"录像播放"路径整合**：`FrontendBattleReplayScene.load_replay` destructive 路径仍由 `main.tscn` / Web 桥接使用。用户表示"接下来一定会清理旧的战斗回放方案"，独立一轮工作做。
