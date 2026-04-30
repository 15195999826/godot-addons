# 逻辑层到表演层数据传递指南

本文档描述了 Logic Game Framework 中逻辑层（Battle Logic）如何将数据传递给表演层（Presentation Layer）的设计方案和实现要点。

## 核心概念

### 为什么需要 StageCue？

在技能执行流程中，存在两个关键时间点：

1. **abilityActivate 事件**：只知道"谁要用技能"，此时 target 可能是空的（由 TargetSelector 在执行时查询）
2. **stageCue 事件**：在 `StageCueAction.execute()` 时产生，此时 targetSelector 已执行，目标列表已确定

```
abilityActivate 事件:
  - 只知道"谁要用技能"
  - target 可能是空的（由 TargetSelector 在执行时查询）
  
stageCue 事件:
  - 在 StageCueAction.execute() 时产生
  - targetSelector 已执行，目标列表已确定
  - 携带完整的表演所需数据
```

## 数据流架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              逻辑层 (Battle)                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. AI 决策                                                                  │
│     │                                                                       │
│     ▼                                                                       │
│  createActionUseEvent(abilityId, actorId, { target, element, power })       │
│     │                                                                       │
│     ▼                                                                       │
│  2. AbilitySet.receiveEvent() ─────► 触发 ActiveUseComponent                │
│     │                                                                       │
│     ▼                                                                       │
│  3. Timeline 执行（按 tag 时间点）                                           │
│     │                                                                       │
│     ├── tag: "start" (0ms) ──────► StageCueAction.execute()                 │
│     │                                    │                                  │
│     │                                    ├─ targetSelector 查询目标          │
│     │                                    │                                  │
│     │                                    └─► 产生 stageCue 事件              │
│     │                                        {                              │
│     │                                          kind: "stageCue",            │
│     │                                          sourceActorId: "攻击者",      │
│     │                                          targetActorIds: ["目标"],    │
│     │                                          cueId: "melee_slash"         │
│     │                                        }                              │
│     │                                                                       │
│     └── tag: "hit" (300ms) ──────► DamageAction.execute()                   │
│                                          │                                  │
│                                          └─► 产生 damage 事件               │
│                                              {                              │
│                                                kind: "damage",              │
│                                                sourceActorId, targetActorId,│
│                                                damage, damageType, ...      │
│                                              }                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼ EventCollector.flush()
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                              回放数据 (BattleRecord)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│  timeline: [                                                                │
│    { frame: 47, events: [stageCue, ...] },   // 动画开始                     │
│    { frame: 52, events: [damage, ...] },     // 伤害结算                     │
│  ]                                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼ BattleDirector / Visualizer
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                              表演层 (Presentation)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  4. VisualizerRegistry.translate(event, context)                            │
│     │                                                                       │
│     ├── stageCue ──────► StageCueVisualizer                                 │
│     │                         │                                             │
│     │                         └─► MeleeStrikeAction { from, to, style }     │
│     │                                                                       │
│     └── damage ────────► DamageVisualizer                                   │
│                               │                                             │
│                               ├─► FloatingTextAction { text: "-50" }        │
│                               └─► UpdateHPAction { fromHP, toHP }           │
│                                                                             │
│  5. ActionScheduler.enqueue(actions) ──► 并行执行动画                        │
│     │                                                                       │
│     ▼                                                                       │
│  6. RenderWorld.applyActions() ──► 更新渲染状态                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 实现要点

### 1. Timeline 定义

每个技能的 Timeline 需要包含 `start` tag（时间点 0ms），用于触发 StageCueAction：

```gdscript
# skill_timelines.gd
static var SLASH_TIMELINE := {
    "id": "skill_slash",
    "totalDuration": 500.0,
    "tags": {
        "start": 0.0,    # 0ms 发送 stageCue 给表演层
        "hit": 300.0,    # 300ms 时造成伤害
        "end": 500.0,
    },
}
```

### 2. Ability 配置

