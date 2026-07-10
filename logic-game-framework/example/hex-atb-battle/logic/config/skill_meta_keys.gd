## 技能元数据 Key 定义
##
## 用于 AbilityConfig.meta(key, value) 的标准化 Key 常量。
## 游戏层通过这些 Key 从 Ability.metadata 中读取技能参数。
class_name HexBattleSkillMetaKeys


## 施法距离（格子数）
## int - 技能可作用的最大六边形距离
const RANGE := "range"


## 允许的目标种类白名单
## Array[String] - 元素取值: "Character" / "Environment"
## 默认 ["Character"]; 要打墙 / 推墙 / 修墙等 env 交互时显式 opt-in。
## 由 can_use_skill_on() 消费; AI / UI / tooltip / 玩家 cast 都查这里。
const ALLOWED_TARGET_KINDS := "allowedTargetKinds"


## 施法输入协议（active 技能必填, manifest lint 强制）
## String - 取值见下方 TARGETING_* 三常量。
## 消费方: AI 构造 activate 事件时按它决定附 target_actor_id 还是 target_coord
## (不再嗅探 "cone" tag); can_use_skill_on 管 ACTOR/SELF, can_use_skill_at 管 COORD。
const TARGETING := "targeting"

## 指向 actor: activate 事件带 target_actor_id
const TARGETING_ACTOR := "actor"
## 指向格子: activate 事件必须带 target_coord(缺失时 selector fail-fast)
const TARGETING_COORD := "coord"
## 自施: 不需要外部目标, 事件 target 即 caster
const TARGETING_SELF := "self"
