## Timeline Tag 常量
##
## 定义 Timeline 中常用的 Tag 名称，避免硬编码字符串。
## 用于 tagActions 的 key 和 Timeline 定义中的 tags。
class_name TimelineTags


# ========== 通用 Tag ==========

## 开始
const START := "start"

## 结束
const END := "end"


# ========== 攻击 Tag ==========

## 命中（单次）
const HIT := "hit"

## 多段攻击
const HIT1 := "hit1"
const HIT2 := "hit2"
const HIT3 := "hit3"
const HIT4 := "hit4"
const HIT5 := "hit5"


# ========== 施法 Tag ==========

## 施法动作
const CAST := "cast"

## 发射（投射物）
const LAUNCH := "launch"

## 蓄力
const WINDUP := "windup"


# ========== 效果 Tag ==========

## 治疗
const HEAL := "heal"

## 执行（如移动应用）
const EXECUTE := "execute"

## 效果生效
const APPLY := "apply"

## 效果移除
const REMOVE := "remove"
