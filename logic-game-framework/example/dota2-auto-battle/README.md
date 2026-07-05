# Dota2 Auto Battle 示例

ARAM 式**单中路实时自动战斗** example：一条水平中路，左右两队从两端 spawn lane creep，单位推进 → 按 aggro range 获取敌人 → 追击进 attack range → 基础攻击经 LGF Ability/Timeline/Action 解析。逻辑层单线程定长 tick（30 Hz）、前端只读响应式渲染。

> 状态：**M1 vertical slice 已落地**（core + logic 全层 + 可 F6 运行的 lane battle scene + 2 个 smoke）。本 README 是本 example 的唯一总览，吸收了原 `docs/design-notes/` 6 篇 + 各层 README + development-plan。变更记录见 [`CHANGELOG.md`](CHANGELOG.md)，框架级架构见 [`../../docs/README.md`](../../docs/README.md) 与 [`../../docs/reference/action-architecture.md`](../../docs/reference/action-architecture.md)。

## 分层结构

依赖方向自上而下，上层依赖下层，下层绝不反向引用（参照 `hex-atb-battle` 的 LGF 分层）。

### `core/`
- 拥有战斗世界 `Dota2WorldGameplayInstance`、定长 tick 推进 `Dota2AutoBattleProcedure`（每次调用恰好推进一个 fixed logic tick）、单帧封装 `Dota2LogicFrame`，以及共享事件 `events/dota2_battle_events.gd`。
- 单线程执行；不拥有前端渲染，也不拥有 DOTA2 专属的移动策略内部实现。catch-up 时钟块归第一个前端场景所有，任何 catch-up / 债务丢帧必须打 warning。

### `logic/`
- 战斗规则与机制层，依赖 core/LGF；前端只读其状态或事件。子目录：`actors/`（`Dota2BattleActor` / `Dota2UnitActor`）、`controllers/`、`ability/`（`Dota2BasicAttackAbility` / `Dota2AttackCooldown`）、`actions/`（`Dota2DamageAction` / `Dota2AttackStartedAction`）、`ai/`（`Dota2TargetSelectors`）、`config/`（`Dota2LaneConfig` / `Dota2UnitTypeConfig`）、`systems/`（`Dota2WaveSpawner` / `Dota2TargetingSystem`）、`movement/`（`Dota2MovementAdapter`，战斗意图→移动实现的适配器，以 sim-nav-map 的 DOTA2 移动 lab 为参考）、`attributes/`。
- Systems / Abilities / Actions 是唯一的状态变更权威；M1/M2 不引入 command/order 层。

### `logic/attributes/`
- 单位属性走 LGF AttributeSet，不在 actor 上加 per-stat forwarding getter。`Dota2BattleActorAttributeSet`（基类，含 `hp` / `max_hp` 及 `hp <= max_hp` 跨属性 clamp，clamp 归 AttributeSet 而非 actor setter）；`Dota2UnitAttributeSet` 继承之，加 `move_speed` / `attack_damage` / `attack_range` / `attack_interval_ms` / `aggro_range`。
- `armor` 暂不生成（待伤害模型需要再加）；spawn 时**先设 `max_hp` 再设 `hp`** 避免被默认 max clip。
- **example-local config/output**：`attributes_config.gd` 定义本 example 全部 set，`AttributeSetGeneratorScript` 按 `example/<name>/logic/attributes/attributes_config.gd` 约定自动发现，产物生成到同目录 `generated/`。

### `logic/controllers/`
- 每单位的运行时行为大脑：`Dota2UnitController`（基类）、`Dota2LaneCreepController`（首个具体实现：推线行军 / aggro / 追击 / 攻击 / 回线）。
- 决策/意图模型：`Dota2DecisionResult`（创建/保持/打断/清除意图的决策输出）、`Dota2Intent`（持久化的 current_intent）、`Dota2IntentStepResult`（systems 每 tick 回报的执行结果）、`Dota2IntentStatus`（`RUNNING` / `COMPLETED` / `FAILED` / `INTERRUPTED`）。
- Controller 仅在意图需要重新决策时才决策，拥有最终生命周期转换（keep/complete/fail/interrupt/replace）；**不**直接改 position / HP / cooldown / 死亡状态 / Ability 执行状态。