在 Ability 的 `tagActions` 中，`start` tag 绑定 `StageCueAction`，`hit` tag 绑定 `DamageAction`：

```gdscript
# skill_abilities.gd
static var SLASH_ABILITY := {
    "configId": "skill_slash",
    "displayName": "横扫斩",
    "tags": ["skill", "active", "melee", "enemy"],
    "activeUseComponents": [
        func():
            return ActiveUseComponent.new({
                "timelineId": "skill_slash",
                "tagActions": {
                    # start tag: 发送动画提示
                    "start": [StageCueAction.new({
                        "targetSelector": default_target_selector,
                        "cueId": "melee_slash",
                    })],
                    # hit tag: 造成伤害
                    "hit": [DamageAction.new({
                        "targetSelector": default_target_selector,
                        "damage": 50.0,
                        "damage_type": DamageType.PHYSICAL,
                    })],
                },
            }),
    ],
}
```

### 3. StageCue 事件结构

```gdscript
{
    "kind": "stageCue",
    "sourceActorId": "attacker_001",      # 技能使用者
    "targetActorIds": ["target_001"],     # 目标列表（已确定）
    "cueId": "melee_slash",               # 动画提示 ID
    "params": {}                          # 可选的额外参数
}
```

### 4. 常用 cueId 命名约定

| cueId | 描述 | 适用场景 |
|-------|------|----------|
| `melee_slash` | 近战斩击 | 普通近战攻击 |
| `melee_heavy` | 近战重击 | 蓄力攻击、毁灭重击 |
| `melee_combo` | 近战连击 | 多段攻击（params.hits 指定段数） |
| `ranged_arrow` | 远程箭矢 | 弓箭攻击 |
| `magic_fireball` | 火球术 | 火系魔法 |
| `magic_heal` | 治疗魔法 | 治疗技能 |

### 5. 表演层处理

表演层根据 `cueId` 选择对应的 Visualizer 来生成动画 Action：

```gdscript
# 伪代码示例
func translate_stage_cue(event: Dictionary, context: Dictionary) -> Array:
    var cue_id = event.get("cueId", "")
    var source_id = event.get("sourceActorId", "")
    var target_ids = event.get("targetActorIds", [])
    
    match cue_id:
        "melee_slash":
            return [MeleeStrikeAction.new({
                "from": get_actor_position(source_id),
                "to": get_actor_position(target_ids[0]),
                "style": "slash",
            })]
        "magic_fireball":
            return [ProjectileAction.new({
                "from": get_actor_position(source_id),
                "to": get_actor_position(target_ids[0]),
                "projectile_type": "fireball",
            })]
        _:
            return []
```

## 事件时序示例

以"横扫斩"技能为例：

```
Frame 0:   AI 决策使用横扫斩
Frame 1:   abilityActivate 事件触发 ActiveUseComponent
Frame 1:   Timeline 开始执行
Frame 1:   [start tag, 0ms] StageCueAction 产生 stageCue 事件
           └─► 表演层开始播放攻击动画
Frame 4:   [hit tag, 300ms] DamageAction 产生 damage 事件
           └─► 表演层显示伤害数字、更新血条
Frame 6:   [end tag, 500ms] Timeline 结束
```

## 设计原则

1. **逻辑与表演分离**：逻辑层只产生事件，不关心如何渲染
2. **事件携带完整数据**：stageCue 事件包含表演所需的所有信息
3. **时间点精确控制**：通过 Timeline 的 tag 精确控制事件产生时机
4. **可扩展的 cueId**：新增动画类型只需添加新的 cueId 和对应的 Visualizer

## 相关文件

- `skills/skill_timelines.gd` - Timeline 定义
- `skills/skill_abilities.gd` - Ability 配置（包含 StageCueAction）
- `events/replay_events.gd` - 事件类型定义
- `core/events/GameEvent.gd` - 框架事件定义（包含 stageCue）
- `stdlib/actions/StageCueAction.gd` - StageCue Action 实现
