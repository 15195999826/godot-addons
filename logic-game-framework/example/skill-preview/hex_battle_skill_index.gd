## HexBattle 技能索引
##
## 服务于 SkillPreview 开发者工具:从 HexBattleAllSkills 总清单派生"玩家可选技能"列表
## (过滤掉 buff / debuff,只留带 "skill" 或 "passive" 标签的)。
##
## active/passive 由 AbilityConfig.active_use_components 字段判定。
##
## 加新技能 = 在 hex-atb-battle/skills/all_skills.gd::_build_manifest() 加一行,这里自动跟随。
class_name HexBattleSkillIndex


## 枚举所有 AbilityConfig (含主动和被动)
static func all() -> Array[AbilityConfig]:
	return _build_all()


## 返回所有 ActiveUse 技能 (active_use_components 非空)
static func actives() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for cfg in _build_all():
		if not cfg.active_use_components.is_empty():
			out.append(cfg)
	return out


## 返回所有纯被动技能 (active_use_components 为空)
static func passives() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for cfg in _build_all():
		if cfg.active_use_components.is_empty():
			out.append(cfg)
	return out


## 按 config_id 查找
static func get_by_id(config_id: String) -> AbilityConfig:
	for cfg in _build_all():
		if cfg.config_id == config_id:
			return cfg
	return null


## 从 HexBattleAllSkills.ALL 派生:保留 skill / passive,过滤 buff / debuff。
## 判定标准:ability_tags 含 "skill" 或 "passive"(buff 标签是 "buff" / "debuff")。
static func _build_all() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for cfg in HexBattleAllSkills.all_abilities():
		if cfg.ability_tags.has("skill") or cfg.ability_tags.has("passive"):
			out.append(cfg)
	return out