### `frontend/`
- 实时车道战斗场景 `scene/dota2_lane_battle.tscn`（编辑器 F6 运行）+ 场景脚本私有 logic clock 块 + 富 debug 面板。对战斗决策**只读**：可请求场景搭建 / debug 控制，但不得直接改战斗、目标选择或移动状态；可基于快照插值渲染，但插值结果不得回喂战斗决策。`ui/` 目前仅占位。

### `tests/`
- battle / frontend 两个 smoke：`battle/smoke_lane_wave_engage.tscn`、`frontend/smoke_frontend_main.tscn`。经 `tests/test_groups.json` 注册，namespace `dota2autobattle`，组 `smoke` + `regression`；入口 `./tools/run_tests.ps1 dota2autobattle/smoke`。

## Tick 模型

单线程**定长逻辑 tick**（fixed timestep）。逻辑层是唯一权威（controller 状态、战斗、targeting、移动 intent、cooldown、HP、死亡、事件 emission）；Godot render frame 只提供 elapsed real time，不拥有任何仿真决策；前端只读逻辑 frame 与 event，不得 mutate 战斗状态。

固定 tick 常量（前端持有，带有限 catch-up）：

```gdscript
const LOGIC_DT_MS := 1000.0 / 30.0
const MAX_LOGIC_STEPS_PER_RENDER_FRAME := 2
const MAX_ACCUMULATOR_MS := LOGIC_DT_MS * MAX_LOGIC_STEPS_PER_RENDER_FRAME
```

30 Hz 给 attack cooldown / aggro recheck / chase-stop / DOT-HOT interval / projectile travel 稳定的 "seconds" 语义（variable delta 已否决）。**Catch-up 不是标准路径**：标准路径是 render frame 到达 → 累积够时执行恰好一个 fixed tick → 从最新 logic frame 渲染。render frame 迟到时同帧最多执行 `MAX_LOGIC_STEPS_PER_RENDER_FRAME` 个 tick；debt 超 `MAX_ACCUMULATOR_MS` 则**丢弃**多余 debt（避免 runaway，unlimited catch-up 已否决）。

**Warning 契约**：任何 catch-up 或 debt drop **必须** `Log.warning(...)`（含 `real_delta_ms` / `accumulator_ms_before` / `logic_steps_executed` / `dropped_debt_ms` / `logic_tick_index`）；正常单 tick 推进不得 warning。

**Logic clock 归属**：首版**不**创建 `Dota2SimulationDriver.gd`，render-facing scene 自持私有 clock block（`_accumulator_ms` + `_advance_logic_clock`）；procedure 拥有 fixed-step 仿真顺序、不知道 render frame，每次 `tick_once(LOGIC_DT_MS)` 恰好推进一个逻辑 tick。仅当多个 caller 共享同一 clock / step-frame debug UI / runtime 速度控制时才抽独立类。

**单 tick 执行顺序**：① tick ability/cooldown durations → ② cleanup dead actors + invalidate impossible intents → ③ update targeting/spatial → ④ controller decision step → ⑤ movement & ability systems advance intents → ⑥ controller result step → ⑦ emit frame/events。决策与 intent 执行分离，controller 持 `current_intent`、只在 lifecycle 需要时决策。

## Controller / Intent 模型

M1/M2 采用**持久 intent 执行**（persistent intent），而非 per-tick intent emission：

```text
Brain decision -> Dota2Intent -> controller.current_intent
  -> systems advance current_intent every fixed tick
  -> Dota2IntentStepResult -> controller updates intent lifecycle
```

**为何持久**：每 tick 重建会让系统无法分辨"延续同一动作"还是"开始新动作"，使 path reuse / attack windup / 中断 / 完成 / 失败语义模糊。持久 intent 给每个单位明确执行契约：决策选意图 → controller 存储 → 系统推进 → 系统返回执行状态 → controller 决定 keep/replace/interrupt/clear。

