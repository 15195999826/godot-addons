## HexBattleBuffTags - buff/debuff 分类 tag 的单一来源
##
## 这些 ability_tag 字符串过去散落在各 buff 的 `ability_tags([...])` 声明 +
## cleanse 的分类匹配里, 逐文件硬抄。集中成 const 后:
##   - 新加 buff 引用 const, 不会 typo "negative" 成 "negtive" 导致 cleanse 静默漏清
##   - cleanse 的优先级匹配与 buff 声明用同一来源, 改一处即对齐
##
## 语义约定:
##   - BUFF: 所有 buff/debuff ability 都带 (区分于 skill/passive)
##   - NEGATIVE / POSITIVE: 增益 vs 减益。注意 ward_buff 是防御 buff 却带 NEGATIVE —
##     那是为了让"按 tag 找 buff"逻辑统一处理 (见 ward_buff.gd 头注释), 实际增减益由
##     各 PreEvent/Action 自解释。cleanse 清 NEGATIVE 时会波及 ward — 见设计债文档待评估项。
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
