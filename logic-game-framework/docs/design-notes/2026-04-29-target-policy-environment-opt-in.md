# Target Policy — EnvironmentActor Opt-In 边界

**状态**: Draft v4 (架构原则收敛: 走 metadata, 不引入新 condition)
**日期**: 2026-04-29
**范围**: `addons/logic-game-framework/example/hex-atb-battle/logic/` (sample 层)
**前置**: M1 EnvironmentActor 子系统 (8f643cb / c057c5e), 现有 `target_selectors.gd`, `can_use_skill_on()`
**依赖**: `2026-04-29-skill-preview-battle-migration.md` — 迁移完成后, 本 plan 的 harness 改动落在 `addons/logic-game-framework/example/hex-atb-battle/logic/scenario/skill_scenario_harness.gd`, 不再动主仓 `scripts/`。

---

## 背景

M1 引入了 `EnvironmentActor` (HexBattleActor 子类), 以 `StoneWall` 为唯一形态验证. 当前隔离边界靠各处 hardcode:

- `AllEnemies` selector 内部判 `actor is CharacterActor`
- `get_alive_actors()` / `get_alive_actor_ids()` 只返 character
- `HealAction.get_character_actor()` 拿不到 env 时直接 noop
- DamageEvent / DeathEvent / PreEvent 对 env 平权 (StoneWall 能受伤、能死)

要做"打墙"、"撞墙反伤"、"推墙"、"可破坏箱子" 这类 env 交互, 需要把"能不能选 env"从隐式 hardcode 提到声明式. **关键问题**: 在哪一层声明、声明什么.

---

## 架构原则 (v4 核心收敛)

经过 v1–v3 在 condition 路径上反复推演, v4 回到一条原则:

> **"如何释放" 是声明, 不是行为. 声明必须可查询.**

具体含义:
- "范围 / 阵营 / 能否对环境物释放" 这类 cast eligibility 配置必须是 **declarative metadata**, 让 AI / UI / tooltip / 玩家 cast 路径都能**事前查询**.
- Condition 是**事件到达时的 reactive 判断**, 适合被动技能"该不该响应这个事件". 主动 cast 的目标合法性**不是** condition 的本职.
- 把 cast 配置塞进 condition 会导致 AI 没法事前过滤候选 (它要么 dry-run condition, 要么各处复制规则), 是双源真相的开端.

现状已对齐这个原则的部分:
- `range` 走 ability metadata `"range"` (见 `HexBattleSkillMetaKeys.RANGE`)
- `enemy / ally` 走 ability tag (同样可查询)
- `can_use_skill_on(actor, skill, target)` 是 declarative 入口, AI 在 `ai_strategy.gd:45` 用它过滤候选

`allowed_target_kinds` 是同档次概念, **必须跟 range 同处理 — 进 metadata, 不进 condition**.

---

## 决策

**单层声明, 走 ability metadata**:

1. **声明** — 给 `HexBattleSkillMetaKeys` 加 `ALLOWED_TARGET_KINDS` key, 默认 `["Character"]`.
2. **消费** — `can_use_skill_on()` 加几行: 读 metadata, 校验 `target.type ∈ allowed_kinds`. 签名 `target: CharacterActor` 放宽到 `target: HexBattleActor`.
3. **生效层 (action semantics)** — Action 代码自己决定对 env 怎么处理:
   - DamageAction 走 `HexBattleActor.get_attribute_set()` 已平权
   - HealAction / ApplyBuffAction / ApplyShieldAction 维持 character-only (代码里用 `get_character_actor()`)
   - 特殊交互 (push / destroy) 等真有需求再加专用 Action, **不预先抽象**

**不做的事** (写下来防止 scope creep):
- ❌ 不加 `TargetPolicy` 类 — 只有一个字段 `allowed_kinds` 没必要包一个类, 直接走 metadata key
- ❌ 不加 `TargetAllowedCondition` 类 — 当前没有任何被动场景在用, 留作未来需求驱动 (例如 Thorns 反伤时按 source 类型 filter)
- ❌ 不改现有 7 个主动技能 — 它们走 metadata default `["Character"]`, **一行不用改**
- ❌ 不加新 selector — `CurrentTarget` 已经 type-blind, WallBreaker 复用即可
- ❌ 不改 `TargetSelector` 基类 / 不动 `select() -> Array[String]` 签名
- ❌ 不引入 `TargetResolution / TargetQueryResult` — 等 UI / AI 真用到再做
- ❌ 不预先抽 `DestroyEnvironmentAction` / `PushIntoEnvironmentAction`
- ❌ 不扩 `AbilityActivateFailed` event schema
- ❌ V1 不改 AI 让它候选 env (AI `for target in get_alive_actors()` 只看 character, 这个不动 — 未来要让 AI 主动打墙再加新候选源, V1 不在范围内)