**Class 词汇**：`Dota2UnitController`（per-unit 行为 owner）、`Dota2LaneCreepController`（首个具体 controller）、`Dota2DecisionResult`（决策输出）、`Dota2Intent`（持久当前意图）、`Dota2IntentStepResult`（每 tick 执行结果）、`Dota2IntentStatus`（lifecycle 状态）。Intent 词汇：M1 实现 `LaneMarchIntent` / `AttackTargetIntent`（`dota2_intent.gd` 的 `KIND_LANE_MARCH` / `KIND_ATTACK_TARGET`）；`MoveToPointIntent` / `IdleIntent` / `CastAbilityIntent` 为设计预留、M1 未实现。

**Intent status**：`NONE` / `RUNNING` / `COMPLETED` / `FAILED` / `INTERRUPTED`。`intent_id` 用于区分"延续"与"新意图"。`AttackTargetIntent` 的权威 target 是 `payload.target_id`；actor 侧 target 字段只是 debug mirror，执行/决策必须读 current intent。

**执行边界**：Controller **不得**直接改 position / 施加 damage / mutate HP / 绕过 cooldown / 执行 ability / 移除死亡 actor / 调前端节点；**可以**更新自身行为状态 / 选新 intent / 中断自己的 current intent / 记录执行状态。`WaveSpawner` 不是命令源、不发 intent，只做：创建 unit actor → apply config + AttributeSet → 放 spawn point → attach controller → 注册。

**决策触发**：仅在 无 current intent / intent COMPLETED / FAILED / 被更高优先级中断 / intent 失效（target 死）/ 到 `next_decision_tick` 且允许 reconsideration 时才决策（不能仅因新 tick 就决策）。决策间隔是 controller policy：lane marching 每 5 tick 做一次 aggro search + 小的确定性 stagger（`actor_spawn_index % 3`）避免同 tick 扎堆；`AttackTargetIntent` 有效期间不周期切 target（避免 jitter），仅 death/invalid/leash failure 时重选。

**与 Ability 的关系**：lane march/chase/stop **不是** Ability，是 movement system 推进的 controller intent；基础攻击与未来法术 cast 才是经 `AbilitySet` 检查的 Ability。`AttackTargetIntent` 意为"保持此 target 并推进到合法基础攻击"，不直接施加 damage（movement adapter 报告 in-range → `AbilitySet` 请求 `Dota2BasicAttackAbility` → Timeline 到 attack point → Action 施加 damage → Event 记录）。

**未来玩家输入**：以独立 `PlayerController` 输入边界引入（command/request 留在 fixed tick 内；lane creep AI 与 `WaveSpawner` 永不用 command）。M1 不创建 `Dota2CommandBuffer` / `Dota2CommandSystem` / `Dota2UnitOrder`。

## Actor 与属性

DOTA2 战斗的运行时 stats（HP / attack damage / range / move speed / aggro / cooldown / armor / 未来 aura/item/buff）**不散落为 actor 字段**，actor 也**不长纯转发 getter**（`get_hp()` 等）。复用 LGF AttributeSet。

**Actor 契约**：

```text
Dota2BattleActor { ability_set; team_id; position_2d; velocity; is_dead/check_death();
                   get_attribute_set() -> Dota2BattleActorAttributeSet }
Dota2UnitActor   extends Dota2BattleActor { unit_type;    attribute_set: Dota2UnitAttributeSet }
Dota2TowerActor  extends Dota2BattleActor { tower_kind;   attribute_set: Dota2TowerAttributeSet }
```

`_on_id_assigned()` 须同步 `ability_set.owner_actor_id` 与 `get_attribute_set().actor_id`。`hp <= 0` 数据驱动死亡。共享 system/action 只需通用字段时用 `get_attribute_set()`；unit 专用系统直读 `unit.attribute_set.move_speed`。不为每个 stat 加转发方法（actor 方法保留给语义行为：`is_dead()` / `can_attack()` / 决策）。

**AttributeSet family**（非单一 unit bag）：`Dota2BattleActorAttributeSet { hp; max_hp; armor }` 只含所有可战斗 actor 能共享的 stats（`hp`/`max_hp` 必含，`armor` 仅当 unit/tower 都参与同一 armor 模型时放这里、首版无公式则 unused）；`Dota2UnitAttributeSet` 加 `move_speed` / `attack_damage` / `attack_range` / `attack_interval_ms` / `aggro_range`。基类返回 `Dota2BattleActorAttributeSet`（而非 unit）正是为支持 tower/building。

