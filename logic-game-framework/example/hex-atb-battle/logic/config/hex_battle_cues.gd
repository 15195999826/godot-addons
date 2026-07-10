## HexBattleCues - StageCue cue_id 官方菜单(单一来源)
##
## 收口规则(docs/plan/hex-skill-applayer-convergence-plan.md P3): cue 声明方
## (技能 / Buff 的 StageCueAction 与直接 GameEvent.StageCue.create)和 frontend
## 注册表(stage_cue_visualizer)都必须引用本文件 const —— typo 变编译期错误;
## 想用新 cue 必须先来这里加一行, 动静自然暴露。
##
## 背景: frontend 对未登记 cue **静默跳过**(不报错不显示), 这正是本菜单 +
## manifest lint cue 断言存在的理由。
##
## 分组含义:
## - 有视觉: stage_cue_visualizer 各注册表已消费
## - 有意无视觉: 视觉由投射物动画承载, cue 本身不出效果(visualizer 注释明示)
## - 暂无视觉: 逻辑已 emit、美术未接; manifest lint 豁免名单同步登记
class_name HexBattleCues


# ========== 近战挥击 (frontend MELEE_ATTACK_CUES) ==========

const MELEE_SLASH := "melee_slash"
const MELEE_HEAVY := "melee_heavy"
const MELEE_COMBO := "melee_combo"
const TOTEM_ATTACK := "totem_attack"


# ========== 治疗 (frontend HEAL_CUES) ==========

const MAGIC_HEAL := "magic_heal"


# ========== 斩杀击杀收尾 ==========

const EXECUTE_KILL := "execute_kill"


# ========== 控制 / 进阶技能飘字 (frontend CONTROL_FLOATING_TEXTS) ==========

const CONTROL_STUNNED := "control_stunned"
const CONTROL_SILENCED := "control_silenced"
const CONTROL_BROKEN := "control_broken"
const CONTROL_CLEANSED := "control_cleansed"
const SWAP_BLINK := "swap_blink"
const SUMMON_TOTEM_CAST := "summon_totem_cast"
const FIRE_TILE_CAST := "fire_tile_cast"
const PIERCING_LINE_CAST := "piercing_line_cast"
const LIFESTEAL_DRAIN := "lifesteal_drain"


# ========== 锥形 debug overlay (frontend CONE_DEBUG_CUES) ==========

const GRID_CONE_CAST := "grid_cone_cast"
const ANGLE_CONE_CAST := "angle_cone_cast"


# ========== 有意无视觉 (投射物动画承载, visualizer 明示跳过) ==========

const MAGIC_FIREBALL := "magic_fireball"
const RANGED_ARROW := "ranged_arrow"


# ========== 暂无视觉 (美术未接; manifest lint 豁免名单同步登记) ==========

const DEMON_FORM_PULSE := "demon_form_pulse"