---

## 架构

```
ability metadata
  ├── "range": int                           (现有)
  └── "allowedTargetKinds": Array[String]    (新增, 默认 ["Character"])

ability tags
  └── "enemy" / "ally"                       (现有, 阵营)

can_use_skill_on(actor: CharacterActor, skill: Ability, target: HexBattleActor) -> bool
  ├── target.is_dead() 检查
  ├── 阵营检查 (enemy/ally tag + team)
  ├── range 检查 (skill.get_meta_int("range", 1))
  └── allowed_target_kinds 检查 (新增)
        var allowed := skill.get_meta(ALLOWED_TARGET_KINDS, ["Character"])
        if not target.type in allowed: return false

WallBreaker (新技能, 验证)
  └── ability_config.meta(ALLOWED_TARGET_KINDS, ["Character", "Environment"])
```

**关键签名变化**:
- `can_use_skill_on(actor, skill, target: CharacterActor)` → `target: HexBattleActor`
- 调用方 `ai_strategy.gd:45` 走的是 `for target in battle.get_alive_actors()` 仍只产 character, 不受类型放宽影响
- 未来要让 AI 候选 env 时, 加新候选源 (例如 `get_alive_targetables()`), 不在 V1 范围

---

## 落地顺序 (5 步)

| 步 | 动作 | 文件 |
|---|---|---|
| 1 | 加 metadata key: `const ALLOWED_TARGET_KINDS := "allowedTargetKinds"` | `example/hex-atb-battle/logic/config/skill_meta_keys.gd` |
| 2 | `can_use_skill_on` 加 4-5 行 `allowed_target_kinds` 检查; 签名 target 类型放宽到 `HexBattleActor` | `example/hex-atb-battle/core/hex_world_gameplay_instance.gd` |
| 3 | 写 WallBreaker 验证技能: 单体伤害, `meta(ALLOWED_TARGET_KINDS, ["Character", "Environment"])`. 复用 `CurrentTarget` selector + `DamageAction`. | `example/hex-atb-battle/logic/skills/wall_breaker.gd` |
| 4 | 最小改 headless harness `HexBattleSkillScenarioHarness`: 扩 `run_with_actions` / `_target_cfg_to_ref` / `_resolve_target_ref` 三处, 支持 target ref `"environment_N"` 和 `target_cfg.mode = "environment_index"` | `example/hex-atb-battle/logic/scenario/skill_scenario_harness.gd` |
| 5 | smoke 测试: 见下"验证"段; submodule commit + 主仓库 bump pointer | `example/hex-atb-battle/tests/battle/smoke_wall_breaker.tscn/.gd` |

每步验证后再走下一步.

**注意**: 现有技能不动 (默认 metadata 兜底); 这是相比 v3 最大的收敛 — v3 要给 7 个技能各加一行 condition, v4 零修改.

---

## 验证

| 场景 | 预期 | 断言方式 |
|---|---|---|
| `can_use_skill_on(actor, Strike, wall)` | false | 直接断函数返回值 (默认 metadata `["Character"]`, wall.type == "Environment") |
| `can_use_skill_on(actor, WallBreaker, wall)` | true | 直接断函数返回值 |
| `can_use_skill_on(actor, WallBreaker, character)` | true | 直接断函数返回值 (allowed_kinds 含 Character) |
| WallBreaker 经 harness 命中墙 | DamageEvent push, 墙 hp 减少 | 断 hp delta + event 存在 |
| WallBreaker 打死墙 | 墙死亡, 留 world | `wall.is_dead == true`, world.get_actor(id) 仍可拿到 (依 2026-04-26-death-keeps-actor) |

**不测的场景** (跟 range 同规约, 写下来):
- "harness 直接 cast Strike 选墙会被拦" — 不测. harness 是 testing tool, 直接 fire action 不走 `can_use_skill_on`, 跟"harness 直接 cast Strike 超距打人"同处理. 不是 bug 是规约.
- "AI 选 WallBreaker 会候选墙" — 不测. AI 当前 `for target in get_alive_actors()` 只看 character; V1 不改 AI 候选源. 要真验证这条, 加 V2 task.