**static config vs runtime attribute**：type config 是静态共享初值/常量；AttributeSet 是 buff/aura/item/modifier 读写的运行时对象。可被 modifier 改的 stat 进 AttributeSet；纯 identity/geometry/authored timing（`team_id` / `position_2d` / `collision_radius` / `attack_point_ms` / `backswing_ms` / `projectile_speed`）留 actor 或 config，**待真有 modifier 需求再 promote**。tower protection / glyph 经 AbilitySet tag/modifier 建模，不硬编码为 actor flag。

**属性生成 example-local**：config 与产物都在 `logic/attributes/`（generator 自动发现，见「分层结构 › logic/attributes/」）；set 名跨 config 全局唯一（决定生成的 class_name），generator 生成前做冲突预检。

## Logic / View 契约

逻辑层权威，前端对战斗状态**只读**，首版无运行时玩家命令路径。

**Logic to View**：每 fixed tick 产/更新一个 frame 供前端消费：

```gdscript
class_name Dota2LogicFrame
var tick_index: int
var logic_time_ms: float
var actor_snapshots: Dictionary   # 稳定数据, 非 live actor 引用
var events: Array
```

契约：snapshot = 当前可观测状态；event = 本 tick 发生的事；view = 仅消费者。lane creep snapshot 期望字段：actor id / unit type / team / position / facing / HP / max HP / alive / current intent kind-status-target / next decision tick / movement state（destination/path/block reason）/ basic attack ability state（cooldown/phase/target）。

**事件词汇（M1/M2 canonical，其他文档应引用这些名而非发明别名）**：`unit_spawned` / `intent_started` / `intent_completed` / `intent_failed` / `target_acquired` / `attack_started` / `attack_landed` / `damage_applied` / `unit_died` / `unit_removed`。catch-up/debt-drop warning 是 telemetry，不建模为 gameplay event。

**View to Logic**：必须经显式 entry point（scene setup / reset / debug pause / debug speed）。**不允许**：从 view node 设 actor position / 从 VFX 施加 damage / 从动画 callback 改 cooldown / 点 sprite 换 target / 改 controller behavior / death 动画结束时移除逻辑 actor（死亡动画可比逻辑 actor 存活更久，但逻辑 removal event 决定 actor 何时离开仿真）。

**Interpolation**：`render_interpolated(alpha)` 的 `alpha` 仅渲染用、不回灌逻辑；combat range / attack timing / aggro / death check 全用 fixed-tick 状态。

## LGF Skill 模型

M1 基础攻击从首版战斗实现起即为 **Ability-backed**（依赖 Tick 模型与 Logic/View 契约先达成）。

**保留**（hex ATB 取舍）：Ability 决定 configured capability；AbilityComponent/Timeline 决定 action 何时 fire；Action 执行原子 state mutation；Event 记录发生之事供前端/replay/passive reaction；AI strategy 无状态返回 intent；Actor 拥有 identity/state；AttributeSet 拥有 runtime stats（落在正确 typed family 成员上）。**不保留**：ATB charge 作主 gate / hex grid targeting / 前端 playback 前的 full pre-simulation。

**基础攻击路径**：

```text
AttackTargetIntent
  -> movement adapter approach/stop
  -> AbilitySet 请求 Dota2BasicAttackAbility
  -> Timeline 至少建模 attack point (backswing/projectile 可后加而不改 intent 契约)
  -> Dota2DamageAction 施加 damage 与死亡
  -> attack_started / attack_landed / damage_applied / unit_died events
```

cooldown 与 cast timing 是 Ability/AbilitySet 执行状态，非临时 controller state；combat 从 typed `actor.attribute_set` 读 damage/range/timing（不经 actor 转发 getter）。

