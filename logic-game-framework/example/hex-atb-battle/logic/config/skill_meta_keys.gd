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