---

## 遗留 / 未来

识别出但**不在本轮范围**的同类项:

- **`TargetAllowedCondition` 类的实际登场**: V1 没建. 未来真做 Thorns 反伤 / Adrenaline 打到 character 才叠层 这类**被动技能**时, 是它的本职舞台 — 在被动 condition 列表里挂, 读 event 里的 source/target id 判断 type. 写时再加, 不预先建无消费方的类.
- **AI 候选源扩展**: V1 不让 AI 主动打墙. 要让 AI 在被挡路时砸墙, 需要新候选源 (`get_alive_targetables()` 或类似) + 决策策略 (砸墙 vs 绕路). 加在 AI 层不在 selector 层.
- **`TargetResolution` 返回值结构**: 等 UI / AI 真要查"为什么这个格子高亮 / 这个 selector 给哪些候选"时再做. 当前 `select() -> Array[String]` 够用.
- **多 selector 类型 (allies / dead / range_within / all_environments)**: 真有技能需要再加.
- **CollisionProfile 与 metadata 的关系**: 一个描述物理 (push / blocks_path), 一个描述 cast eligibility (allowed_target_kinds). 暂保持独立, 等真有"既描述物理又描述 targetability"的情况再考虑合并.
- **TargetPolicy 进 SkillPreview UI**: preview UI 需要预先可视化"这个技能能选哪些格子", 直接读 ability metadata 就够, 不需要单独抽象.
- **玩家手动 cast 路径**: 当前 demo 全 AI cast. 未来加玩家 UI 时, 要确保它走 `can_use_skill_on` 校验 (跟 range 同处理). 否则玩家点墙仍会硬打 — 这是规约, 写下来等玩家路径接入时一并处理.

---

## 与 codex 讨论的差异 + 历版本演进

### v4 (本版本) — 走 metadata, 砍掉所有 condition 路径

**起因**: 用户指出 "如何释放的配置应该放在 Ability 配置本身, 不该埋在 Condition 里, 否则 AI 没法事前查."

**改动**:
- 删 `TargetPolicy` 类
- 删 `TargetAllowedCondition` 类 (V1 没消费方)
- 删"给现有 7 个技能加 condition"那批改造 (现有技能零修改)
- `allowed_target_kinds` 走 ability metadata, `can_use_skill_on` 加 5 行
- 验证从"cast 失败拦截 + AbilityActivateFailed 事件"改为"`can_use_skill_on` 返回值断言 + WallBreaker 命中实测"

### v3 — 收编 codex 二审 (TargetPolicy + Condition 路径下的最后一版)

3 个调整:
1. **[P1]** 事件层无法断 condition type. 改用四信号组合归因.
2. **[P2]** Move 不走 `ActiveUseConfig`. 第 3 步候选清单移除 Move; condition pass-through 兜底.
3. **[P2]** harness 文件路径修正为迁移后位置.

### v2 — 收编 codex 一审

1. **[P1]** v1 矛盾"现有技能不动 + Strike 选墙 fail". v2 改: 给现有技能加 `TargetAllowedCondition.character_only()`.
2. **[P1]** v1 不改 harness 但 smoke 要选墙. v2 改: 最小扩 target ref 解析.
3. **[P2]** v1 假设稳定 error code, 实际 schema 没. v2 改: 测试断 condition type + 事件存在性.

### v1 (撤销) — TargetPolicy + Condition 路径初版

codex 提了 4 个新结构 (TargetPolicy + TargetAllowedCondition + TargetResolution + TargetQueryResult), v1 只落前两个. 这条路径在 v4 被"走 metadata"原则全盘替代.

---

## 总结

v1–v3 一直在 condition 路径上找折中, v4 退一步重审, 才发现 condition 不是 cast eligibility 的合理载体. 走 metadata 路径之后, 整个 plan 收敛为:

- **新增 1 行 metadata key**
- **改 ~5 行 `can_use_skill_on`**
- **写 1 个 WallBreaker 技能 (~30 行)**
- **改 ~3 处 harness target ref 解析**
- **写 1 个 smoke (~50 行)**
- **零现有技能修改**

这是该问题的最小落地形态.
