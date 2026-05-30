# 待办: 28 个技能迁移到 condition bundle helper

> 状态: **未做, 待专门一轮**。helper 已就位 (2026-05-31), 既有技能尚未改用。

## 背景

标准主动技能门控四件套在 ~28 个技能里逐文件 byte-identical 手抄:

```gdscript
.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
.condition(HexBattleCooldownSystem.CooldownCondition.new())
.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
```

手抄是唯一的"正确性保证" —— 正是它让 Strike 漏 Silence 这类漂移在结构上无法与"有意豁免"区分。

## 已就位 (2026-05-31)

1. **helper** (`cooldown_system.gd`):
   - `HexBattleCooldownSystem.apply_standard_active_gating(builder, cooldown_ms)` — 应用 cant_act + silence + cooldown condition + timed cost。
   - `HexBattleCooldownSystem.apply_basic_attack_gating(builder, cooldown_ms)` — silence-exempt 变体 (Strike 用)。
2. **SkillValidator Stage5** (`scripts/SkillValidator.gd`): advisory 检测缺 cant_act / silence 门控 (warn-only), strike/move 具名豁免 (`ADVISORY_CANT_ACT_EXEMPT` / `ADVISORY_SILENCE_EXEMPT`)。新技能漏写门控会被 validator 拎出。

## 待做

把 28 个既有技能的手抄四件套改用 helper:

- **标准技能** (~26 个, 含 silence): `fireball / holy_heal / precise_shot / chain_lightning / poison / expose / stun / silence / break / cleanse / swap / lifesteal / piercing_line / grid_cone / angle_cone / knockback_punch / wall_breaker / execute / crushing_blow / swift_strike / shadow_step / surge / ward / physical_shield / magical_shield / spawn_fire_tile / summon_totem / stance` → `apply_standard_active_gating(builder, COOLDOWN_MS)`。
- **strike** (silence-exempt basic attack) → `apply_basic_attack_gating(builder, COOLDOWN_MS)`, 删原"沉默的省略", 变具名豁免。
- **move** 不碰 (走 ActivateInstanceConfig, 无标准门控)。

## 为何拆出来单独做 (本轮不做)

- 改 28 文件 = 28 处 diff + 全量 hex 回归面, 收益主要是美观/防未来漂移, 不是修 bug。
- 既有 28 技能的门控**目前是对的** (除 strike silence 豁免已确认有意), 只是没用 helper。
- 行尾/BOM 坑刚踩过 (见同期 commit), 批量改 28 文件风险叠加, 不混在 review 收尾里仓促搞。

## 验收

迁移后跑 `./tools/run_tests.ps1 hex/regression hex/skills main/validator` 全绿; 逐文件 diff 应只是门控四件套 → 一行 helper 调用 (无行尾/BOM 噪音, 见 reference_godot_binary memory 的 LF 约定)。
