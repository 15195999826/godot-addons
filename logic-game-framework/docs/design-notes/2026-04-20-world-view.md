# WorldView + BattleAnimator：Frontend 的响应式订阅层

**日期**：2026-04-20
**范围**：`example/hex-atb-battle-frontend/world_view.gd`、`example/hex-atb-battle-frontend/battle_animator.gd`、`tests/smoke_world_view.{gd,tscn}`；轻微 deprecation 标注 `example/hex-atb-battle-frontend/scene/battle_replay_scene.gd`
**类型**：阶段 2 落地记录（承 [2026-04-19-world-as-single-instance.md](2026-04-19-world-as-single-instance.md)）

---

## 背景

阶段 1 把 `HexBattle` 拆成持久的 `WorldGameplayInstance`（持有 actor / grid / systems，显式 mutation API 触发 signal）+ 短命的 `BattleProcedure`（ATB loop / recorder / 胜负判定）。但 frontend 仍停在"被动消费 `BattleRecord` dict"范式：

- `FrontendBattleReplayScene.load_replay(record)` destructive 重建整个视觉世界（grid + unit view + 特效）
- 新战斗必须经"写 record → 读 record → spawn everything"三跳才能上屏
- 编辑态 / skill_preview 想"改一下 actor 后立即看到" 必须走同一条 destructive 链

阶段 2 要让 frontend 跟上 core 的心智模型：view 是 state 的 reactive projection。

## 落地组件

### `FrontendWorldView extends Node3D`

订阅 WorldGI 的 mutation signal：
- `actor_added` → 建 `FrontendUnitView`（只针对 `CharacterActor`，见下面决策）
- `actor_removed` → `queue_free` + 从 `_unit_views` 字典移除
- `actor_position_changed` → `set_world_position` 平滑插值（视觉由 UnitView 内部 lerp 消费）
- `grid_configured` → 把新 GridMapModel 喂给内部 `GridMapRenderer3D` 重渲染
- `grid_cell_changed` → 整幅网格重渲染（粒度粗，阶段 2 够用）

`bind_world(world)` 先做一次同步 hydrate（遍历 `world.get_actors()` 建 view + 如果 grid 已配置就渲染）然后连接 signal。绑定解绑对称、多次 `bind_world` 自动 unbind 前一个。

`_unit_views: Dictionary` 以 `actor_id` 为键对外暴露，给 BattleAnimator 用。

### `FrontendBattleAnimator extends Node3D`

本质是 `FrontendBattleDirector` 的薄包装 + "不拥有 view" 约束：
- 内部新建一个 Director + 一个 `EffectsRoot`
- `play(record_dict, unit_views)` 把录像 dict 解码成 `ReplayData.BattleRecord` 喂 `Director.load_replay`，把外部 unit_views 字典存引用
- Director 的 `actor_state_changed` / `actor_died` 等 signal 由 Animator 的 handler 捕获，**转发**到 `unit_views[id].update_state(state)` —— 不动 view 生命周期
- VFX / 投射物 / 飘字（`attack_vfx_*` / `projectile_*` / `floating_text_created`）由 Animator 自己在 `EffectsRoot` 下建节点、自己 cleanup
- `playback_ended` 透传出来，调方据此判定"战斗视觉结束"

### 测试 `tests/smoke_world_view.tscn`

核心断言：
1. bind_world 前 view 数 = 0
2. `HexBattle.start` → signal 驱动 view 数 = 6（= 初始 actor 数）
3. `GameWorld.tick_all(100ms)` 推进战斗至 `battle_finished` 广播非空 timeline
4. `BattleAnimator.play(timeline, views)` 消费到 `playback_ended`
5. 剩余 view 被 `world.remove_actor` 干掉（view → 0）

## 关键决策

### D1. WorldView 只给 `CharacterActor` 建 view

**探测过程**：初版 WorldView 对任何 `add_actor` 一视同仁建 view。跑 smoke 时发现：
- 战斗期 `ProjectileSystem` 会 `instance.add_actor(projectile)` / `remove_actor(...)` → WorldView 为每个子弹创建了 `FrontendUnitView`（有球体 / 血条 / 名字标签）
- 战斗结束时统计 `_world.get_actors().size() == 10`（6 character + 4 残留 projectile），`view_count == 1`，signal 链条工作但视觉语义错乱

**决策**：在 `_spawn_unit_view` 里 `if not (actor is CharacterActor): return`。这引入 hex-atb-battle 包的 class 依赖，但 frontend 目录本来就已经 `import HexBattle`（见 `main.gd`），层次约束允许。