**Passive 与 modifier**：**不得**变成 Procedure 里的临时 if 分支，应表示为 attach 到 actor AbilitySet 的 ability/tag/event handler/modifier（lifesteal 听 post-damage emit heal；thorns 听 post-damage emit 反伤；slow apply movement-via-attribute 的 tag/modifier；poison 是带重复 damage tag 的 timed ability）。属性修改 effect 改 AttributeSet 值/modifier，不直接 patch actor 字段。**Active hero skill 不在 M1/M2**，加入时用与 hex 相同的 LGF 形状（`CastAbilityIntent` → condition/cost → timeline → action → event）。

## M1 契约

**Scene 目标**：ARAM 式单中路 auto battle —— 一条水平中路；两队从两端 spawn lane creep；推进 → 按 contact/aggro range 获取敌人 → chase 进 attack range → 基础攻击经 LGF Ability/Timeline/Action 解析；HP/death/intent state/movement state/event log 在前端可见以供 debug。

**Intent 执行归属**：systems 报告 fact（running/arrived/blocked/failed/stopped、hit/completed/cooldown blocked/target invalid），controller 拥有 lifecycle（keep/complete/fail/interrupt/replace）。

**Movement 契约**：M1 接 `sim-nav-map`（以 DOTA2 lab 为参考实现），战斗层经 `Dota2MovementAdapter` 翻译 intent → movement goal/target following/stop/cancel，**不**直接 mutate pathfinding/motion-controller internals，也不把 DOTA2 movement policy 移进 LGF core 或 sim-nav-map core。保持手感约束：hard block 可接受；无 friendly walk-through；无 formation/group pathfinding；无 push pressure。

**Basic Attack 契约**：从首版即 LGF Ability，`AttackTargetIntent` 不直接施加 damage（路径见「LGF Skill 模型」）。

**Debug-rich 前端**：首版重 observability —— 展示 logic tick / catch-up 计数、actor id/team/type、HP、current intent kind-status-target-next-decision-tick、movement state/goal/blocked-reason、basic attack ability state、近期 event。

**M1 Acceptance**：F6 开 scene 显示 ARAM lane fight；两队 spawn 并沿一条 lane 移动；移动走 adapter 路径（非直接 position mutation）；lane creep 用持久 current intent；基础攻击是 Ability、damage 经 Action/Event flow；前端展示 rich debug；DOTA2 专有 policy 留在本 example 层。

## 未来规划

> M1 已落地；以下为前瞻里程碑（首个验证目标 `./tools/run_tests.ps1 dota2autobattle/smoke`）。

- **M2 — Targeting / Basic Attack 硬化**：补 aggro range / target latch / invalidation / no-jitter switching 与 basic attack legality / cooldown-phase / damage / death event 的 focused test；细化 `Dota2IntentStepResult` reason；清理 event 词汇。**不首次引入 targeting/攻击，只硬化 M1 slice。**
- **M3 — LGF Skill 模型**：把基础攻击 Ability 形状向 DOTA2 技能扩展；定义 DOT/HOT/aura/attack modifier 如何避免硬编码 tick 分支（periodic effect 不进 Procedure tick loop；skill 执行为 cast point/backswing/projectile/passive reaction 留路径）。
- **M4 — Movement Adapter 硬化**：硬化 adapter 边界 + movement/path/blocked/failed 诊断；证明 controller/ability 只与 adapter 对话；底层 lab API 变更时 adapter 可替换。
- **M5 — 可见前端**：`frontend/dota2_lane_battle.tscn` live unit view / HP bar / attack-death VFX / lane camera + debug panel；frontend smoke 验 scene 加载。
- **长期方向**：前端私有 clock 仅在真实压力下抽 `Dota2SimulationDriver`；玩家/英雄控制以独立 `PlayerController` 输入边界设计。

### Open Design Questions

- 未来玩家控制时，cast request 应 override 自主 controller、busy 时 fail、还是 queued-command？
- 首个 basic-attack Timeline 能多小同时保留 attack point/backswing/projectile 路径？
- aura 与 DOT/HOT 如何表示才不成特殊 Procedure tick 分支？
- 哪些部分应在至少两个 example 需要后才提升进 LGF core？

---

> DevAgent 操作见 `frontend/scene/DEV_AGENT.md`。
