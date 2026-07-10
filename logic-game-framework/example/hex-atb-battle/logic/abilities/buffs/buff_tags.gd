## HexBattleBuffTags - buff/debuff 分类 tag 的单一来源
##
## 这些 ability_tag 字符串过去散落在各 buff 的 `ability_tags([...])` 声明 +
## cleanse 的分类匹配里, 逐文件硬抄。集中成 const 后:
##   - 新加 buff 引用 const, 不会 typo "negative" 成 "negtive" 导致 cleanse 静默漏清
##   - cleanse 的优先级匹配与 buff 声明用同一来源, 改一处即对齐
##
## 语义约定 — ability_tags 两轴模型:
##   - 载体轴 (互斥, 必带一个): "skill" / "passive" / BUFF / "intrinsic" / "status"。
##     BUFF = 可被 grant 的状态实例 (出现在 buff 栏、可被 cleanse 作用、被
##     SkillPreview 选单排除)。被动永远不带 BUFF — "增益被动"的增益语义走极性轴。
##   - 极性轴 (正交, 可挂任何载体; buff 实例必带其一): NEGATIVE / POSITIVE。
##     "是否增益"一律查极性 tag, 与载体无关 (恶魔形态 = passive+positive,
##     护盾 = buff+positive, 中毒 = buff+negative)。
##   - CONTROL: 硬控 (stun/silence/break)。cleanse 最高优先清除。
##   - PASSIVE_BREAK: 破甲类 (break)。cleanse 次优先。
class_name HexBattleBuffTags


## 所有 buff/debuff ability 的基础分类 tag
const TAG_BUFF := "buff"

## 减益 (debuff)
const TAG_NEGATIVE := "negative"

## 增益
const TAG_POSITIVE := "positive"

## 硬控类 (stun / silence / break) — cleanse 最高优先清除
const TAG_CONTROL := "control"

## 破甲类 (break) — cleanse 次优先清除
const TAG_PASSIVE_BREAK := "passive_break"