**替代方案**（未选）：
- 按 `actor.type` 字符串过滤（"Character"）—— 避免强类型依赖，但失去类型安全
- 暴露 `spawn_filter: Callable` 让调方决定 —— 过度灵活，阶段 2 无场景

### D2. 战斗中 `damage_utils` 调 `battle.remove_actor(dead_id)` 保留不动

设计 doc 明确说"死了是消失还是留尸体"归游戏规则层决定，framework 不内置。但现有 `hex_battle_damage_utils.gd:90` 的确在 HP=0 时调 `remove_actor` —— 这让 WorldView 在战斗期间也能看到 view 消失，对"reactive projection"是自洽的。阶段 2 不动这个行为；未来如果想"战斗里死了先躺平、战后再 remove_actor"，再改 damage_utils。

**smoke 适配**：不用 `HexBattle.left_team[0]`（那些可能已在战斗中被 remove），而是从 `WorldView.get_unit_views().keys()` 挑一个现存 view 对应的 id 调 remove。reactive 链条在这里是自一致的。

### D3. BattleAnimator 复用 Director 而不是从零写

**候选**：
- A. 在 Animator 里重写 timeline 解码 + scheduler。完全自主，但重新实现 `FrontendRenderWorld` / `FrontendActionScheduler` / `FrontendVisualizerRegistry` 三个现成轮子。
- B. 继承 Director。但 Director 是 Node，继承它 Animator 就不能自己是 Node3D（或得做奇怪的嵌套）。
- C. 组合：Animator 内部 `add_child(Director)`，订阅 Director 的 signal，转发到外部 unit_views。**选这个**。

组合路径零破坏既有 Director，`FrontendBattleReplayScene` 仍旧原样工作。Animator 只是"换了 view 生命周期管理者"的 Director 包装。

### D4. `FrontendBattleReplayScene` 保留但标 deprecated

现役 `main.tscn` / Web 桥接 / `SkillPreviewBattle` 全靠它 `load_replay`。阶段 2 不动它们 —— 阶段 3（skill_preview）/ 阶段 4（录像格式 v3 + ReplayPlayer）/ 阶段 5（main.tscn 切换）逐步迁移。当下标注 deprecation 只是让下游知道"未来的战斗场景走 WorldView + Animator"。

### D5. `actor_position_changed` / `grid_cell_changed` 先订阅、空实现

Core 层目前没有 emit 这两个 signal 的地方（阶段 1 刻意留白，等真有移动 signal / 地形破坏技能时再按需补 emit）。WorldView 先把 handler 写好，handler 做"安全的空操作"：
- `_on_actor_position_changed`：按 new_coord 推动对应 view 的 `set_world_position`
- `_on_grid_cell_changed`：整幅网格重渲染

不 emit 就不触发，不影响 MVP；有 emit 时立刻工作。

## 验证

四套测试全绿：

| 测试 | Before 阶段 2 | After 阶段 2 |
|---|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS | PASS |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ | 9/9 ✅ |
| `tests/smoke_world_view.tscn` | —（新增） | PASS |

## 方法论沉淀

1. **Reactive projection 不等于"view 镜像状态的每个字段"**。WorldView 只订阅**生命周期 + 结构性变化**（add/remove/grid），属性变化（HP / tag）交给 timeline-driven 的 Animator。两层解耦：WorldView 不知道战斗存在，BattleAnimator 不管 view 从哪来 —— 边界清晰、独立演化。

2. **共享状态容器识别**：`_unit_views: Dictionary` 被两个类读写（WorldView 写、Animator 读）。设计时要问"生命周期归谁"：视图归 WorldView（它订阅了 signal），Animator 只"借"不"拥有"。借用契约用 Dictionary 传递、WorldView 负责在 `unbind_world` 时清理；Animator 每次 `play` 时抓一次新的引用。这个模式在 UE 里是 "UObject owner / weak pointer consumer"，在 React 里是 "parent state + props"。

3. **Smoke 测试验证**"生命周期 + 信号链"**比验证"数值正确"更重要**。smoke_world_view 不检查 HP 数字对不对、特效像素对不对，只检查 view count 随 signal 正确变化 + 动画能跑到 `playback_ended` 不崩。这是层间契约测试的正确粒度。

## 遗留

- `actor_position_changed` / `grid_cell_changed` 的 emit 点（阶段 3：移动动画起；未来：地形破坏技能）
- BattleAnimator 消费 v3 格式 `event_timeline`（阶段 4）—— 当前仍吃 v2 dict，因为 HexBattleProcedure 还 override 走旧版 recorder
- `FrontendBattleReplayScene` 的彻底替换（阶段 5）
