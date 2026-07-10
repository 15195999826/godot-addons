## HexBattleSkillTags - 技能侧承重 ability_tag 的单一来源
##
## 收口规则(docs/plan/hex-skill-applayer-convergence-plan.md P3): 「有代码消费的」tag
## 收口为 const —— 消费方与声明方引用同一符号, typo 变编译期错误。纯描述性 tag
## (melee / ranged / magic / aoe / line / flavor) 不 const 化, 由 manifest lint 的
## 词表断言兜 typo。
##
## buff 分类轴 (buff / negative / positive / control / passive_break) 的 const 在
## HexBattleBuffTags; 两轴模型(载体互斥 × 极性正交)见其头注释。
class_name HexBattleSkillTags


# ========== 载体轴 (互斥, 必带一个; BUFF 见 HexBattleBuffTags.TAG_BUFF) ==========

## 主动技能载体(与 TAG_ACTIVE 成对出现)
const TAG_SKILL := "skill"
const TAG_ACTIVE := "active"

## 被动载体(Break 的禁用判据消费)
const TAG_PASSIVE := "passive"

## 角色内建规则桥(每角色必有, 不受 Break 影响; general_passive 专用)
const TAG_INTRINSIC := "intrinsic"

## 短时状态(action_lock 专用载体)
const TAG_STATUS := "status"

## actor 生命周期被动(Break 不禁用: totem / fire_tile 的 lifetime)
const TAG_LIFETIME := "lifetime"


# ========== 目标合法性轴 (can_use_skill_on / AI 消费) ==========

const TAG_ENEMY := "enemy"
const TAG_ALLY := "ally"
const TAG_SELF := "self"


# ========== AI 行为分支 ==========

## 治疗技能: AI 走"只治疗残血目标"分支
const TAG_HEAL := "heal"

## 锥形描述。历史上 AI 靠它决定附 target_coord(施法传参协议),
## TARGETING meta 落地后降回纯描述 tag。
const TAG_CONE := "cone"
